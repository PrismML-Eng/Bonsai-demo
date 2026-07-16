import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The only unchecked Sendable boundary for the URLSession object graph. Every
/// access to mutable session ownership is serialized by `lock`.
final class BackgroundURLSessionOwner: @unchecked Sendable {
    private let lock = NSLock()
    private let configuration: URLSessionConfiguration
    private var storedSession: URLSession?

    init(configuration: URLSessionConfiguration) {
        self.configuration = configuration
    }

    func session(delegate: URLSessionDelegate) -> URLSession {
        lock.withLock {
            if let storedSession { return storedSession }
            let created = URLSession(
                configuration: configuration,
                delegate: delegate,
                delegateQueue: nil
            )
            storedSession = created
            return created
        }
    }
}

/// URLSession tasks and UIKit lifecycle closures are protected by this lock;
/// callers never receive access to the mutable dictionaries themselves.
final class BackgroundDownloadCoordinatorState: @unchecked Sendable {
    private let lock = NSLock()
    private var tasks: [UUID: URLSessionDownloadTask] = [:]
    private var backgroundEventsCompletion: (@Sendable () -> Void)?

    func task(id: UUID) -> URLSessionDownloadTask? {
        lock.withLock { tasks[id] }
    }

    func store(task: URLSessionDownloadTask, id: UUID) {
        lock.withLock { tasks[id] = task }
    }

    func removeTask(id: UUID) {
        _ = lock.withLock { tasks.removeValue(forKey: id) }
    }

    func setBackgroundEventsCompletion(_ completion: @escaping @Sendable () -> Void) {
        lock.withLock { backgroundEventsCompletion = completion }
    }

    func takeBackgroundEventsCompletion() -> (@Sendable () -> Void)? {
        lock.withLock {
            defer { backgroundEventsCompletion = nil }
            return backgroundEventsCompletion
        }
    }
}

actor BackgroundReconciliationGate {
    private var isAcquired = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        guard isAcquired else {
            isAcquired = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        guard !waiters.isEmpty else {
            isAcquired = false
            return
        }
        waiters.removeFirst().resume()
    }
}

struct BackgroundDurableCompletionResolver {
    func reuse(
        using ledger: BackgroundTransferLedger,
        file: ModelManifest.File,
        destination: URL
    ) async throws -> Bool {
        let records = await ledger.completedRecords(destination: destination)
        var reused = false
        for record in records {
            let metadataMatches = record.expectedSize == file.sizeBytes &&
                record.sha256.caseInsensitiveCompare(file.sha256) == .orderedSame
            if !reused, metadataMatches,
               (try? SHA256Verifier().verify(file, at: destination)) != nil {
                reused = true
            } else {
                try await ledger.remove(id: record.id)
            }
        }
        return reused
    }
}
