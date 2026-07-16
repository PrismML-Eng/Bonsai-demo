import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class BackgroundModelDownloadCoordinator: NSObject {
    static let sessionIdentifier = "com.prismml.BonsaiMobile.model-download"
    static let shared = BackgroundModelDownloadCoordinator.makeShared()

    private let ledger: BackgroundTransferLedger?
    private let initializationError: Error?
    private let state = BackgroundDownloadCoordinatorState()
    private let completions = BackgroundTransferCompletionRegistry()
    private let progressBridge = BackgroundDownloadProgressBridge()
    private let sessionOwner: BackgroundURLSessionOwner
    private let reconciliationGate = BackgroundReconciliationGate()
    private let permitsLoopback: Bool

    private init(
        ledger: BackgroundTransferLedger?,
        error: Error?,
        configuration: URLSessionConfiguration,
        permitsLoopback: Bool
    ) {
        self.ledger = ledger
        initializationError = error
        sessionOwner = BackgroundURLSessionOwner(configuration: configuration)
        self.permitsLoopback = permitsLoopback
        super.init()
    }

    convenience init(
        ledger: BackgroundTransferLedger,
        configuration: URLSessionConfiguration,
        permitsLoopback: Bool = false
    ) {
        self.init(
            ledger: ledger,
            error: nil,
            configuration: URLSessionModelFileTransport.sanitized(configuration),
            permitsLoopback: permitsLoopback
        )
    }

    func download(
        _ file: ModelManifest.File,
        from source: URL,
        to destination: URL,
        progress: @escaping @Sendable (Int) async -> Void
    ) async throws {
        guard let ledger else { throw initializationError ?? CocoaError(.fileWriteUnknown) }
        let sourceIsAllowed = source.scheme?.lowercased() == "https" ||
            (permitsLoopback && URLSessionModelFileTransport.isLoopback(source))
        guard sourceIsAllowed else { throw ModelTransportError.insecureURL }
        try await reconcileTasks(using: ledger)

        if let previous = await ledger.activeRecord(destination: destination) {
            if previous.state == .running, let task = state.task(id: previous.id) {
                progressBridge.attach(
                    id: previous.id,
                    existingBytes: previous.existingBytes,
                    expectedBytes: previous.expectedSize,
                    taskBytesReceived: task.countOfBytesReceived,
                    progress: progress
                )
                defer { progressBridge.detach(id: previous.id) }
                try await awaitCompletion(of: previous.id, task: task, startsTask: false)
                return
            }
            try await ledger.remove(id: previous.id)
            completions.remove(id: previous.id)
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
        let task = session().downloadTask(with: request)
        task.taskDescription = record.taskDescription
        try await ledger.bind(id: record.id, taskIdentifier: task.taskIdentifier)
        state.store(task: task, id: record.id)
        progressBridge.attach(
            id: record.id,
            existingBytes: existingBytes,
            expectedBytes: file.sizeBytes,
            taskBytesReceived: task.countOfBytesReceived,
            progress: progress
        )
        defer { progressBridge.detach(id: record.id) }
        try await awaitCompletion(of: record.id, task: task, startsTask: true)
    }

    func restoreBackgroundTasks() {
        guard let ledger else { return }
        Task { try? await reconcileTasks(using: ledger) }
    }

    func setBackgroundEventsCompletion(_ completion: @escaping @Sendable () -> Void) {
        state.setBackgroundEventsCompletion(completion)
        restoreBackgroundTasks()
    }

    private func awaitCompletion(
        of id: UUID,
        task: URLSessionDownloadTask,
        startsTask: Bool
    ) async throws {
        let completionRegistry = completions
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                do {
                    try completionRegistry.register(id: id) { result in
                        continuation.resume(with: result)
                    }
                    if startsTask { task.resume() }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            self.progressBridge.detach(id: id)
            task.cancel()
        }
    }

    private func reconcileTasks(using ledger: BackgroundTransferLedger) async throws {
        await reconciliationGate.acquire()
        do {
            try await performReconciliation(using: ledger)
            await reconciliationGate.release()
        } catch {
            await reconciliationGate.release()
            throw error
        }
    }

    private func performReconciliation(using ledger: BackgroundTransferLedger) async throws {
        let allTasks = await withCheckedContinuation { continuation in
            session().getAllTasks { continuation.resume(returning: $0) }
        }
        let identities = allTasks.map {
            BackgroundTransferTaskIdentity(
                taskIdentifier: $0.taskIdentifier,
                taskDescription: $0.taskDescription,
                state: Self.transferState($0.state)
            )
        }
        let reconciliation = try await ledger.reconcile(tasks: identities)
        let byIdentifier = Dictionary(uniqueKeysWithValues: allTasks.map { ($0.taskIdentifier, $0) })
        for identifier in reconciliation.taskIdentifiersToCancel {
            byIdentifier[identifier]?.cancel()
        }
        for attachment in reconciliation.reattached {
            if let task = byIdentifier[attachment.taskIdentifier] as? URLSessionDownloadTask {
                state.store(task: task, id: attachment.transferID)
                if attachment.decision == .resume { task.resume() }
            }
        }
        for claim in reconciliation.claimedBodies {
            await finalizeClaim(claim, ledger: ledger)
        }
    }

    private func finalize(task: URLSessionTask, error: Error?) async {
        guard let ledger, let description = task.taskDescription,
              let id = UUID(uuidString: description) else {
            resolve(id: task.taskDescription.flatMap(UUID.init(uuidString:)), result: .failure(
                ModelTransportError.invalidResponse
            ))
            return
        }
        do {
            if let error { throw error }
            if let claim = try await ledger.adoptPersistedClaim(id: id) {
                await finalizeClaim(claim, ledger: ledger)
            } else if await ledger.record(id: id)?.state == .completed {
                resolve(id: id, result: .success(()))
            } else {
                let missing = URLError(.networkConnectionLost)
                try await ledger.finish(id: id, failure: missing.localizedDescription, isResumable: true)
                resolve(id: id, result: .failure(missing))
            }
        } catch {
            let resumable = Self.isResumable(error)
            try? await ledger.finish(id: id, failure: String(describing: error), isResumable: resumable)
            resolve(id: id, result: .failure(error))
        }
    }

    private func finalizeClaim(
        _ claim: BackgroundTransferClaim,
        ledger: BackgroundTransferLedger
    ) async {
        do {
            guard let record = await ledger.record(id: claim.transferID) else {
                throw BackgroundTransferLedgerError.unknownTransfer
            }
            if record.state == .completed {
                resolve(id: record.id, result: .success(()))
                return
            }
            try BackgroundTransferPromoter().promote(claim, record: record)
            try await ledger.markPromoted(id: record.id)
            progressBridge.report(
                id: record.id,
                taskBytesReceived: Int64(max(0, record.expectedSize - record.existingBytes))
            )
            await progressBridge.flush(id: record.id)
            resolve(id: record.id, result: .success(()))
        } catch {
            progressBridge.detach(id: claim.transferID)
            try? await ledger.finish(
                id: claim.transferID,
                failure: String(describing: error),
                isResumable: Self.isResumable(error)
            )
            resolve(id: claim.transferID, result: .failure(error))
        }
    }

    private func resolve(id: UUID?, result: Result<Void, Error>) {
        guard let id else { return }
        state.removeTask(id: id)
        completions.resolve(id: id, result: result)
    }

    private func session() -> URLSession {
        sessionOwner.session(delegate: self)
    }

}

extension BackgroundModelDownloadCoordinator: URLSessionDownloadDelegate {
    func urlSession(
        _: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData _: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite _: Int64
    ) {
        guard let description = downloadTask.taskDescription,
              let id = UUID(uuidString: description) else { return }
        progressBridge.report(id: id, taskBytesReceived: totalBytesWritten)
    }

    func urlSession(
        _: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let ledger, let description = downloadTask.taskDescription,
              let id = UUID(uuidString: description),
              let response = downloadTask.response as? HTTPURLResponse else {
            downloadTask.cancel()
            return
        }
        do {
            _ = try ledger.claimBodySynchronously(
                id: id,
                temporaryBody: location,
                statusCode: response.statusCode,
                contentRange: response.value(forHTTPHeaderField: "Content-Range")
            )
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
        let completion = state.takeBackgroundEventsCompletion()
        DispatchQueue.main.async { completion?() }
    }
}

private extension BackgroundModelDownloadCoordinator {
    static func transferState(_ state: URLSessionTask.State) -> BackgroundTransferTaskState {
        switch state {
        case .suspended: .suspended
        case .running: .running
        case .canceling: .canceling
        case .completed: .completed
        @unknown default: .canceling
        }
    }

    static func fileSize(at url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
    }

    static func isResumable(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError {
            return urlError.code != .badURL && urlError.code != .userAuthenticationRequired
        }
        return false
    }

    static func makeShared() -> BackgroundModelDownloadCoordinator {
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
            let ledger = try BackgroundTransferLedger(fileURL: root.appending(path: "transfers.json"))
            return .init(
                ledger: ledger,
                error: nil,
                configuration: URLSessionModelFileTransport.productionConfiguration(),
                permitsLoopback: false
            )
        } catch {
            return .init(
                ledger: nil,
                error: error,
                configuration: URLSessionModelFileTransport.productionConfiguration(),
                permitsLoopback: false
            )
        }
    }
}
