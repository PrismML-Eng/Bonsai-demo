import Foundation
import MLXLMCommon
import Testing
@testable import BonsaiMobile

@Suite("MLX inference load lifecycle")
struct MLXInferenceLifecycleTests {
    @Test
    func sameInstallationLoadsCoalesceIntoOneFactoryTask() async throws {
        let loader = SuspendingRuntimeLoader()
        let engine = MLXInferenceEngine(loader: loader)
        let installation = Self.installation(.oneBit27B)

        let first = Task { try await engine.load(installation) }
        await loader.waitForStarts(1)
        let second = Task { try await engine.load(installation) }
        await Task.yield()

        #expect(await loader.startedModels == [.oneBit27B])
        await loader.finishNext()
        try await first.value
        try await second.value
        #expect(await engine.debugSnapshot() == .loaded(.oneBit27B))
        #expect(await loader.maximumConcurrentLoads == 1)
    }

    @Test
    func unloadCancelsAndAwaitsInFlightCancellationInsensitiveLoad() async {
        let loader = SuspendingRuntimeLoader()
        let engine = MLXInferenceEngine(loader: loader)
        let load = Task { await Self.loadResult(engine, modelID: .oneBit27B) }
        await loader.waitForStarts(1)

        let unload = Task { await engine.unload() }
        await loader.waitForCancellations(1)
        #expect(await engine.debugSnapshot() == .loading)

        await loader.finishNext()
        await unload.value
        _ = await load.value
        #expect(await engine.debugSnapshot() == .empty)
    }

    @Test
    func switchDuringLoadSerializesFactoriesAndOnlyInstallsLatestModel() async throws {
        let loader = SuspendingRuntimeLoader()
        let engine = MLXInferenceEngine(loader: loader)
        let first = Task { await Self.loadResult(engine, modelID: .oneBit27B) }
        await loader.waitForStarts(1)

        let second = Task { try await engine.load(Self.installation(.ternary27B)) }
        await loader.waitForCancellations(1)
        #expect(await loader.startedModels == [.oneBit27B])
        await loader.finishNext()
        await loader.waitForStarts(2)
        await loader.finishNext()

        _ = await first.value
        try await second.value
        #expect(await loader.maximumConcurrentLoads == 1)
        #expect(await engine.debugSnapshot() == .loaded(.ternary27B))
    }

    @Test
    func lateLoaderReturnAfterUnloadCannotInstallResources() async {
        let loader = SuspendingRuntimeLoader()
        let engine = MLXInferenceEngine(loader: loader)
        let load = Task { await Self.loadResult(engine, modelID: .oneBit27B) }
        await loader.waitForStarts(1)
        let unload = Task { await engine.unload() }

        await loader.waitForCancellations(1)
        await loader.finishNext()
        await unload.value
        _ = await load.value

        #expect(await engine.debugSnapshot() == .empty)
        #expect(await loader.returnedResources == 1)
    }

    @Test
    func optionalVisionReleaseDropsSessionButRetainsLoadedWeightsAndRecreatesSession() async throws {
        let loader = SuspendingRuntimeLoader()
        let engine = MLXInferenceEngine(loader: loader)
        let installation = Self.installation(.oneBit27B)
        let load = Task { try await engine.load(installation) }
        await loader.waitForStarts(1)
        await loader.finishNext()
        try await load.value

        await engine.releaseOptionalVisionState()
        #expect(await engine.debugSnapshot() == .loadedWithoutSession(.oneBit27B))

        let stream = try await engine.generate(
            try GenerationRequest(prompt: "next", reasoningEnabled: false)
        )
        for try await _ in stream {}
        #expect(await engine.debugSnapshot() == .loaded(.oneBit27B))
    }

    @Test
    func tokenizerBackedContextCompositionTrimsWithoutChangingRuntimeState() async throws {
        let loader = SuspendingRuntimeLoader(tokenCounts: [
            "system": 100,
            "old-user": 1_200,
            "old-assistant": 1_300,
            "new-user": 1_000,
            "new-assistant": 1_000
        ])
        let engine = MLXInferenceEngine(loader: loader)
        let load = Task { try await engine.load(Self.installation(.oneBit27B)) }
        await loader.waitForStarts(1)
        await loader.finishNext()
        try await load.value
        let before = await engine.debugSnapshot()

        let result = try await engine.trimContext(Self.contextConversation())

        #expect(result.keptTokenCount == 2_100)
        #expect(result.removedMessageIDs.map(\.rawValue) == ["old-user", "old-assistant"])
        #expect(await engine.debugSnapshot() == before)
        #expect(await loader.tokenCountRequestCount == 1)
    }

    private static func contextConversation() throws -> Conversation {
        try Conversation(
            id: ConversationID("context"),
            modelID: .oneBit27B,
            modelRevision: String(repeating: "a", count: 40),
            revision: 1,
            systemInstruction: .init(id: MessageID("system"), role: .system, content: "system"),
            completedTurns: [
                .init(id: "old", messages: [
                    .init(id: MessageID("old-user"), role: .user, content: "old user"),
                    .init(id: MessageID("old-assistant"), role: .assistant, content: "old answer")
                ]),
                .init(id: "new", messages: [
                    .init(id: MessageID("new-user"), role: .user, content: "new user"),
                    .init(id: MessageID("new-assistant"), role: .assistant, content: "new answer")
                ])
            ]
        )
    }

    private static func installation(_ id: ModelID) -> ModelInstallation {
        ModelInstallation(
            modelID: id,
            directory: URL(fileURLWithPath: "/tmp/\(id.rawValue)"),
            revision: String(repeating: "a", count: 40)
        )
    }

    private static func loadResult(
        _ engine: MLXInferenceEngine,
        modelID: ModelID
    ) async -> Result<Void, any Error> {
        do {
            try await engine.load(installation(modelID))
            return .success(())
        } catch {
            return .failure(error)
        }
    }
}

private actor SuspendingRuntimeLoader: MLXRuntimeLoading {
    private struct Pending {
        let modelID: ModelID
        let continuation: CheckedContinuation<any MLXRuntimeResource, Never>
    }

    private var pending: [Pending] = []
    private var startWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var cancellationWaiters: [
        (count: Int, continuation: CheckedContinuation<Void, Never>)
    ] = []
    private(set) var startedModels: [ModelID] = []
    private(set) var maximumConcurrentLoads = 0
    private(set) var returnedResources = 0
    private var cancellationCount = 0
    private var concurrentLoads = 0
    private let tokenCounts: [String: Int]
    private(set) var tokenCountRequestCount = 0

    init(tokenCounts: [String: Int] = [:]) {
        self.tokenCounts = tokenCounts
    }

    func load(_ installation: ModelInstallation) async throws -> any MLXRuntimeResource {
        startedModels.append(installation.modelID)
        concurrentLoads += 1
        maximumConcurrentLoads = max(maximumConcurrentLoads, concurrentLoads)
        resumeStartWaiters()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                pending.append(.init(modelID: installation.modelID, continuation: continuation))
            }
        } onCancel: {
            Task { await self.recordCancellation() }
        }
    }

    func waitForStarts(_ count: Int) async {
        if startedModels.count >= count { return }
        await withCheckedContinuation { startWaiters.append((count, $0)) }
    }

    func waitForCancellations(_ count: Int) async {
        if cancellationCount >= count { return }
        await withCheckedContinuation { cancellationWaiters.append((count, $0)) }
    }

    func finishNext() {
        let next = pending.removeFirst()
        concurrentLoads -= 1
        returnedResources += 1
        next.continuation.resume(
            returning: FakeRuntimeResource(
                modelID: next.modelID,
                tokenCounts: tokenCounts,
                didCountTokens: { await self.recordTokenCountRequest() }
            )
        )
    }

    private func recordTokenCountRequest() { tokenCountRequestCount += 1 }

    private func resumeStartWaiters() {
        let ready = startWaiters.filter { startedModels.count >= $0.count }
        startWaiters.removeAll { startedModels.count >= $0.count }
        ready.forEach { $0.continuation.resume() }
    }

    private func recordCancellation() {
        cancellationCount += 1
        let ready = cancellationWaiters.filter { cancellationCount >= $0.count }
        cancellationWaiters.removeAll { cancellationCount >= $0.count }
        ready.forEach { $0.continuation.resume() }
    }
}

private final class FakeRuntimeResource: MLXRuntimeResource, @unchecked Sendable {
    let modelID: ModelID
    let reasoningConfig: ReasoningConfig? = nil
    private(set) var hasSession = true
    private let tokenCounts: [String: Int]
    private let didCountTokens: @Sendable () async -> Void

    init(
        modelID: ModelID,
        tokenCounts: [String: Int] = [:],
        didCountTokens: @escaping @Sendable () async -> Void = {}
    ) {
        self.modelID = modelID
        self.tokenCounts = tokenCounts
        self.didCountTokens = didCountTokens
    }

    func configure(_ request: GenerationRequest) { hasSession = true }

    func releaseOptionalSession() { hasSession = false }

    func tokenCounts(for messages: [ConversationMessage]) async throws -> [MessageID: Int] {
        await didCountTokens()
        return Dictionary(uniqueKeysWithValues: messages.map {
            ($0.id, tokenCounts[$0.id.rawValue, default: 1])
        })
    }

    func streamDetails(to prompt: String) -> AsyncThrowingStream<MLXLMCommon.Generation, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

private extension MLXInferenceEngine.DebugSnapshot {
    static var empty: Self {
        .init(
            loadedModelID: nil,
            hasContainer: false,
            hasSession: false,
            hasActiveGeneration: false,
            hasActiveLoad: false
        )
    }

    static var loading: Self {
        .init(
            loadedModelID: nil,
            hasContainer: false,
            hasSession: false,
            hasActiveGeneration: false,
            hasActiveLoad: true
        )
    }

    static func loaded(_ modelID: ModelID) -> Self {
        .init(
            loadedModelID: modelID,
            hasContainer: true,
            hasSession: true,
            hasActiveGeneration: false,
            hasActiveLoad: false
        )
    }

    static func loadedWithoutSession(_ modelID: ModelID) -> Self {
        .init(
            loadedModelID: modelID,
            hasContainer: true,
            hasSession: false,
            hasActiveGeneration: false,
            hasActiveLoad: false
        )
    }
}
