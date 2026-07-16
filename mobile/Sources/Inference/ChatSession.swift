import Foundation

enum ChatSessionState: String, Equatable, Sendable {
    case idle
    case loading
    case ready
    case generating
    case awaitingApproval
    case failed
}

enum ChatSessionAction: String, Equatable, Sendable {
    case load
    case send
}

enum ChatSessionError: Error, Equatable, Sendable {
    case invalidTransition(from: ChatSessionState, action: ChatSessionAction)
}

struct CompletedChatTurn: Equatable, Sendable {
    let user: String
    let assistant: String
}

struct ChatSessionSnapshot: Equatable, Sendable {
    let state: ChatSessionState
    let modelID: ModelID?
    let completedTurns: [CompletedChatTurn]
}

actor ChatSession {
    private let engine: any InferenceEngine
    private var state: ChatSessionState = .idle
    private var installation: ModelInstallation?
    private var completedTurns: [CompletedChatTurn] = []
    private var activeGeneration: (id: UUID, task: Task<Void, Never>)?
    private var activeLoadID: UUID?
    private var cancellationRequested = false

    init(engine: any InferenceEngine) {
        self.engine = engine
    }

    func snapshot() -> ChatSessionSnapshot {
        ChatSessionSnapshot(
            state: state,
            modelID: installation?.modelID,
            completedTurns: completedTurns
        )
    }

    func load(_ installation: ModelInstallation) async throws {
        switch state {
        case .generating, .awaitingApproval:
            throw ChatSessionError.invalidTransition(from: state, action: .load)
        case .loading:
            throw ChatSessionError.invalidTransition(from: state, action: .load)
        case .ready where self.installation == installation:
            return
        case .failed:
            await engine.cancel()
            await engine.unload()
            self.installation = nil
        case .idle, .ready:
            if self.installation != nil {
                await engine.cancel()
                await engine.unload()
                self.installation = nil
            }
        }

        state = .loading
        let loadID = UUID()
        activeLoadID = loadID
        do {
            try await engine.load(installation)
            guard activeLoadID == loadID else { throw CancellationError() }
            activeLoadID = nil
            self.installation = installation
            state = .ready
        } catch {
            if activeLoadID == loadID {
                activeLoadID = nil
                state = .failed
            }
            throw error
        }
    }

    func send(
        _ request: GenerationRequest
    ) async throws -> AsyncThrowingStream<GenerationEvent, any Error> {
        guard state == .ready else {
            throw ChatSessionError.invalidTransition(from: state, action: .send)
        }

        let source = try await engine.generate(request)
        let (stream, continuation) = AsyncThrowingStream<GenerationEvent, any Error>.makeStream()
        let id = UUID()
        state = .generating
        cancellationRequested = false
        let task = Task {
            await self.consume(
                source,
                request: request,
                id: id,
                continuation: continuation
            )
        }
        activeGeneration = (id, task)
        continuation.onTermination = { [weak self] termination in
            guard case .cancelled = termination else { return }
            Task { await self?.consumerDropped(id: id) }
        }
        return stream
    }

    func cancel() async {
        guard let activeGeneration else { return }
        cancellationRequested = true
        activeGeneration.task.cancel()
        await engine.cancel()
        await activeGeneration.task.value
    }

    func unload() async {
        activeLoadID = nil
        await cancel()
        await engine.unload()
        installation = nil
        state = .idle
    }

    private func consume(
        _ source: AsyncThrowingStream<GenerationEvent, any Error>,
        request: GenerationRequest,
        id: UUID,
        continuation: AsyncThrowingStream<GenerationEvent, any Error>.Continuation
    ) async {
        var assistant = ""
        var completion: CompletionReason?
        do {
            for try await event in source {
                try Task.checkCancellation()
                guard completion == nil else { continue }
                if case .answer(let chunk) = event { assistant += chunk }
                if case .completed(let reason) = event { completion = reason }
                continuation.yield(event)
            }
            if completion == nil {
                completion = cancellationRequested ? .cancelled : .stop
                continuation.yield(.completed(completion!))
            }
            continuation.finish()
            finishGeneration(id: id, request: request, assistant: assistant, completion: completion!)
        } catch is CancellationError {
            continuation.yield(.completed(.cancelled))
            continuation.finish()
            finishGeneration(id: id, request: request, assistant: assistant, completion: .cancelled)
        } catch {
            continuation.finish(throwing: error)
            failGeneration(id: id)
        }
    }

    private func finishGeneration(
        id: UUID,
        request: GenerationRequest,
        assistant: String,
        completion: CompletionReason
    ) {
        guard activeGeneration?.id == id else { return }
        activeGeneration = nil
        cancellationRequested = false
        switch completion {
        case .stop, .length:
            completedTurns.append(.init(user: request.prompt, assistant: assistant))
            state = .ready
        case .toolRequest:
            state = .awaitingApproval
        case .cancelled:
            state = .ready
        }
    }

    private func failGeneration(id: UUID) {
        guard activeGeneration?.id == id else { return }
        activeGeneration = nil
        cancellationRequested = false
        state = .failed
    }

    private func consumerDropped(id: UUID) async {
        guard let activeGeneration, activeGeneration.id == id else { return }
        cancellationRequested = true
        activeGeneration.task.cancel()
        await engine.cancel()
        await activeGeneration.task.value
    }
}
