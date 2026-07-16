import Foundation
import MLXLMCommon
import Testing
@testable import BonsaiMobile

@Suite("Resource pressure recovery")
struct ResourceRecoveryTests {
    @Test
    func criticalRecoveryAwaitsTheExactOrder() async {
        let recoverer = RecordingResourceRecoverer()
        let coordinator = ResourceRecoveryCoordinator(recoverer: recoverer)

        await coordinator.handle(.memoryWarning(count: 1))

        #expect(await recoverer.calls == [
            .cancelGeneration,
            .releaseOptionalVisionState,
            .clearReusableCaches,
            .offerFullUnload
        ])
        #expect(await coordinator.snapshot().fullUnloadOffered)
    }

    @Test
    func concurrentCriticalEventsCoalesceButLaterEpisodeRecoversAgain() async {
        let recoverer = RecordingResourceRecoverer(suspendAtCancel: true)
        let coordinator = ResourceRecoveryCoordinator(recoverer: recoverer)

        async let first: Void = coordinator.handle(.memoryWarning(count: 1))
        await recoverer.waitUntilCancelStarted()
        async let second: Void = coordinator.handle(.thermal(.critical))
        while await coordinator.snapshot().coalescedEventCount == 0 {
            await Task.yield()
        }
        await recoverer.resumeCancel()
        _ = await (first, second)
        await coordinator.handle(.thermal(.critical))

        #expect(await recoverer.calls == [
            .cancelGeneration,
            .releaseOptionalVisionState,
            .clearReusableCaches,
            .offerFullUnload,
            .cancelGeneration,
            .releaseOptionalVisionState,
            .clearReusableCaches,
            .offerFullUnload
        ])
    }

    @Test
    func criticalRecoveryAwaitsAndInvalidatesAnInFlightLoadBeforeCacheClear() async throws {
        let loader = RecoverySuspendingLoader()
        let cache = RecordingCacheClearer()
        let engine = MLXInferenceEngine(loader: loader, cacheClearer: cache)
        let installation = ModelInstallation(
            modelID: .oneBit27B,
            directory: URL(fileURLWithPath: "/tmp/recovery-load"),
            revision: String(repeating: "a", count: 40)
        )
        let load = Task { try await engine.load(installation) }
        await loader.waitUntilStarted()
        let recovery = Task {
            await ResourceRecoveryCoordinator(
                recoverer: MLXResourceRecoverer(engine: engine) {}
            ).handle(.memoryWarning(count: 1))
        }

        await Task.yield()
        #expect(cache.clearCount == 0)
        await loader.resumeWithResource()
        await #expect(throws: CancellationError.self) { try await load.value }
        await recovery.value

        #expect(cache.clearCount == 1)
        let snapshot = await engine.debugSnapshot()
        #expect(!snapshot.hasActiveLoad)
        #expect(!snapshot.hasContainer)
    }

    @Test
    func resourceEventStreamTerminationRemovesRegisteredObservers() async {
        let registrar = RecordingResourceEventRegistrar()
        let source = PlatformResourceEventSource(registrar: registrar)
        let stream = source.events()
        let consumer = Task {
            for await _ in stream {}
        }
        await registrar.waitUntilInstalled()

        consumer.cancel()
        await consumer.value
        await registrar.waitUntilRemoved()

        #expect(await registrar.installCount == 1)
        #expect(await registrar.removeCount == 1)
    }

    @Test
    func liveAdapterClearsPinnedMLXCachesAndPublishesUnloadOffer() async {
        let cache = RecordingCacheClearer()
        let offers = UnloadOfferRecorder()
        let engine = MLXInferenceEngine(cacheClearer: cache)
        let recoverer = MLXResourceRecoverer(engine: engine) {
            await offers.record()
        }
        let coordinator = ResourceRecoveryCoordinator(recoverer: recoverer)

        await coordinator.handle(.memoryWarning(count: 1))

        #expect(cache.clearCount == 1)
        #expect(await offers.count == 1)
    }
}

private actor RecoverySuspendingLoader: MLXRuntimeLoading {
    private var continuation: CheckedContinuation<any MLXRuntimeResource, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func load(_ installation: ModelInstallation) async throws -> any MLXRuntimeResource {
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        return await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilStarted() async {
        if continuation != nil { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func resumeWithResource() {
        continuation?.resume(returning: RecoveryRuntimeResource())
        continuation = nil
    }
}

private final class RecoveryRuntimeResource: MLXRuntimeResource, @unchecked Sendable {
    let reasoningConfig: ReasoningConfig? = nil
    func configure(_ request: GenerationRequest) {}
    func streamDetails(to prompt: String) -> AsyncThrowingStream<MLXLMCommon.Generation, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

private final class RecordingCacheClearer: MLXCacheClearing, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var clearCount: Int { lock.withLock { count } }

    func clear() {
        lock.withLock { count += 1 }
    }
}

private actor UnloadOfferRecorder {
    private(set) var count = 0
    func record() { count += 1 }
}

private actor RecordingResourceRecoverer: ResourceRecovering {
    enum Call: Equatable {
        case cancelGeneration
        case releaseOptionalVisionState
        case clearReusableCaches
        case offerFullUnload
    }

    private(set) var calls: [Call] = []
    private var shouldSuspendAtCancel: Bool
    private var cancelContinuation: CheckedContinuation<Void, Never>?
    private var cancelWaiters: [CheckedContinuation<Void, Never>] = []

    init(suspendAtCancel: Bool = false) {
        self.shouldSuspendAtCancel = suspendAtCancel
    }

    func cancelGeneration() async {
        calls.append(.cancelGeneration)
        cancelWaiters.forEach { $0.resume() }
        cancelWaiters.removeAll()
        if shouldSuspendAtCancel {
            shouldSuspendAtCancel = false
            await withCheckedContinuation { cancelContinuation = $0 }
        }
    }

    func releaseOptionalVisionState() async { calls.append(.releaseOptionalVisionState) }
    func clearReusableCaches() async { calls.append(.clearReusableCaches) }
    func offerFullUnload() async { calls.append(.offerFullUnload) }

    func waitUntilCancelStarted() async {
        if calls.contains(.cancelGeneration) { return }
        await withCheckedContinuation { cancelWaiters.append($0) }
    }

    func resumeCancel() {
        cancelContinuation?.resume()
        cancelContinuation = nil
    }
}

private actor RecordingResourceEventRegistrar: ResourceEventRegistering {
    private(set) var installCount = 0
    private(set) var removeCount = 0
    private var installedWaiters: [CheckedContinuation<Void, Never>] = []
    private var removedWaiters: [CheckedContinuation<Void, Never>] = []

    func install(_ yield: @escaping @Sendable (ResourcePressureEvent) -> Void) async -> UUID {
        installCount += 1
        installedWaiters.forEach { $0.resume() }
        installedWaiters.removeAll()
        return UUID()
    }

    func remove(_ token: UUID) async {
        removeCount += 1
        removedWaiters.forEach { $0.resume() }
        removedWaiters.removeAll()
    }

    func waitUntilInstalled() async {
        if installCount > 0 { return }
        await withCheckedContinuation { installedWaiters.append($0) }
    }

    func waitUntilRemoved() async {
        if removeCount > 0 { return }
        await withCheckedContinuation { removedWaiters.append($0) }
    }
}
