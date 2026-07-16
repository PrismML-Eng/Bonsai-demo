import Foundation
import Testing
@testable import BonsaiMobile

@Suite("Streaming SHA-256 verifier")
struct SHA256VerifierTests {
    @Test
    func verifiesLargeFileInBoundedChunks() throws {
        let data = Data(repeating: 0xA5, count: 5 * 1_048_576 + 17)
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try data.write(to: url)
        let file = try ModelManifest.File.validated(
            path: "weights/model.safetensors",
            sizeBytes: data.count,
            sha256: SHA256Verifier.digest(data),
            role: .weight,
            isOptional: false
        )

        try SHA256Verifier().verify(file, at: url)
    }

    @Test
    func rejectsSizeBeforeAcceptingDigest() throws {
        let data = Data("content".utf8)
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try data.write(to: url)
        let file = try ModelManifest.File.validated(
            path: "weights/model.safetensors",
            sizeBytes: data.count + 1,
            sha256: SHA256Verifier.digest(data),
            role: .weight,
            isOptional: false
        )

        #expect(throws: ModelLibraryError.sizeMismatch("weights/model.safetensors")) {
            try SHA256Verifier().verify(file, at: url)
        }
    }
}
