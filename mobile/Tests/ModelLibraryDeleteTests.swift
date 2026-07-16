import Foundation
import Testing
@testable import BonsaiMobile

@Suite("Model library deletion")
struct ModelLibraryDeleteTests {
    @Test
    func preflightsLateSymlinkedStagingAncestorBeforeRemovingReadyInstallation() async throws {
        let root = try temporaryDirectory()
        let external = try temporaryDirectory()
        let expected = Data("still-ready".utf8)
        let manifest = try fixtureManifest(expected: expected)
        let library = try ModelLibrary(
            root: root,
            transport: DeleteFixtureTransport(data: expected),
            manifests: [manifest]
        )
        try await library.install(manifest, qualification: .qualified([.textGeneration]))
        let readyState = await library.state(for: .oneBit27B)
        guard case .ready = readyState else {
            Issue.record("Fixture installation must be ready before deletion")
            return
        }

        let stagingAncestor = root.appending(path: ".staging")
        try FileManager.default.removeItem(at: stagingAncestor)
        try FileManager.default.createSymbolicLink(at: stagingAncestor, withDestinationURL: external)

        await #expect(throws: ModelLibraryError.unsafeManagedPath(stagingAncestor.path)) {
            try await library.delete(.oneBit27B)
        }

        #expect(await library.state(for: .oneBit27B) == readyState)
        #expect(
            try Data(contentsOf: root.appending(path: "installed/oneBit27B/model.safetensors")) == expected
        )
        #expect((try FileManager.default.contentsOfDirectory(atPath: external.path)).isEmpty)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func fixtureManifest(expected: Data) throws -> ModelManifest {
        let file = try ModelManifest.File.validated(
            path: "model.safetensors",
            sizeBytes: expected.count,
            sha256: SHA256Verifier.digest(expected),
            role: .weight,
            isOptional: false
        )
        return try ModelManifest.validated(
            id: .oneBit27B,
            repository: "example/model",
            revision: String(repeating: "a", count: 40),
            files: [file]
        )
    }
}

private struct DeleteFixtureTransport: ModelFileTransport {
    let data: Data

    func download(_: ModelManifest.File, from _: URL, to destination: URL) async throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination)
    }
}
