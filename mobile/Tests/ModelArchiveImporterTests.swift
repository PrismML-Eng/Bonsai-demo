import Darwin
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
}

extension ModelArchiveImporterTests {
    @Test(arguments: [S_IFIFO, S_IFSOCK, S_IFCHR, S_IFBLK, S_IFLNK])
    func rawArchiveRejectsSpecialUnixModesThroughModelLibrary(_ type: mode_t) async throws {
        let expected = Data("special-mode".utf8)
        let archive = try makeRawMetadataArchive(
            expected: expected,
            mode: type | 0o644
        )
        try await expectRejectedBeforeManagedWrite(archive, expected: expected)
    }

    @Test(arguments: [UInt16(0x000D), UInt16(0x756E)])
    func rawArchiveRejectsHardLinkMetadataThroughModelLibrary(_ identifier: UInt16) async throws {
        let expected = Data("hard-link".utf8)
        let archive = try makeRawMetadataArchive(
            expected: expected,
            mode: S_IFREG | 0o644,
            centralExtra: zipExtra(identifier: identifier)
        )
        try await expectRejectedBeforeManagedWrite(archive, expected: expected)
    }

    @Test
    func rawArchiveRejectsMalformedTruncatedAndDuplicateExtraFields() async throws {
        let expected = Data("bad-extra".utf8)
        let hostileExtras: [Data] = [
            Data([0xFE, 0xCA, 0x04, 0x00, 0xAA]),
            Data([0xFE, 0xCA, 0x00]),
            zipExtra(identifier: 0xCAFE) + zipExtra(identifier: 0xCAFE)
        ]

        for extra in hostileExtras {
            let archive = try makeRawMetadataArchive(
                expected: expected,
                mode: S_IFREG | 0o644,
                centralExtra: extra
            )
            try await expectRejectedBeforeManagedWrite(archive, expected: expected)
        }
    }

    @Test
    func archiveRejectsDescendantOfRequiredFileBeforeManagedWrite() async throws {
        let expected = Data("prefix-parent".utf8)
        let archive = try makeArchive([
            .file(path: "model.safetensors", data: expected),
            .directory(path: "model.safetensors/child")
        ])

        try await expectRejectedBeforeManagedWrite(archive, expected: expected)
    }

    @Test
    func archiveRejectsFileAncestorOfRequiredFileBeforeManagedWrite() async throws {
        let expected = Data("prefix-child".utf8)
        let archive = try makeArchive([
            .file(path: "weights", data: Data("unexpected".utf8)),
            .file(path: "weights/model.safetensors", data: expected)
        ])

        try await expectRejectedBeforeManagedWrite(
            archive,
            expected: expected,
            requiredPath: "weights/model.safetensors"
        )
    }
}

extension ModelArchiveImporterTests {
    func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func fixtureManifest(
        expected: Data,
        path: String = "model.safetensors"
    ) throws -> ModelManifest {
        let file = try ModelManifest.File.validated(
            path: path,
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

    func makeRawMetadataArchive(
        expected: Data,
        mode: mode_t,
        madeByHost: UInt8 = 3,
        centralExtra: Data = Data()
    ) throws -> URL {
        let archive = try makeArchive([.file(path: "model.safetensors", data: expected)])
        var bytes = try Data(contentsOf: archive)
        guard let endOffset = bytes.lastIndex(ofLittleEndian: 0x0605_4B50) else {
            throw FixtureError.invalidArchive
        }
        let directoryOffset = Int(bytes.littleEndianUInt32(at: endOffset + 16))
        guard bytes.littleEndianUInt32(at: directoryOffset) == 0x0201_4B50 else {
            throw FixtureError.invalidArchive
        }
        bytes[directoryOffset + 5] = madeByHost
        bytes.writeLittleEndian(UInt32(mode) << 16, at: directoryOffset + 38)

        if !centralExtra.isEmpty {
            let nameLength = Int(bytes.littleEndianUInt16(at: directoryOffset + 28))
            let oldExtraLength = Int(bytes.littleEndianUInt16(at: directoryOffset + 30))
            let insertionOffset = directoryOffset + 46 + nameLength + oldExtraLength
            bytes.insert(contentsOf: centralExtra, at: insertionOffset)
            bytes.writeLittleEndian(
                UInt16(oldExtraLength + centralExtra.count),
                at: directoryOffset + 30
            )
            let relocatedEndOffset = endOffset + centralExtra.count
            let oldDirectorySize = bytes.littleEndianUInt32(at: relocatedEndOffset + 12)
            bytes.writeLittleEndian(
                oldDirectorySize + UInt32(centralExtra.count),
                at: relocatedEndOffset + 12
            )
        }
        try bytes.write(to: archive, options: .atomic)
        return archive
    }

    func zipExtra(identifier: UInt16) -> Data {
        var data = Data(count: 4)
        data.writeLittleEndian(identifier, at: 0)
        data.writeLittleEndian(UInt16(0), at: 2)
        return data
    }

    func expectRejectedBeforeManagedWrite(
        _ archive: URL,
        expected: Data,
        requiredPath: String = "model.safetensors"
    ) async throws {
        let root = try temporaryDirectory()
        let library = try ModelLibrary(root: root, transport: NoopTransport())
        await #expect(throws: (any Error).self) {
            try await library.importModel(
                try fixtureManifest(expected: expected, path: requiredPath),
                from: archive,
                qualification: .qualified([.textGeneration])
            )
        }
        let identifier = ModelID.oneBit27B.rawValue
        #expect(!FileManager.default.fileExists(
            atPath: root.appending(path: "installed/\(identifier)").path
        ))
        #expect(!FileManager.default.fileExists(
            atPath: root.appending(path: ".staging/\(identifier)").path
        ))
    }
}

private enum FixtureError: Error {
    case invalidArchive
}

private extension Data {
    func lastIndex(ofLittleEndian value: UInt32) -> Int? {
        guard count >= 4 else { return nil }
        for offset in stride(from: count - 4, through: 0, by: -1)
        where littleEndianUInt32(at: offset) == value {
            return offset
        }
        return nil
    }

    func littleEndianUInt16(at offset: Int) -> UInt16 {
        self[offset ..< offset + 2].enumerated().reduce(0) { result, pair in
            result | UInt16(pair.element) << (8 * pair.offset)
        }
    }

    func littleEndianUInt32(at offset: Int) -> UInt32 {
        self[offset ..< offset + 4].enumerated().reduce(0) { result, pair in
            result | UInt32(pair.element) << (8 * pair.offset)
        }
    }

    mutating func writeLittleEndian(_ value: UInt16, at offset: Int) {
        for index in 0 ..< 2 { self[offset + index] = UInt8(truncatingIfNeeded: value >> (8 * index)) }
    }

    mutating func writeLittleEndian(_ value: UInt32, at offset: Int) {
        for index in 0 ..< 4 { self[offset + index] = UInt8(truncatingIfNeeded: value >> (8 * index)) }
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

struct NoopTransport: ModelFileTransport {
    func download(_: ModelManifest.File, from _: URL, to _: URL) async throws {}
}
