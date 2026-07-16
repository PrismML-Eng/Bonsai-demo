import Foundation

protocol ModelFileTransport: Sendable {
    func download(_ file: ModelManifest.File, from source: URL, to destination: URL) async throws
}
