import Foundation

final class ModelDownloadSessionHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var session: URLSession?
    private var cancelled = false
    private var preStoreCancellation: (@Sendable () -> Void)?

    func registerPreStoreCancellation(_ action: @escaping @Sendable () -> Void) {
        let runNow = lock.withLock { () -> Bool in
            if cancelled { return true }
            preStoreCancellation = action
            return false
        }
        if runNow { action() }
    }

    func store(_ session: URLSession) -> Bool {
        let shouldCancel = lock.withLock { () -> Bool in
            if cancelled { return true }
            self.session = session
            preStoreCancellation = nil
            return false
        }
        if shouldCancel {
            session.invalidateAndCancel()
            return false
        }
        return true
    }

    func cancel() {
        let resources = lock.withLock { () -> (URLSession?, (@Sendable () -> Void)?) in
            cancelled = true
            defer { preStoreCancellation = nil }
            return (session, session == nil ? preStoreCancellation : nil)
        }
        resources.1?()
        resources.0?.invalidateAndCancel()
    }

    func invalidate() {
        let session = lock.withLock { () -> URLSession? in
            defer { self.session = nil }
            return self.session
        }
        session?.finishTasksAndInvalidate()
    }
}
