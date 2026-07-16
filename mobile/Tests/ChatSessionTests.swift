import Foundation
import Testing
@testable import BonsaiMobile

@Suite("Chat session lifecycle")
struct ChatSessionTests {
    @Test
    func initialAndSameModelLoadsAreIdempotent() async throws {
        let engine = RecordingInferenceEngine()
        let session = ChatSession(engine: engine)
        let installation = Self.installation(.oneBit27B)

        try await session.load(installation)
        try await session.load(installation)

        #expect(await engine.calls == [.load(.oneBit27B)])
        #expect(await session.snapshot().state == .ready)
    }

    @Test
    func switchingModelsCancelsThenUnloads() async throws {
        let engine = RecordingInferenceEngine()
        let session = ChatSession(engine: engine)

        try await session.load(Self.installation(.oneBit27B))
        try await session.load(Self.installation(.ternary27B))

        #expect(await engine.calls == [
            .load(.oneBit27B), .cancel, .unload, .load(.ternary27B)
        ])
    }

    @Test
    func generationCompletesExactlyOnceAndRecordsOnlyCompleteTurn() async throws {
        let engine = RecordingInferenceEngine(events: [
            .answer("partial"), .answer(" answer"), .completed(.stop), .completed(.stop)
        ])
        let session = ChatSession(engine: engine)
        try await session.load(Self.installation(.oneBit27B))

        let stream = try await session.send(try GenerationRequest(prompt: "question"))
        let events = try await Array(stream)

        #expect(events.filter(\.isTerminal).count == 1)
        #expect(await session.snapshot().completedTurns == [
            .init(user: "question", assistant: "partial answer")
        ])
        #expect(await session.snapshot().state == .ready)
    }

    @Test
    func cancelledGenerationDoesNotRecordPartialTurn() async throws {
        let engine = RecordingInferenceEngine(events: [.answer("partial")], suspendAfterEvents: true)
        let session = ChatSession(engine: engine)
        try await session.load(Self.installation(.oneBit27B))

        let stream = try await session.send(try GenerationRequest(prompt: "question"))
        let consumer = Task { try await Array(stream) }
        await engine.waitUntilGenerating()
        await session.cancel()
        _ = try await consumer.value

        #expect(await engine.calls.suffix(1) == [.cancel])
        #expect(await session.snapshot().completedTurns.isEmpty)
        #expect(await session.snapshot().state == .ready)
    }

    @Test
    func droppedConsumerCancelsUnderlyingGeneration() async throws {
        let engine = RecordingInferenceEngine(events: [.answer("partial")], suspendAfterEvents: true)
        let session = ChatSession(engine: engine)
        try await session.load(Self.installation(.oneBit27B))
        let stream = try await session.send(try GenerationRequest(prompt: "question"))

        let consumer = Task {
            for try await _ in stream {}
        }
        await engine.waitUntilGenerating()
        consumer.cancel()
        _ = try? await consumer.value
        await engine.waitForCancel()

        #expect(await engine.calls.contains(.cancel))
        #expect(await session.snapshot().completedTurns.isEmpty)
    }

    @Test
    func unloadCancelsAndReturnsToIdle() async throws {
        let engine = RecordingInferenceEngine(events: [.answer("partial")], suspendAfterEvents: true)
        let session = ChatSession(engine: engine)
        try await session.load(Self.installation(.oneBit27B))
        _ = try await session.send(try GenerationRequest(prompt: "question"))
        await engine.waitUntilGenerating()

        await session.unload()

        #expect(await engine.calls.suffix(2) == [.cancel, .unload])
        #expect(await session.snapshot().state == .idle)
    }

    @Test
    func lateLoadCompletionCannotOverwriteCompletedUnload() async throws {
        let engine = CancellationInsensitiveLoadingEngine()
        let session = ChatSession(engine: engine)
        let load = Task { () -> Bool in
            do {
                try await session.load(Self.installation(.oneBit27B))
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }
        await engine.waitUntilLoading()

        await session.unload()
        #expect(await session.snapshot().state == .idle)
        await engine.finishLoad()
        #expect(await load.value)

        let snapshot = await session.snapshot()
        #expect(snapshot.state == .idle)
        #expect(snapshot.modelID == nil)
    }

    @Test
    func rejectsConcurrentSendAndLoad() async throws {
        let engine = RecordingInferenceEngine(events: [], suspendAfterEvents: true)
        let session = ChatSession(engine: engine)
        try await session.load(Self.installation(.oneBit27B))
        let activeStream = try await session.send(try GenerationRequest(prompt: "first"))
        await engine.waitUntilGenerating()

        await #expect(throws: ChatSessionError.invalidTransition(from: .generating, action: .send)) {
            _ = try await session.send(try GenerationRequest(prompt: "second"))
        }
        await #expect(throws: ChatSessionError.invalidTransition(from: .generating, action: .load)) {
            try await session.load(Self.installation(.ternary27B))
        }
        withExtendedLifetime(activeStream) {}
        await session.cancel()
    }

    @Test
    func failedGenerationCanRecoverByReloading() async throws {
        let engine = RecordingInferenceEngine(error: TestFailure.boom)
        let session = ChatSession(engine: engine)
        let installation = Self.installation(.oneBit27B)
        try await session.load(installation)

        let stream = try await session.send(try GenerationRequest(prompt: "question"))
        await #expect(throws: TestFailure.boom) { try await Array(stream) }
        #expect(await session.snapshot().state == .failed)

        await engine.setError(nil)
        try await session.load(installation)

        #expect(await session.snapshot().state == .ready)
        #expect(await engine.calls.suffix(3) == [.cancel, .unload, .load(.oneBit27B)])
    }

    private static func installation(_ id: ModelID) -> ModelInstallation {
        ModelInstallation(
            modelID: id,
            directory: URL(fileURLWithPath: "/tmp/\(id.rawValue)"),
            revision: String(repeating: "a", count: 40)
        )
    }
}

private enum TestFailure: Error, Equatable { case boom }

private actor CancellationInsensitiveLoadingEngine: InferenceEngine {
    private var loadContinuation: CheckedContinuation<Void, any Error>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func load(_ installation: ModelInstallation) async throws {
        waiters.forEach { $0.resume() }
        waiters.removeAll()
        try await withCheckedThrowingContinuation { loadContinuation = $0 }
    }

    func generate(
        _ request: GenerationRequest
    ) async throws -> AsyncThrowingStream<GenerationEvent, any Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func cancel() async {}
    func unload() async {}

    func waitUntilLoading() async {
        if loadContinuation != nil { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func finishLoad() {
        loadContinuation?.resume()
        loadContinuation = nil
    }
}

private actor RecordingInferenceEngine: InferenceEngine {
    enum Call: Equatable { case load(ModelID), generate, cancel, unload }

    private(set) var calls: [Call] = []
    private let events: [GenerationEvent]
    private let suspendAfterEvents: Bool
    private var error: (any Error)?
    private var generatingWaiters: [CheckedContinuation<Void, Never>] = []
    private var cancelWaiters: [CheckedContinuation<Void, Never>] = []
    private var generationContinuation: CheckedContinuation<Void, Never>?

    init(
        events: [GenerationEvent] = [.completed(.stop)],
        suspendAfterEvents: Bool = false,
        error: (any Error)? = nil
    ) {
        self.events = events
        self.suspendAfterEvents = suspendAfterEvents
        self.error = error
    }

    func load(_ installation: ModelInstallation) async throws {
        calls.append(.load(installation.modelID))
    }

    func generate(
        _ request: GenerationRequest
    ) async throws -> AsyncThrowingStream<GenerationEvent, any Error> {
        calls.append(.generate)
        generatingWaiters.forEach { $0.resume() }
        generatingWaiters.removeAll()
        let events = events
        let failure = error
        let shouldSuspend = suspendAfterEvents
        return AsyncThrowingStream { continuation in
            let task = Task {
                for event in events { continuation.yield(event) }
                if let failure {
                    continuation.finish(throwing: failure)
                } else if shouldSuspend {
                    await withTaskCancellationHandler {
                        await withCheckedContinuation { self.storeGenerationContinuation($0) }
                    } onCancel: {
                        continuation.yield(.completed(.cancelled))
                    }
                    continuation.finish()
                } else {
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func cancel() async {
        calls.append(.cancel)
        generationContinuation?.resume()
        generationContinuation = nil
        cancelWaiters.forEach { $0.resume() }
        cancelWaiters.removeAll()
    }

    func unload() async {
        calls.append(.unload)
    }

    func setError(_ error: (any Error)?) { self.error = error }

    func waitUntilGenerating() async {
        if calls.contains(.generate) { return }
        await withCheckedContinuation { generatingWaiters.append($0) }
    }

    func waitForCancel() async {
        if calls.contains(.cancel) { return }
        await withCheckedContinuation { cancelWaiters.append($0) }
    }

    private func storeGenerationContinuation(_ continuation: CheckedContinuation<Void, Never>) {
        generationContinuation = continuation
    }
}

private extension GenerationEvent {
    var isTerminal: Bool {
        if case .completed = self { true } else { false }
    }
}

private extension Array {
    init(_ stream: AsyncThrowingStream<Element, any Error>) async throws {
        self = []
        for try await element in stream { append(element) }
    }
}
