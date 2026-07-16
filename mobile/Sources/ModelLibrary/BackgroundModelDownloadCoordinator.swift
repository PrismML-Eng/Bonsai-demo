#if os(iOS)
import Foundation

final class BackgroundModelDownloadCoordinator: NSObject, @unchecked Sendable {
    static let sessionIdentifier = "com.prismml.BonsaiMobile.model-download"
    static let shared = BackgroundModelDownloadCoordinator.makeShared()

    private let lock = NSLock()
    private let ledger: BackgroundTransferLedger?
    private let downloadsRoot: URL?
    private let initializationError: Error?
    private var continuations: [UUID: CheckedContinuation<Void, Error>] = [:]
    private var tasks: [UUID: URLSessionDownloadTask] = [:]
    private var durableDownloads: [Int: URL] = [:]
    private var backgroundEventsCompletion: (@Sendable () -> Void)?

    private lazy var session: URLSession = {
        let configuration = URLSessionModelFileTransport.productionConfiguration()
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    private init(ledger: BackgroundTransferLedger?, downloadsRoot: URL?, error: Error?) {
        self.ledger = ledger
        self.downloadsRoot = downloadsRoot
        initializationError = error
        super.init()
    }

    func download(_ file: ModelManifest.File, from source: URL, to destination: URL) async throws {
        guard let ledger else { throw initializationError ?? CocoaError(.fileWriteUnknown) }
        guard source.scheme?.lowercased() == "https" else { throw ModelTransportError.insecureURL }
        try await reconcileTasks(using: ledger)

        if let previous = await ledger.activeRecord(destination: destination) {
            if previous.state == .running, let task = lock.withLock({ tasks[previous.id] }) {
                try await awaitCompletion(of: previous.id, task: task, startsTask: false)
                return
            }
            try await ledger.remove(id: previous.id)
        }

        let existingBytes = Self.fileSize(at: destination)
        let record = try await ledger.create(
            source: source,
            destination: destination,
            expectedSize: file.sizeBytes,
            sha256: file.sha256,
            existingBytes: existingBytes
        )
        var request = URLRequest(url: source)
        request.httpMethod = "GET"
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if existingBytes > 0, existingBytes < file.sizeBytes {
            request.setValue("bytes=\(existingBytes)-", forHTTPHeaderField: "Range")
        }
        let task = session.downloadTask(with: request)
        task.taskDescription = record.taskDescription
        try await ledger.bind(id: record.id, taskIdentifier: task.taskIdentifier)
        lock.withLock { tasks[record.id] = task }
        try await awaitCompletion(of: record.id, task: task, startsTask: true)
    }

    func restoreBackgroundTasks() {
        guard let ledger else { return }
        Task { try? await reconcileTasks(using: ledger) }
    }

    func setBackgroundEventsCompletion(_ completion: @escaping @Sendable () -> Void) {
        lock.withLock { backgroundEventsCompletion = completion }
        restoreBackgroundTasks()
    }

    private func awaitCompletion(
        of id: UUID,
        task: URLSessionDownloadTask,
        startsTask: Bool
    ) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let replaced = lock.withLock { continuations.updateValue(continuation, forKey: id) }
                replaced?.resume(throwing: ModelLibraryError.operationInProgress)
                if startsTask { task.resume() }
            }
        } onCancel: {
            task.cancel()
        }
    }

    private func reconcileTasks(using ledger: BackgroundTransferLedger) async throws {
        let allTasks = await withCheckedContinuation { continuation in
            session.getAllTasks { continuation.resume(returning: $0) }
        }
        let identities = allTasks.map {
            BackgroundTransferTaskIdentity(
                taskIdentifier: $0.taskIdentifier,
                taskDescription: $0.taskDescription
            )
        }
        let reconciliation = try await ledger.reconcile(tasks: identities)
        let byIdentifier = Dictionary(uniqueKeysWithValues: allTasks.map { ($0.taskIdentifier, $0) })
        for identifier in reconciliation.taskIdentifiersToCancel {
            byIdentifier[identifier]?.cancel()
        }
        lock.withLock {
            for attachment in reconciliation.reattached {
                if let task = byIdentifier[attachment.taskIdentifier] as? URLSessionDownloadTask {
                    tasks[attachment.transferID] = task
                }
            }
        }
    }

    private func finalize(task: URLSessionTask, error: Error?) async {
        guard let ledger, let description = task.taskDescription,
              let id = UUID(uuidString: description),
              let record = await ledger.record(id: id) else {
            resolve(id: task.taskDescription.flatMap(UUID.init(uuidString:)), result: .failure(
                ModelTransportError.invalidResponse
            ))
            return
        }
        do {
            if let error { throw error }
            guard let http = task.response as? HTTPURLResponse else {
                throw ModelTransportError.invalidResponse
            }
            guard (200 ... 299).contains(http.statusCode) else {
                throw ModelTransportError.httpStatus(http.statusCode)
            }
            let downloaded = try lock.withLock { () throws -> URL in
                guard let url = durableDownloads.removeValue(forKey: task.taskIdentifier) else {
                    throw ModelTransportError.invalidResponse
                }
                return url
            }
            try Self.promote(downloaded, response: http, record: record)
            try await ledger.finish(id: id, failure: nil, isResumable: false)
            resolve(id: id, result: .success(()))
        } catch {
            let resumable = Self.isResumable(error)
            try? await ledger.finish(id: id, failure: String(describing: error), isResumable: resumable)
            resolve(id: id, result: .failure(error))
        }
    }

    private func resolve(id: UUID?, result: Result<Void, Error>) {
        guard let id else { return }
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Error>? in
            tasks.removeValue(forKey: id)
            return continuations.removeValue(forKey: id)
        }
        continuation?.resume(with: result)
    }

    private static func promote(
        _ downloaded: URL,
        response: HTTPURLResponse,
        record: BackgroundTransferRecord
    ) throws {
        let append = record.existingBytes > 0 && response.statusCode == 206
        if append, !URLSessionModelFileTransport.contentRangeStarts(
            response.value(forHTTPHeaderField: "Content-Range"),
            at: record.existingBytes
        ) {
            throw ModelTransportError.invalidContentRange
        }
        try FileManager.default.createDirectory(
            at: record.destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if append {
            let output = try FileHandle(forWritingTo: record.destination)
            defer { try? output.close() }
            try output.seekToEnd()
            let input = try FileHandle(forReadingFrom: downloaded)
            defer { try? input.close() }
            while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
                try output.write(contentsOf: chunk)
            }
            try output.synchronize()
            try FileManager.default.removeItem(at: downloaded)
        } else {
            if FileManager.default.fileExists(atPath: record.destination.path) {
                try FileManager.default.removeItem(at: record.destination)
            }
            try FileManager.default.moveItem(at: downloaded, to: record.destination)
        }
    }

    private static func fileSize(at url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
    }

    private static func isResumable(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError {
            return urlError.code != .badURL && urlError.code != .userAuthenticationRequired
        }
        return false
    }

    private static func makeShared() -> BackgroundModelDownloadCoordinator {
        do {
            let applicationSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let root = applicationSupport.appending(
                path: "BonsaiMobile/BackgroundTransfers",
                directoryHint: .isDirectory
            )
            let downloads = root.appending(path: "Downloads", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
            let ledger = try BackgroundTransferLedger(fileURL: root.appending(path: "transfers.json"))
            return .init(ledger: ledger, downloadsRoot: downloads, error: nil)
        } catch {
            return .init(ledger: nil, downloadsRoot: nil, error: error)
        }
    }
}

extension BackgroundModelDownloadCoordinator: URLSessionDownloadDelegate {
    func urlSession(
        _: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let downloadsRoot, let description = downloadTask.taskDescription,
              UUID(uuidString: description) != nil else {
            downloadTask.cancel()
            return
        }
        let durable = downloadsRoot.appending(path: "\(description).download")
        do {
            if FileManager.default.fileExists(atPath: durable.path) {
                try FileManager.default.removeItem(at: durable)
            }
            try FileManager.default.moveItem(at: location, to: durable)
            lock.withLock { durableDownloads[downloadTask.taskIdentifier] = durable }
        } catch {
            Task { await finalize(task: downloadTask, error: error) }
        }
    }

    func urlSession(_: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task { await finalize(task: task, error: error) }
    }

    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(URLSessionModelFileTransport.sanitizedRedirect(request, permitsLoopback: false))
    }

    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling, nil)
        } else {
            completionHandler(.rejectProtectionSpace, nil)
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession _: URLSession) {
        let completion = lock.withLock { () -> (@Sendable () -> Void)? in
            defer { backgroundEventsCompletion = nil }
            return backgroundEventsCompletion
        }
        DispatchQueue.main.async { completion?() }
    }
}
#endif
