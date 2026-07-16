import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum ModelTransportError: Error, Equatable, Sendable {
    case insecureURL
    case invalidResponse
    case httpStatus(Int)
    case invalidContentRange
    case duplicateWaiter
}

final class URLSessionModelFileTransport: ProgressReportingModelFileTransport, @unchecked Sendable {
    private let configuration: URLSessionConfiguration
    private let usesAppBackgroundCoordinator: Bool

    init(
        configuration: URLSessionConfiguration? = nil
    ) {
        #if os(iOS)
        usesAppBackgroundCoordinator = configuration == nil
        #else
        usesAppBackgroundCoordinator = false
        #endif
        self.configuration = Self.sanitized(configuration ?? .ephemeral)
    }

    func download(_ file: ModelManifest.File, from source: URL, to destination: URL) async throws {
        try await download(file, from: source, to: destination, progress: { _ in })
    }

    func download(_ file: ModelManifest.File, from source: URL, to destination: URL,
                  progress: @escaping @Sendable (Int) async -> Void) async throws {
        guard source.scheme?.lowercased() == "https" || Self.isLoopback(source) else {
            throw ModelTransportError.insecureURL
        }
        #if os(iOS)
        if usesAppBackgroundCoordinator {
            try await BackgroundModelDownloadCoordinator.shared.download(
                file,
                from: source,
                to: destination
            )
            await progress(file.sizeBytes)
            return
        }
        #endif
        let existing = Self.fileSize(at: destination)
        var request = URLRequest(url: source)
        request.httpMethod = "GET"
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if existing > 0, existing < file.sizeBytes {
            request.setValue("bytes=\(existing)-", forHTTPHeaderField: "Range")
        }

        let holder = ModelDownloadSessionHolder()
        defer { holder.invalidate() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let delegate = StreamingDownloadDelegate(
                    destination: destination,
                    existingBytes: existing,
                    permitsLoopback: Self.isLoopback(source),
                    completion: continuation,
                    progress: progress
                )
                let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
                holder.registerPreStoreCancellation { delegate.cancelBeforeStart() }
                guard holder.store(session) else { return }
                session.dataTask(with: request).resume()
            }
        } onCancel: {
            holder.cancel()
        }
    }

    private static func fileSize(at url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    static func contentRangeStarts(_ value: String?, at offset: Int) -> Bool {
        value?.lowercased().hasPrefix("bytes \(offset)-") == true
    }

    fileprivate static func isLoopback(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "http" else { return false }
        return ["127.0.0.1", "localhost", "::1"].contains(url.host ?? "")
    }

    static func productionConfiguration() -> URLSessionConfiguration {
        #if os(iOS)
        let identifier = "com.prismml.BonsaiMobile.model-download"
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        #else
        let configuration = URLSessionConfiguration.ephemeral
        #endif
        return sanitized(configuration)
    }

    static func sanitized(_ configuration: URLSessionConfiguration) -> URLSessionConfiguration {
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        var headers = configuration.httpAdditionalHeaders ?? [:]
        for key in headers.keys where ["authorization", "cookie"].contains(String(describing: key).lowercased()) {
            headers.removeValue(forKey: key)
        }
        configuration.httpAdditionalHeaders = headers
        return configuration
    }

    static func sanitizedRedirect(_ request: URLRequest, permitsLoopback: Bool) -> URLRequest? {
        guard let url = request.url else { return nil }
        let allowed = url.scheme?.lowercased() == "https" || (permitsLoopback && isLoopback(url))
        guard allowed, request.value(forHTTPHeaderField: "Authorization") == nil,
              request.value(forHTTPHeaderField: "Cookie") == nil else {
            return nil
        }
        var sanitized = request
        sanitized.setValue(nil, forHTTPHeaderField: "Authorization")
        sanitized.setValue(nil, forHTTPHeaderField: "Cookie")
        return sanitized
    }
}

private final class StreamingDownloadDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let destination: URL
    private let existingBytes: Int
    private let permitsLoopback: Bool
    private var output: FileHandle?
    private var terminalError: Error?
    private var completion: CheckedContinuation<Void, Error>?
    private let progress: @Sendable (Int) async -> Void
    private var receivedBytes: Int

    init(
        destination: URL,
        existingBytes: Int,
        permitsLoopback: Bool,
        completion: CheckedContinuation<Void, Error>,
        progress: @escaping @Sendable (Int) async -> Void
    ) {
        self.destination = destination
        self.existingBytes = existingBytes
        self.permitsLoopback = permitsLoopback
        self.completion = completion
        self.progress = progress
        receivedBytes = existingBytes
    }

    func cancelBeforeStart() {
        finish(.failure(CancellationError()))
    }

    func urlSession(
        _: URLSession,
        dataTask _: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        do {
            guard let http = response as? HTTPURLResponse else { throw ModelTransportError.invalidResponse }
            guard (200 ... 299).contains(http.statusCode) else {
                throw ModelTransportError.httpStatus(http.statusCode)
            }
            let append = existingBytes > 0 && http.statusCode == 206
            if append, !URLSessionModelFileTransport.contentRangeStarts(
                http.value(forHTTPHeaderField: "Content-Range"),
                at: existingBytes
            ) {
                throw ModelTransportError.invalidContentRange
            }
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !append {
                try Data().write(to: destination, options: .atomic)
            } else if !FileManager.default.fileExists(atPath: destination.path) {
                guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
                    throw CocoaError(.fileWriteUnknown)
                }
            }
            let handle = try FileHandle(forWritingTo: destination)
            if append { try handle.seekToEnd() }
            lock.withLock { output = handle }
            completionHandler(.allow)
        } catch {
            lock.withLock { terminalError = error }
            completionHandler(.cancel)
        }
    }

    func urlSession(_: URLSession, dataTask _: URLSessionDataTask, didReceive data: Data) {
        do {
            try lock.withLock {
                guard terminalError == nil, let output else { return }
                try output.write(contentsOf: data)
                receivedBytes += data.count
            }
            let current = lock.withLock { receivedBytes }
            Task { await progress(current) }
        } catch {
            lock.withLock { terminalError = error }
        }
    }

    func urlSession(_: URLSession, task _: URLSessionTask, didCompleteWithError error: Error?) {
        let result: Result<Void, Error> = lock.withLock {
            do {
                try output?.synchronize()
                try output?.close()
            } catch {
                terminalError = terminalError ?? error
            }
            output = nil
            if let terminalError { return .failure(terminalError) }
            if let error { return .failure(error) }
            return .success(())
        }
        finish(result)
    }

    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(
            URLSessionModelFileTransport.sanitizedRedirect(request, permitsLoopback: permitsLoopback)
        )
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

    private func finish(_ result: Result<Void, Error>) {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Error>? in
            defer { completion = nil }
            return completion
        }
        continuation?.resume(with: result)
    }
}
