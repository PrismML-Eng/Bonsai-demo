import Foundation
import Testing
@testable import BonsaiMobile

@Suite("Background transfer completion registry")
struct TransferCompletionRegistryTests {
    @Test
    func terminalBeforeRegistrationIsRetainedUntilExactlyOneConsumption() throws {
        let registry = BackgroundTransferCompletionRegistry()
        let id = UUID()
        let observations = LockedObservations()

        registry.resolve(id: id, result: .success(()))
        registry.resolve(id: id, result: .failure(ModelTransportError.invalidResponse))
        try registry.register(id: id) { observations.append($0) }
        registry.resolve(id: id, result: .failure(ModelTransportError.invalidContentRange))

        #expect(observations.count == 1)
        #expect(observations.firstSucceeded)
    }

    @Test
    func completionRacingRegistrationAlwaysDeliversExactlyOnce() async throws {
        let registry = BackgroundTransferCompletionRegistry()
        let observations = LockedObservations()

        for _ in 0 ..< 200 {
            let id = UUID()
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    try? registry.register(id: id) { observations.append($0) }
                }
                group.addTask {
                    registry.resolve(id: id, result: .success(()))
                }
            }
        }

        #expect(observations.count == 200)
        #expect(observations.successCount == 200)
    }

    @Test
    func duplicateWaiterIsTypedAndDoesNotReplaceOriginal() throws {
        let registry = BackgroundTransferCompletionRegistry()
        let id = UUID()
        let observations = LockedObservations()
        try registry.register(id: id) { observations.append($0) }

        #expect(throws: ModelTransportError.duplicateWaiter) {
            try registry.register(id: id) { _ in }
        }
        registry.resolve(id: id, result: .success(()))

        #expect(observations.count == 1)
    }
}

@Suite("Restored background task policy")
struct BackgroundRestoredTaskPolicyTests {
    @Test
    func durablyBoundSuspendedTaskMustResume() {
        #expect(
            BackgroundRestoredTaskPolicy.decision(isDurablyBound: true, taskState: .suspended) == .resume
        )
    }

    @Test
    func runningTaskReattachesWithoutExtraResume() {
        #expect(
            BackgroundRestoredTaskPolicy.decision(isDurablyBound: true, taskState: .running) == .reattach
        )
    }

    @Test(arguments: [BackgroundTransferTaskState.suspended, .running, .canceling, .completed])
    func unboundOrTerminalTasksCancel(_ state: BackgroundTransferTaskState) {
        #expect(BackgroundRestoredTaskPolicy.decision(isDurablyBound: false, taskState: state) == .cancel)
        if state == .canceling || state == .completed {
            #expect(BackgroundRestoredTaskPolicy.decision(isDurablyBound: true, taskState: state) == .cancel)
        }
    }
}

private final class LockedObservations: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<Void, any Error>] = []

    var count: Int { lock.withLock { results.count } }
    var successCount: Int { lock.withLock { results.filter(\.isSuccess).count } }
    var firstSucceeded: Bool { lock.withLock { results.first?.isSuccess == true } }

    func append(_ result: Result<Void, any Error>) {
        lock.withLock { results.append(result) }
    }
}

private extension Result where Success == Void, Failure == any Error {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
