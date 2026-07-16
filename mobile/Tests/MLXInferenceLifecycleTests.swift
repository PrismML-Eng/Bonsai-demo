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
        next.continuation.resume(returning: FakeRuntimeResource(modelID: next.modelID))
    }

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

    init(modelID: ModelID) { self.modelID = modelID }

    func configure(_ request: GenerationRequest) {}

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
}
