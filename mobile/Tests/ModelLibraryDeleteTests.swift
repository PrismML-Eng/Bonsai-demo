import Foundation
import Testing
@testable import BonsaiMobile

@Suite("Model library deletion")
struct ModelLibraryDeleteTests {
    @Test
    func stagingCleanupFailureRetainsReadyInstallation() async throws {
        let root = try temporaryDirectory()
        let expected = Data("still-installed".utf8)
        let manifest = try fixtureManifest(expected: expected)
        let fileSystem = FaultInjectingModelLibraryFileSystem(failure: .removeStaging)
        let library = try ModelLibrary(
            root: root,
            transport: DeleteFixtureTransport(data: expected),
            manifests: [manifest],
            managedFileSystem: fileSystem
        )
        try await library.install(manifest, qualification: .qualified([.textGeneration]))
        let readyState = await library.state(for: .oneBit27B)
        let staging = root.appending(path: ".staging/oneBit27B")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try Data("partial".utf8).write(to: staging.appending(path: "partial"))

        await #expect(throws: POSIXError.self) {
            try await library.delete(.oneBit27B)
        }

        #expect(await library.state(for: .oneBit27B) == readyState)
        #expect(
            try Data(contentsOf: root.appending(path: "installed/oneBit27B/model.safetensors")) == expected
        )
    }

    @Test
    func installedRenameFailureRetainsReadyInstallation() async throws {
        let root = try temporaryDirectory()
        let expected = Data("rename-must-be-atomic".utf8)
        let manifest = try fixtureManifest(expected: expected)
        let fileSystem = FaultInjectingModelLibraryFileSystem(failure: .moveInstalled)
        let library = try ModelLibrary(
            root: root,
            transport: DeleteFixtureTransport(data: expected),
            manifests: [manifest],
            managedFileSystem: fileSystem
        )
        try await library.install(manifest, qualification: .qualified([.textGeneration]))
        let readyState = await library.state(for: .oneBit27B)

        await #expect(throws: POSIXError.self) {
            try await library.delete(.oneBit27B)
        }

        #expect(await library.state(for: .oneBit27B) == readyState)
        #expect(
            try Data(contentsOf: root.appending(path: "installed/oneBit27B/model.safetensors")) == expected
        )
    }

    @Test
    func trashCleanupIsBestEffortAndRecoveredOnRelaunch() async throws {
        let root = try temporaryDirectory()
        let expected = Data("eventually-collected".utf8)
        let manifest = try fixtureManifest(expected: expected)
        let fileSystem = FaultInjectingModelLibraryFileSystem(failure: .removeTrash)
        let library = try ModelLibrary(
            root: root,
            transport: DeleteFixtureTransport(data: expected),
            manifests: [manifest],
            managedFileSystem: fileSystem
        )
        try await library.install(manifest, qualification: .qualified([.textGeneration]))

        try await library.delete(.oneBit27B)

        #expect(await library.state(for: .oneBit27B) == .notInstalled)
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "installed/oneBit27B").path))
        #expect(!(try FileManager.default.contentsOfDirectory(atPath: root.appending(path: ".trash").path)).isEmpty)

        let relaunched = try ModelLibrary(root: root, manifests: [manifest])
        #expect(await relaunched.state(for: .oneBit27B) == .notInstalled)
        #expect((try FileManager.default.contentsOfDirectory(atPath: root.appending(path: ".trash").path)).isEmpty)
    }

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

private final class FaultInjectingModelLibraryFileSystem: ModelLibraryFileSystem, @unchecked Sendable {
    enum Failure: Equatable {
        case removeStaging
        case moveInstalled
        case removeTrash
    }

    private let failure: Failure

    init(failure: Failure) {
        self.failure = failure
    }

    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: withIntermediateDirectories
        )
    }

    func removeItem(at url: URL) throws {
        if failure == .removeStaging, url.path.contains("/.staging/oneBit27B") {
            throw POSIXError(.EIO)
        }
        if failure == .removeTrash, url.path.contains("/.trash/oneBit27B-") {
            throw POSIXError(.EIO)
        }
        try FileManager.default.removeItem(at: url)
    }

    func moveItem(at source: URL, to destination: URL) throws {
        if failure == .moveInstalled, source.path.hasSuffix("/installed/oneBit27B") {
            throw POSIXError(.EIO)
        }
        try FileManager.default.moveItem(at: source, to: destination)
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
