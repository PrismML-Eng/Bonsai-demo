import CryptoKit
import Foundation

struct SHA256Verifier: Sendable {
    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func verify(_ file: ModelManifest.File, at url: URL) throws {
        // FileManager reads current metadata; URL resource values can remain cached
        // across an interrupted transfer followed by an in-place Range append.
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw ModelLibraryError.invalidFileType(file.path)
        }
        guard (attributes[.size] as? NSNumber)?.intValue == file.sizeBytes else {
            throw ModelLibraryError.sizeMismatch(file.path)
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            try Task.checkCancellation()
            let chunk = try handle.read(upToCount: 1_048_576) ?? Data()
            guard !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        let actual = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == file.sha256 else {
            throw ModelLibraryError.hashMismatch(file.path)
        }
    }
}
