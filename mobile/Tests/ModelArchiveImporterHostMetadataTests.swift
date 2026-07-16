import Darwin
import Foundation
import Testing
@testable import BonsaiMobile

extension ModelArchiveImporterTests {
    @Test(arguments: (0 ... 255).map(UInt8.init))
    func rawArchiveRejectsHardLinkMetadataForEveryHost(_ madeByHost: UInt8) async throws {
        let expected = Data("host-independent-hard-link".utf8)
        for identifier in [UInt16(0x000D), UInt16(0x756E)] {
            let archive = try makeRawMetadataArchive(
                expected: expected,
                mode: S_IFREG | 0o644,
                madeByHost: madeByHost,
                centralExtra: zipExtra(identifier: identifier)
            )
            try await expectRejectedBeforeManagedWrite(archive, expected: expected)
        }
    }

    @Test(arguments: (0 ... 255).map(UInt8.init))
    func rawArchiveRejectsMalformedTruncatedAndDuplicateExtraFieldsForEveryHost(
        _ madeByHost: UInt8
    ) async throws {
        let expected = Data("host-independent-bad-extra".utf8)
        let hostileExtras: [Data] = [
            Data([0xFE, 0xCA, 0x04, 0x00, 0xAA]),
            Data([0xFE, 0xCA, 0x00]),
            zipExtra(identifier: 0xCAFE) + zipExtra(identifier: 0xCAFE)
        ]
        for extra in hostileExtras {
            let archive = try makeRawMetadataArchive(
                expected: expected,
                mode: S_IFREG | 0o644,
                madeByHost: madeByHost,
                centralExtra: extra
            )
            try await expectRejectedBeforeManagedWrite(archive, expected: expected)
        }
    }

    @Test(arguments: [UInt8(0), UInt8(10)])
    func rawNonUnixArchiveDoesNotInterpretUnixModeBits(_ madeByHost: UInt8) async throws {
        let expected = Data("non-unix-mode".utf8)
        let archive = try makeRawMetadataArchive(
            expected: expected,
            mode: S_IFIFO | 0o644,
            madeByHost: madeByHost
        )
        let library = try ModelLibrary(root: temporaryDirectory(), transport: NoopTransport())

        try await library.importModel(
            try fixtureManifest(expected: expected),
            from: archive,
            qualification: .qualified([.textGeneration])
        )

        guard case .ready = await library.state(for: .oneBit27B) else {
            Issue.record("Expected non-Unix host mode bits to be ignored")
            return
        }
    }

    @Test(arguments: [UInt8(3), UInt8(19)])
    func rawUnixLikeArchiveInterpretsUnixModeBits(_ madeByHost: UInt8) async throws {
        let expected = Data("unix-mode".utf8)
        let archive = try makeRawMetadataArchive(
            expected: expected,
            mode: S_IFIFO | 0o644,
            madeByHost: madeByHost
        )
        try await expectRejectedBeforeManagedWrite(archive, expected: expected)
    }
}
