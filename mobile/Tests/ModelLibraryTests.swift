import Foundation
import Testing
@testable import BonsaiMobile

@Suite("Model library")
struct ModelLibraryTests {
    @Test
    func corruptShardNeverBecomesReady() async throws {
        let root = try temporaryDirectory()
        let manifest = try fixtureManifest(expected: Data("good".utf8))
        let transport = RecordingTransport(files: ["model.safetensors": Data("bad!".utf8)])
        let library = try ModelLibrary(root: root, transport: transport)

        await #expect(throws: ModelLibraryError.hashMismatch("model.safetensors")) {
            try await library.install(manifest, qualification: .qualified([.textGeneration]))
        }

        #expect(await library.state(for: .oneBit27B) == .notInstalled)
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "installed/oneBit27B").path))
    }

    @Test
    func verifiedInstallBecomesReadyAndPublishesTerminalSnapshot() async throws {
        let root = try temporaryDirectory()
        let expected = Data("garden".utf8)
        let manifest = try fixtureManifest(expected: expected)
        let transport = RecordingTransport(files: ["model.safetensors": expected])
        let library = try ModelLibrary(root: root, transport: transport)

        try await library.install(manifest, qualification: .qualified([.textGeneration]))

        guard case let .ready(installation) = await library.state(for: .oneBit27B) else {
            Issue.record("Expected a ready installation")
            return
        }
        #expect(try Data(contentsOf: installation.directory.appending(path: "model.safetensors")) == expected)
        var iterator = await library.snapshots().makeAsyncIterator()
        let snapshot = await iterator.next()
        guard case .ready? = snapshot?.states[.oneBit27B] else {
            Issue.record("Expected terminal ready snapshot")
            return
        }
    }

    @Test
    func unqualifiedInstallDoesNotAllocateOrDownload() async throws {
        let root = try temporaryDirectory()
        let transport = RecordingTransport(files: [:])
        let library = try ModelLibrary(root: root, transport: transport)

        await #expect(throws: ModelLibraryError.unqualified) {
            try await library.install(
                try fixtureManifest(expected: Data("x".utf8)),
                qualification: .unverified(.deviceNotMeasured)
            )
        }

        #expect(await transport.callCount == 0)
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: ".staging").path))
    }

    @Test
    func resumeReusesAlreadyVerifiedFiles() async throws {
        let root = try temporaryDirectory()
        let expected = Data("verified".utf8)
        let manifest = try fixtureManifest(expected: expected)
        let staged = root.appending(path: ".staging/oneBit27B/model.safetensors")
        try FileManager.default.createDirectory(
            at: staged.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try expected.write(to: staged)
        let transport = RecordingTransport(files: [:])
        let library = try ModelLibrary(root: root, transport: transport)

        try await library.resume(manifest, qualification: .qualified([.textGeneration]))

        #expect(await transport.callCount == 0)
        guard case .ready = await library.state(for: .oneBit27B) else {
            Issue.record("Expected ready after reuse")
            return
        }
    }

    @Test
    func sizeMismatchNeverPromotes() async throws {
        let root = try temporaryDirectory()
        let manifest = try fixtureManifest(expected: Data("expected".utf8))
        let transport = RecordingTransport(files: ["model.safetensors": Data("short".utf8)])
        let library = try ModelLibrary(root: root, transport: transport)

        await #expect(throws: ModelLibraryError.sizeMismatch("model.safetensors")) {
            try await library.install(manifest, qualification: .qualified([.textGeneration]))
        }

        #expect(await library.state(for: .oneBit27B) == .notInstalled)
    }

    @Test
    func verifiedInstallAtomicallyReplacesAnExistingInstallation() async throws {
        let root = try temporaryDirectory()
        let old = root.appending(path: "installed/oneBit27B")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: old.appending(path: "model.safetensors"))
        let expected = Data("new-model".utf8)
        let library = try ModelLibrary(
            root: root,
            transport: RecordingTransport(files: ["model.safetensors": expected])
        )

        try await library.install(
            try fixtureManifest(expected: expected),
            qualification: .qualified([.textGeneration])
        )

        #expect(
            try Data(contentsOf: old.appending(path: "model.safetensors")) == expected
        )
    }

    @Test
    func cancellationLeavesNonReadyTerminalState() async throws {
        let root = try temporaryDirectory()
        let library = try ModelLibrary(root: root, transport: CancellingTransport())

        await #expect(throws: CancellationError.self) {
            try await library.install(
                try fixtureManifest(expected: Data("x".utf8)),
                qualification: .qualified([.textGeneration])
            )
        }

        #expect(await library.state(for: .oneBit27B) == .cancelled)
    }

    @Test
    func deleteIsIdempotentAndIsolatedByModel() async throws {
        let root = try temporaryDirectory()
        let oneBit = root.appending(path: "installed/oneBit27B")
        let ternary = root.appending(path: "installed/ternary27B")
        try FileManager.default.createDirectory(at: oneBit, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: ternary, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: ternary.appending(path: "marker"))
        let library = try ModelLibrary(root: root, transport: RecordingTransport(files: [:]))

        try await library.delete(.oneBit27B)
        try await library.delete(.oneBit27B)

        #expect(!FileManager.default.fileExists(atPath: oneBit.path))
        #expect(try Data(contentsOf: ternary.appending(path: "marker")) == Data("keep".utf8))
    }

    @Test
    func validFolderImportIsCopyOnly() async throws {
        let root = try temporaryDirectory()
        let source = try temporaryDirectory()
        let expected = Data("offline".utf8)
        try expected.write(to: source.appending(path: "model.safetensors"))
        let library = try ModelLibrary(root: root, transport: RecordingTransport(files: [:]))

        try await library.importModel(
            try fixtureManifest(expected: expected),
            from: source,
            qualification: .qualified([.textGeneration])
        )

        #expect(try Data(contentsOf: source.appending(path: "model.safetensors")) == expected)
        guard case .ready = await library.state(for: .oneBit27B) else {
            Issue.record("Expected imported model to be ready")
            return
        }
    }

    @Test(arguments: [HostileFolder.missing, .extra, .symlink, .hardLink, .executable])
    private func hostileFoldersAreRejected(_ hostile: HostileFolder) async throws {
        let root = try temporaryDirectory()
        let source = try temporaryDirectory()
        let expected = Data("safe".utf8)
        let model = source.appending(path: "model.safetensors")
        if hostile != .missing { try expected.write(to: model) }
        switch hostile {
        case .missing: break
        case .extra: try Data().write(to: source.appending(path: "unexpected"))
        case .symlink:
            try FileManager.default.removeItem(at: model)
            try FileManager.default.createSymbolicLink(
                at: model,
                withDestinationURL: URL(fileURLWithPath: "/etc/hosts")
            )
        case .hardLink:
            try FileManager.default.linkItem(at: model, to: source.appending(path: "alias"))
        case .executable:
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: model.path)
        }
        let library = try ModelLibrary(root: root, transport: RecordingTransport(files: [:]))

        await #expect(throws: (any Error).self) {
            try await library.importModel(
                try fixtureManifest(expected: expected),
                from: source,
                qualification: .qualified([.textGeneration])
            )
        }

        #expect(await library.state(for: .oneBit27B) == .notInstalled)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func fixtureManifest(expected: Data) throws -> ModelManifest {
        let digest = SHA256Verifier.digest(expected)
        let file = try ModelManifest.File.validated(
            path: "model.safetensors",
            sizeBytes: expected.count,
            sha256: digest,
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

private enum HostileFolder: CaseIterable, Sendable {
    case missing
    case extra
    case symlink
    case hardLink
    case executable
}

private actor RecordingTransport: ModelFileTransport {
    let files: [String: Data]
    private(set) var callCount = 0

    init(files: [String: Data]) {
        self.files = files
    }

    func download(_ file: ModelManifest.File, from _: URL, to destination: URL) async throws {
        callCount += 1
        guard let data = files[file.path] else {
            throw CocoaError(.fileNoSuchFile)
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination)
    }
}

private struct CancellingTransport: ModelFileTransport {
    func download(_: ModelManifest.File, from _: URL, to _: URL) async throws {
        throw CancellationError()
    }
}
