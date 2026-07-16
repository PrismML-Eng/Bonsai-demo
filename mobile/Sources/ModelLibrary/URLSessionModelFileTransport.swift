import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum ModelTransportError: Error, Equatable, Sendable {
    case insecureURL
    case invalidResponse
    case httpStatus(Int)
    case invalidContentRange
}

final class URLSessionModelFileTransport: ModelFileTransport, @unchecked Sendable {
    private let configuration: URLSessionConfiguration

    init(configuration: URLSessionConfiguration = .default) {
        self.configuration = configuration
    }

    func download(_ file: ModelManifest.File, from source: URL, to destination: URL) async throws {
        guard source.scheme?.lowercased() == "https" || Self.isLoopback(source) else {
            throw ModelTransportError.insecureURL
        }
        let existing = Self.fileSize(at: destination)
        var request = URLRequest(url: source)
        request.httpMethod = "GET"
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if existing > 0, existing < file.sizeBytes {
            request.setValue("bytes=\(existing)-", forHTTPHeaderField: "Range")
        }

        let holder = SessionHolder()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let delegate = StreamingDownloadDelegate(
                    destination: destination,
                    existingBytes: existing,
                    completion: continuation
                )
                let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
                holder.store(session)
                session.dataTask(with: request).resume()
            }
        } onCancel: {
            holder.cancel()
        }
    }

    private static func fileSize(at url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    fileprivate static func contentRangeStarts(_ value: String?, at offset: Int) -> Bool {
        value?.lowercased().hasPrefix("bytes \(offset)-") == true
    }

    fileprivate static func isLoopback(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "http" else { return false }
        return ["127.0.0.1", "localhost", "::1"].contains(url.host ?? "")
    }
}

private final class SessionHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var session: URLSession?

    func store(_ session: URLSession) {
        lock.withLock { self.session = session }
    }

    func cancel() {
        lock.withLock { session?.invalidateAndCancel() }
    }
}

private final class StreamingDownloadDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let destination: URL
    private let existingBytes: Int
    private var output: FileHandle?
    private var terminalError: Error?
    private var completion: CheckedContinuation<Void, Error>?

    init(destination: URL, existingBytes: Int, completion: CheckedContinuation<Void, Error>) {
        self.destination = destination
        self.existingBytes = existingBytes
        self.completion = completion
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
            }
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
        guard let url = request.url else { return completionHandler(nil) }
        let allowed = url.scheme?.lowercased() == "https" || URLSessionModelFileTransport.isLoopback(url)
        completionHandler(allowed ? request : nil)
    }

    private func finish(_ result: Result<Void, Error>) {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Error>? in
            defer { completion = nil }
            return completion
        }
        continuation?.resume(with: result)
    }
}
