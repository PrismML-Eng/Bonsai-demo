import Foundation
import Testing
@testable import BonsaiMobile

@Suite("Chat session operation reservations")
struct ChatSessionConcurrencyTests {
    @Test
    func sendReservesGeneratingBeforeEngineAcquisitionAndRejectsSecondSend() async throws {
        let engine = SuspendingInferenceEngine()
        let session = ChatSession(engine: engine)
        try await session.load(Self.installation(.oneBit27B))
        await engine.suspendNext(.generate)

        let first = Task { try await session.send(try GenerationRequest(prompt: "first")) }
        await engine.waitUntilEntered(.generate)

        #expect(await session.snapshot().state == .generating)
        await #expect(throws: ChatSessionError.invalidTransition(from: .generating, action: .send)) {
            _ = try await session.send(try GenerationRequest(prompt: "second"))
        }

        await engine.resume(.generate)
        let stream = try await first.value
        _ = try await Array(stream)
        #expect(await session.snapshot().state == .ready)
    }

    @Test
    func switchSupersedesSendSuspendedInGenerateAndRunsCancelUnloadLoad() async throws {
        let engine = SuspendingInferenceEngine()
        let session = ChatSession(engine: engine)
        try await session.load(Self.installation(.oneBit27B))
        await engine.suspendNext(.generate)
        await engine.suspendNext(.cancel)

        let send = Task { await Self.sendResult(session, prompt: "question") }
        await engine.waitUntilEntered(.generate)
        let switching = Task { try await session.load(Self.installation(.ternary27B)) }
        await Self.waitForState(.loading, in: session)

        #expect(await session.snapshot().state == .loading)
        await engine.resume(.generate)
        await engine.resume(.cancel)
        try await switching.value
        #expect(Self.isCancellation(await send.value))
        #expect(await engine.calls == [
            .load(.oneBit27B), .generate, .cancel, .unload, .load(.ternary27B)
        ])
        #expect(await session.snapshot() == .init(
            state: .ready,
            modelID: .ternary27B,
            completedTurns: []
        ))
    }

    @Test
    func unloadSupersedesSendSuspendedInGenerateWithoutLateStateMutation() async throws {
        let engine = SuspendingInferenceEngine()
        let session = ChatSession(engine: engine)
        try await session.load(Self.installation(.oneBit27B))
        await engine.suspendNext(.generate)
        await engine.suspendNext(.unload)

        let send = Task { await Self.sendResult(session, prompt: "question") }
        await engine.waitUntilEntered(.generate)
        let unload = Task { await session.unload() }
        await Self.waitForState(.loading, in: session)

        #expect(await session.snapshot().state == .loading)
        await engine.resume(.generate)
        await engine.resume(.unload)
        await unload.value
        #expect(Self.isCancellation(await send.value))
        #expect(await session.snapshot() == .init(state: .idle, modelID: nil, completedTurns: []))
    }

    @Test
    func unloadSupersedesSwitchSuspendedInEngineUnload() async throws {
        let engine = SuspendingInferenceEngine()
        let session = ChatSession(engine: engine)
        try await session.load(Self.installation(.oneBit27B))
        await engine.suspendNext(.unload)

        let switching = Task { await Self.loadResult(session, modelID: .ternary27B) }
        await engine.waitUntilEntered(.unload)
        let unload = Task { await session.unload() }
        await engine.waitUntilEntered(.unload, count: 2)
        await unload.value

        await engine.resume(.unload)
        #expect(Self.isCancellation(await switching.value))
        #expect(await session.snapshot() == .init(state: .idle, modelID: nil, completedTurns: []))
        #expect(await engine.calls.filter { if case .load(.ternary27B) = $0 { true } else { false } }.isEmpty)
    }

    @Test
    func switchDuringActiveGenerationCancelsBeforeUnloadAndNeverRecordsPartialTurn() async throws {
        let engine = SuspendingInferenceEngine(holdsGeneration: true)
        let session = ChatSession(engine: engine)
        try await session.load(Self.installation(.oneBit27B))

        let stream = try await session.send(try GenerationRequest(prompt: "question"))
        let consumer = Task { try await Array(stream) }
        await engine.waitForHeldGeneration()
        await engine.yieldPartialAnswer()
        await Task.yield()
        await engine.suspendNext(.cancel)

        let switching = Task { try await session.load(Self.installation(.ternary27B)) }
        await Self.waitForState(.loading, in: session)
        #expect(await session.snapshot().state == .loading)
        await engine.resume(.cancel)
        try await switching.value
        _ = try await consumer.value

        #expect(await engine.calls == [
            .load(.oneBit27B), .generate, .cancel, .unload, .load(.ternary27B)
        ])
        #expect(await session.snapshot().completedTurns.isEmpty)
        #expect(await session.snapshot().state == .ready)
    }

    @Test
    func acquisitionAndReplacementFailuresLeaveTruthfulState() async throws {
        let engine = SuspendingInferenceEngine()
        let session = ChatSession(engine: engine)
        try await session.load(Self.installation(.oneBit27B))

        await engine.failNextGenerate(TestOperationFailure.boom)
        await #expect(throws: TestOperationFailure.boom) {
            _ = try await session.send(try GenerationRequest(prompt: "question"))
        }
        #expect(await session.snapshot() == .init(
            state: .ready,
            modelID: .oneBit27B,
            completedTurns: []
        ))

        await engine.failNextLoad(TestOperationFailure.boom)
        await #expect(throws: TestOperationFailure.boom) {
            try await session.load(Self.installation(.ternary27B))
        }
        #expect(await session.snapshot() == .init(state: .failed, modelID: nil, completedTurns: []))
    }

    private static func installation(_ id: ModelID) -> ModelInstallation {
        ModelInstallation(
            modelID: id,
            directory: URL(fileURLWithPath: "/tmp/\(id.rawValue)"),
            revision: String(repeating: "a", count: 40)
        )
    }

    private static func sendResult(
        _ session: ChatSession,
        prompt: String
    ) async -> Result<AsyncThrowingStream<GenerationEvent, any Error>, any Error> {
        do {
            return .success(try await session.send(try GenerationRequest(prompt: prompt)))
        } catch {
            return .failure(error)
        }
    }

    private static func loadResult(
        _ session: ChatSession,
        modelID: ModelID
    ) async -> Result<Void, any Error> {
        do {
            try await session.load(installation(modelID))
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    private static func isCancellation<T>(_ result: Result<T, any Error>) -> Bool {
        guard case .failure(let error) = result else { return false }
        return error is CancellationError
    }

    private static func waitForState(_ state: ChatSessionState, in session: ChatSession) async {
        for _ in 0..<1_000 {
            if await session.snapshot().state == state { return }
            await Task.yield()
        }
    }
}

private enum TestOperationFailure: Error, Equatable { case boom }

private actor SuspendingInferenceEngine: InferenceEngine {
    enum Point: Hashable, Sendable { case load, generate, cancel, unload }
    enum Call: Equatable, Sendable { case load(ModelID), generate, cancel, unload }

    private(set) var calls: [Call] = []
    private var blocked: Set<Point> = []
    private var pending: [Point: [CheckedContinuation<Void, Never>]] = [:]
    private var entered: [Point: Int] = [:]
    private var enteredWaiters: [
        Point: [(count: Int, continuation: CheckedContinuation<Void, Never>)]
    ] = [:]
    private var nextLoadError: (any Error)?
    private var nextGenerateError: (any Error)?
    private let holdsGeneration: Bool
    private var heldGeneration: AsyncThrowingStream<GenerationEvent, any Error>.Continuation?
    private var generationWaiters: [CheckedContinuation<Void, Never>] = []

    init(holdsGeneration: Bool = false) {
        self.holdsGeneration = holdsGeneration
    }

    func load(_ installation: ModelInstallation) async throws {
        calls.append(.load(installation.modelID))
        await pause(.load)
        if let error = nextLoadError {
            nextLoadError = nil
            throw error
        }
    }

    func generate(
        _ request: GenerationRequest
    ) async throws -> AsyncThrowingStream<GenerationEvent, any Error> {
        calls.append(.generate)
        await pause(.generate)
        if let error = nextGenerateError {
            nextGenerateError = nil
            throw error
        }
        guard holdsGeneration else {
            return AsyncThrowingStream {
                $0.yield(.completed(.stop))
                $0.finish()
            }
        }
        return AsyncThrowingStream { continuation in
            storeHeldGeneration(continuation)
        }
    }

    func cancel() async {
        calls.append(.cancel)
        await pause(.cancel)
        heldGeneration?.yield(.completed(.cancelled))
        heldGeneration?.finish()
        heldGeneration = nil
    }

    func unload() async {
        calls.append(.unload)
        await pause(.unload)
    }

    func suspendNext(_ point: Point) { blocked.insert(point) }

    func resume(_ point: Point) {
        blocked.remove(point)
        let continuations = pending.removeValue(forKey: point) ?? []
        continuations.forEach { $0.resume() }
    }

    func waitUntilEntered(_ point: Point, count: Int = 1) async {
        if entered[point, default: 0] >= count { return }
        await withCheckedContinuation { enteredWaiters[point, default: []].append((count, $0)) }
    }

    func failNextLoad(_ error: any Error) { nextLoadError = error }
    func failNextGenerate(_ error: any Error) { nextGenerateError = error }

    func waitForHeldGeneration() async {
        if heldGeneration != nil { return }
        await withCheckedContinuation { generationWaiters.append($0) }
    }

    func yieldPartialAnswer() {
        heldGeneration?.yield(.answer("partial"))
    }

    private func pause(_ point: Point) async {
        entered[point, default: 0] += 1
        let count = entered[point, default: 0]
        let ready = enteredWaiters[point, default: []].filter { count >= $0.count }
        enteredWaiters[point, default: []].removeAll { count >= $0.count }
        guard blocked.remove(point) != nil else {
            ready.forEach { $0.continuation.resume() }
            return
        }
        await withCheckedContinuation {
            pending[point, default: []].append($0)
            ready.forEach { $0.continuation.resume() }
        }
    }

    private func storeHeldGeneration(
        _ continuation: AsyncThrowingStream<GenerationEvent, any Error>.Continuation
    ) {
        heldGeneration = continuation
        generationWaiters.forEach { $0.resume() }
        generationWaiters.removeAll()
    }
}

private extension Array {
    init(_ stream: AsyncThrowingStream<Element, any Error>) async throws {
        self = []
        for try await element in stream { append(element) }
    }
}
