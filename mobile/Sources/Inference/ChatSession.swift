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
    private struct ActiveGeneration {
        let id: UUID
        let operation: UInt64
        let task: Task<Void, Never>
    }

    private let engine: any InferenceEngine
    private var state: ChatSessionState = .idle
    private var installation: ModelInstallation?
    private var completedTurns: [CompletedChatTurn] = []
    private var activeGeneration: ActiveGeneration?
    private var currentOperation: UInt64 = 0

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
        let previousState = state
        switch state {
        case .loading:
            throw ChatSessionError.invalidTransition(from: state, action: .load)
        case .ready where self.installation == installation:
            return
        case .generating where self.installation == installation:
            throw ChatSessionError.invalidTransition(from: state, action: .load)
        case .awaitingApproval where self.installation == installation:
            throw ChatSessionError.invalidTransition(from: state, action: .load)
        case .idle, .ready, .generating, .awaitingApproval, .failed:
            break
        }

        let operation = reserve(.loading)
        let generation = activeGeneration
        generation?.task.cancel()
        do {
            if self.installation != nil || previousState != .idle {
                await engine.cancel()
                try ensureCurrent(operation)
                if let generation {
                    await generation.task.value
                    try ensureCurrent(operation)
                    clearGeneration(generation.id)
                }
                await engine.unload()
                try ensureCurrent(operation)
                self.installation = nil
            }

            try await engine.load(installation)
            try ensureCurrent(operation)
            self.installation = installation
            state = .ready
        } catch {
            guard currentOperation == operation else { throw CancellationError() }
            if self.installation == nil {
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

        let operation = reserve(.generating)
        let source: AsyncThrowingStream<GenerationEvent, any Error>
        do {
            source = try await engine.generate(request)
            try ensureCurrent(operation)
        } catch {
            guard currentOperation == operation else { throw CancellationError() }
            state = .ready
            throw error
        }
        let (stream, continuation) = AsyncThrowingStream<GenerationEvent, any Error>.makeStream()
        let id = UUID()
        let task = Task {
            await self.consume(
                source,
                request: request,
                id: id,
                operation: operation,
                continuation: continuation
            )
        }
        activeGeneration = .init(id: id, operation: operation, task: task)
        continuation.onTermination = { [weak self] termination in
            guard case .cancelled = termination else { return }
            Task { await self?.consumerDropped(id: id) }
        }
        return stream
    }

    func cancel() async {
        guard state == .generating else { return }
        let operation = reserve(.generating)
        let generation = activeGeneration
        generation?.task.cancel()
        await engine.cancel()
        guard currentOperation == operation else { return }
        if let generation {
            await generation.task.value
            guard currentOperation == operation else { return }
            clearGeneration(generation.id)
        }
        state = installation == nil ? .idle : .ready
    }

    func unload() async {
        let operation = reserve(.loading)
        let generation = activeGeneration
        generation?.task.cancel()
        await engine.cancel()
        guard currentOperation == operation else { return }
        if let generation {
            await generation.task.value
            guard currentOperation == operation else { return }
            clearGeneration(generation.id)
        }
        await engine.unload()
        guard currentOperation == operation else { return }
        installation = nil
        state = .idle
    }

    private func consume(
        _ source: AsyncThrowingStream<GenerationEvent, any Error>,
        request: GenerationRequest,
        id: UUID,
        operation: UInt64,
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
            try Task.checkCancellation()
            if completion == nil {
                completion = .stop
                continuation.yield(.completed(completion!))
            }
            continuation.finish()
            finishGeneration(
                id: id,
                operation: operation,
                request: request,
                assistant: assistant,
                completion: completion!
            )
        } catch is CancellationError {
            continuation.yield(.completed(.cancelled))
            continuation.finish()
            finishGeneration(
                id: id,
                operation: operation,
                request: request,
                assistant: assistant,
                completion: .cancelled
            )
        } catch {
            continuation.finish(throwing: error)
            failGeneration(id: id, operation: operation)
        }
    }

    private func finishGeneration(
        id: UUID,
        operation: UInt64,
        request: GenerationRequest,
        assistant: String,
        completion: CompletionReason
    ) {
        guard currentOperation == operation,
              activeGeneration?.id == id,
              activeGeneration?.operation == operation else { return }
        activeGeneration = nil
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

    private func failGeneration(id: UUID, operation: UInt64) {
        guard currentOperation == operation,
              activeGeneration?.id == id,
              activeGeneration?.operation == operation else { return }
        activeGeneration = nil
        state = .failed
    }

    private func consumerDropped(id: UUID) async {
        guard let activeGeneration, activeGeneration.id == id else { return }
        await cancel()
    }

    private func reserve(_ reservedState: ChatSessionState) -> UInt64 {
        currentOperation &+= 1
        state = reservedState
        return currentOperation
    }

    private func ensureCurrent(_ operation: UInt64) throws {
        guard currentOperation == operation else { throw CancellationError() }
    }

    private func clearGeneration(_ id: UUID) {
        guard activeGeneration?.id == id else { return }
        activeGeneration = nil
    }
}
