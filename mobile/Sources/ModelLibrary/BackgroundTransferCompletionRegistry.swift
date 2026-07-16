import Foundation

enum BackgroundTransferTaskState: Equatable, Sendable {
    case suspended
    case running
    case canceling
    case completed
}

enum BackgroundRestoredTaskDecision: Equatable, Sendable {
    case resume
    case reattach
    case cancel
}

enum BackgroundRestoredTaskPolicy {
    static func decision(
        isDurablyBound: Bool,
        taskState: BackgroundTransferTaskState
    ) -> BackgroundRestoredTaskDecision {
        guard isDurablyBound else { return .cancel }
        switch taskState {
        case .suspended:
            return .resume
        case .running:
            return .reattach
        case .canceling, .completed:
            return .cancel
        }
    }
}

/// A synchronization boundary between URLSession delegate callbacks and async waiters.
/// Terminal results remain recorded after delivery so duplicate callbacks cannot create
/// a new completion for a later waiter. Call `remove(id:)` after the transfer is retired.
final class BackgroundTransferCompletionRegistry: @unchecked Sendable {
    typealias Completion = @Sendable (Result<Void, any Error>) -> Void

    private enum Entry {
        case waiting(Completion)
        case terminal(Result<Void, any Error>)
        case consumed
    }

    private let lock = NSLock()
    private var entries: [UUID: Entry] = [:]

    func register(id: UUID, completion: @escaping Completion) throws {
        let retainedResult: Result<Void, any Error>? = try lock.withLock {
            switch entries[id] {
            case nil:
                entries[id] = .waiting(completion)
                return nil
            case let .terminal(result):
                entries[id] = .consumed
                return result
            case .waiting, .consumed:
                throw ModelTransportError.duplicateWaiter
            }
        }
        if let retainedResult {
            completion(retainedResult)
        }
    }

    func resolve(id: UUID, result: Result<Void, any Error>) {
        let completion: Completion? = lock.withLock {
            switch entries[id] {
            case nil:
                entries[id] = .terminal(result)
                return nil
            case let .waiting(completion):
                entries[id] = .consumed
                return completion
            case .terminal, .consumed:
                return nil
            }
        }
        completion?(result)
    }

    func remove(id: UUID) {
        _ = lock.withLock { entries.removeValue(forKey: id) }
    }
}
