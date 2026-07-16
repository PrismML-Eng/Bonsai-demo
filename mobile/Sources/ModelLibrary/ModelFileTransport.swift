import Foundation

protocol ModelFileTransport: Sendable {
    func download(_ file: ModelManifest.File, from source: URL, to destination: URL) async throws
}

protocol ProgressReportingModelFileTransport: ModelFileTransport {
    func download(_ file: ModelManifest.File, from source: URL, to destination: URL,
                  progress: @escaping @Sendable (Int) async -> Void) async throws
}
