import Foundation
import Testing
@testable import BonsaiMobile

@Suite("Background download progress bridge")
struct BackgroundDownloadProgressBridgeTests {
    @Test
    func restoredTransferStartsAtPersistedPrefixPlusTaskBytes() async throws {
        let bridge = BackgroundDownloadProgressBridge()
        let recorder = ProgressRecorder()
        let id = UUID()

        bridge.attach(
            id: id,
            existingBytes: 120,
            expectedBytes: 1_000,
            taskBytesReceived: 37,
            progress: { await recorder.append($0) }
        )
        await bridge.flush(id: id)

        #expect(await recorder.values == [157])
    }

    @Test
    func delegateTotalsAreDeliveredExactlyOnceInStrictByteOrder() async throws {
        let bridge = BackgroundDownloadProgressBridge()
        let recorder = ProgressRecorder(suspendsFirstAppend: true)
        let id = UUID()
        bridge.attach(
            id: id,
            existingBytes: 40,
            expectedBytes: 100,
            taskBytesReceived: 0,
            progress: { await recorder.append($0) }
        )

        bridge.report(id: id, taskBytesReceived: 7)
        bridge.report(id: id, taskBytesReceived: 31)
        bridge.report(id: id, taskBytesReceived: 60)
        await recorder.releaseFirstAppend()
        await bridge.flush(id: id)

        #expect(await recorder.values == [40, 47, 71, 100])
        #expect(await recorder.maximumConcurrentAppends == 1)
    }

    @Test
    func detachPreventsQueuedOrLateDelegateProgress() async throws {
        let bridge = BackgroundDownloadProgressBridge()
        let recorder = ProgressRecorder(suspendsFirstAppend: true)
        let id = UUID()
        bridge.attach(
            id: id,
            existingBytes: 0,
            expectedBytes: 100,
            taskBytesReceived: 10,
            progress: { await recorder.append($0) }
        )
        bridge.report(id: id, taskBytesReceived: 20)
        try await recorder.waitUntilFirstAppendStarts()

        bridge.detach(id: id)
        bridge.report(id: id, taskBytesReceived: 30)
        await recorder.releaseFirstAppend()
        await bridge.flush(id: id)

        #expect(await recorder.values == [10])
    }
}

private actor ProgressRecorder {
    private(set) var values: [Int] = []
    private(set) var maximumConcurrentAppends = 0
    private var activeAppends = 0
    private var firstAppendContinuation: CheckedContinuation<Void, Never>?
    private var firstAppendReleased = false
    private var firstAppendStarted = false
    private let suspendsFirstAppend: Bool

    init(suspendsFirstAppend: Bool = false) {
        self.suspendsFirstAppend = suspendsFirstAppend
    }

    func append(_ value: Int) async {
        activeAppends += 1
        maximumConcurrentAppends = max(maximumConcurrentAppends, activeAppends)
        if suspendsFirstAppend, values.isEmpty, !firstAppendReleased {
            firstAppendStarted = true
            await withCheckedContinuation { firstAppendContinuation = $0 }
        }
        values.append(value)
        activeAppends -= 1
    }

    func releaseFirstAppend() {
        firstAppendReleased = true
        firstAppendContinuation?.resume()
        firstAppendContinuation = nil
    }

    func waitUntilFirstAppendStarts() async throws {
        for _ in 0 ..< 100 {
            if firstAppendStarted { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw CocoaError(.fileReadUnknown)
    }
}
