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

@Suite("No-follow installation reconstruction")
struct NoFollowInstallationReconstructionTests {
    @Test
    func rejectsSymlinkedRequiredFile() async throws {
        let fixture = try await Fixture(expected: Data("external-model".utf8))
        let requiredFile = fixture.installed.appending(path: "model.safetensors")
        let externalFile = fixture.external.appending(path: "model.safetensors")
        try fixture.expected.write(to: externalFile)
        try replaceWithSymlink(requiredFile, to: externalFile)

        try await fixture.expectFailedReconstruction()
    }

    @Test
    func rejectsSymlinkedInstallationRecord() async throws {
        let fixture = try await Fixture(expected: Data("installed-model".utf8))
        let record = fixture.installed.appending(path: ".bonsai-installation.json")
        let externalRecord = fixture.external.appending(path: ".bonsai-installation.json")
        try FileManager.default.copyItem(at: record, to: externalRecord)
        try replaceWithSymlink(record, to: externalRecord)

        try await fixture.expectFailedReconstruction()
    }

    private func replaceWithSymlink(_ item: URL, to destination: URL) throws {
        try FileManager.default.removeItem(at: item)
        try FileManager.default.createSymbolicLink(at: item, withDestinationURL: destination)
    }
}

private extension NoFollowInstallationReconstructionTests {
    struct Fixture {
        let root: URL
        let external: URL
        let expected: Data
        let manifest: ModelManifest

        var installed: URL { root.appending(path: "installed/oneBit27B") }

        init(expected: Data) async throws {
            root = try Self.temporaryDirectory()
            external = try Self.temporaryDirectory()
            self.expected = expected
            let file = try ModelManifest.File.validated(
                path: "model.safetensors",
                sizeBytes: expected.count,
                sha256: SHA256Verifier.digest(expected),
                role: .weight,
                isOptional: false
            )
            manifest = try ModelManifest.validated(
                id: .oneBit27B,
                repository: "example/model",
                revision: String(repeating: "a", count: 40),
                files: [file]
            )
            let library = try ModelLibrary(
                root: root,
                transport: ReconstructionTransport(data: expected),
                manifests: [manifest]
            )
            try await library.install(manifest, qualification: .qualified([.textGeneration]))
        }

        func expectFailedReconstruction() async throws {
            let relaunched = try ModelLibrary(root: root, manifests: [manifest])
            guard case .failed = await relaunched.state(for: .oneBit27B) else {
                Issue.record("A symlinked installation artifact must never reconstruct as ready")
                return
            }
        }

        private static func temporaryDirectory() throws -> URL {
            let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
    }
}

private struct ReconstructionTransport: ModelFileTransport {
    let data: Data

    func download(_: ModelManifest.File, from _: URL, to destination: URL) async throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination)
    }
}
