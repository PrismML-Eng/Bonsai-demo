import Foundation
import Testing
import ZIPFoundation
@testable import BonsaiMobile

@Suite("Model archive importer")
struct ModelArchiveImporterTests {
    @Test
    func validArchiveImportsWithoutWholeArchiveExtraction() async throws {
        let expected = Data("zipped".utf8)
        let library = try ModelLibrary(root: temporaryDirectory(), transport: NoopTransport())
        let archive = try makeArchive([.file(path: "model.safetensors", data: expected)])

        try await library.importModel(
            try fixtureManifest(expected: expected),
            from: archive,
            qualification: .qualified([.textGeneration])
        )

        guard case .ready = await library.state(for: .oneBit27B) else {
            Issue.record("Expected ZIP import to be ready")
            return
        }
    }

    @Test(arguments: ["../model.safetensors", "/model.safetensors", "C:/model.safetensors"])
    func archiveTraversalAndAbsolutePathsAreRejected(_ path: String) async throws {
        let expected = Data("badpath".utf8)
        let archive = try makeArchive([.file(path: path, data: expected)])
        let library = try ModelLibrary(root: temporaryDirectory(), transport: NoopTransport())

        await #expect(throws: (any Error).self) {
            try await library.importModel(
                try fixtureManifest(expected: expected),
                from: archive,
                qualification: .qualified([.textGeneration])
            )
        }
    }

    @Test
    func archiveRejectsDuplicateSymlinkExecutableAndDeclaredSizeMismatch() async throws {
        let expected = Data("archive".utf8)
        let hostileArchives: [[ArchiveFixtureEntry]] = [
            [.file(path: "model.safetensors", data: expected),
             .file(path: "model.safetensors", data: expected)],
            [.init(path: "model.safetensors", data: Data("target".utf8), type: .symlink, permissions: 0o644)],
            [.init(path: "model.safetensors", data: expected, type: .file, permissions: 0o755)],
            [.file(path: "model.safetensors", data: Data("wrong".utf8))]
        ]
        for entries in hostileArchives {
            let archive = try makeArchive(entries)
            let library = try ModelLibrary(root: temporaryDirectory(), transport: NoopTransport())
            await #expect(throws: (any Error).self) {
                try await library.importModel(
                    try fixtureManifest(expected: expected),
                    from: archive,
                    qualification: .qualified([.textGeneration])
                )
            }
        }
    }

    @Test
    func genericZipIsRejected() async throws {
        let expected = Data("generic".utf8)
        let package = try makeArchive([.file(path: "model.safetensors", data: expected)])
        let generic = package.deletingLastPathComponent().appending(path: "\(UUID().uuidString).zip")
        try FileManager.default.moveItem(at: package, to: generic)
        let library = try ModelLibrary(root: temporaryDirectory(), transport: NoopTransport())

        await #expect(throws: (any Error).self) {
            try await library.importModel(
                try fixtureManifest(expected: expected),
                from: generic,
                qualification: .qualified([.textGeneration])
            )
        }
    }

    @Test
    func archiveRejectsMissingHashMismatchAndDirectoryFileCollision() async throws {
        let expected = Data("required".utf8)
        let hostileArchives: [[ArchiveFixtureEntry]] = [
            [.directory(path: "weights")],
            [.file(path: "model.safetensors", data: Data("mismatch".utf8))],
            [.directory(path: "model.safetensors"), .file(path: "model.safetensors", data: expected)]
        ]
        for entries in hostileArchives {
            let library = try ModelLibrary(root: temporaryDirectory(), transport: NoopTransport())
            await #expect(throws: (any Error).self) {
                try await library.importModel(
                    try fixtureManifest(expected: expected),
                    from: try makeArchive(entries),
                    qualification: .qualified([.textGeneration])
                )
            }
        }
    }

    @Test
    func archiveRejectsZipBombCompressionRatioBeforeWriting() async throws {
        let expected = Data(repeating: 0, count: 5 * 1_048_576)
        let archive = try makeArchive([
            .init(
                path: "model.safetensors",
                data: expected,
                type: .file,
                permissions: 0o644,
                compression: .deflate
            )
        ])
        let root = try temporaryDirectory()
        let library = try ModelLibrary(root: root, transport: NoopTransport())

        await #expect(throws: ModelLibraryError.archiveTooLarge) {
            try await library.importModel(
                try fixtureManifest(expected: expected),
                from: archive,
                qualification: .qualified([.textGeneration])
            )
        }
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "installed").path))
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

    private func makeArchive(_ entries: [ArchiveFixtureEntry]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "\(UUID().uuidString).bonsaimodel.zip")
        let archive = try Archive(url: url, accessMode: .create)
        for entry in entries {
            try archive.addEntry(
                with: entry.path,
                type: entry.type,
                uncompressedSize: Int64(entry.data.count),
                permissions: entry.permissions,
                compressionMethod: entry.compression
            ) { position, size in
                let start = Int(position)
                return entry.data.subdata(in: start ..< min(start + size, entry.data.count))
            }
        }
        return url
    }
}

private struct ArchiveFixtureEntry {
    let path: String
    let data: Data
    let type: Entry.EntryType
    let permissions: UInt16
    let compression: CompressionMethod

    init(
        path: String,
        data: Data,
        type: Entry.EntryType,
        permissions: UInt16,
        compression: CompressionMethod = .none
    ) {
        self.path = path
        self.data = data
        self.type = type
        self.permissions = permissions
        self.compression = compression
    }

    static func file(path: String, data: Data) -> Self {
        Self(path: path, data: data, type: .file, permissions: 0o644, compression: .none)
    }

    static func directory(path: String) -> Self {
        Self(path: path, data: Data(), type: .directory, permissions: 0o755, compression: .none)
    }
}

private struct NoopTransport: ModelFileTransport {
    func download(_: ModelManifest.File, from _: URL, to _: URL) async throws {}
}
