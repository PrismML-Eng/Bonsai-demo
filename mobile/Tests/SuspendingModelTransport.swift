import Foundation
@testable import BonsaiMobile

actor SuspendingModelTransport: ModelFileTransport {
    private let data: Data
    private var started = false
    private var continuation: CheckedContinuation<Void, Never>?

    init(data: Data) { self.data = data }

    func waitUntilStarted() async {
        while !started { await Task.yield() }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }

    func download(_: ModelManifest.File, from _: URL, to destination: URL) async throws {
        started = true
        await withCheckedContinuation { continuation = $0 }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination)
    }
}
