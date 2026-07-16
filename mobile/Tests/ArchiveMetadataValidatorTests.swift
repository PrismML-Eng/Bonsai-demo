import Darwin
import Testing
@testable import BonsaiMobile

@Suite("Archive Unix metadata")
struct ArchiveMetadataValidatorTests {
    @Test(arguments: [S_IFIFO, S_IFSOCK, S_IFCHR, S_IFBLK, S_IFLNK])
    func rejectsUnsupportedUnixEntryModes(_ type: mode_t) {
        #expect(throws: (any Error).self) {
            try ArchiveMetadataValidator().validateUnixMetadata(mode: type | 0o644, extraFieldIDs: [])
        }
    }

    @Test(arguments: [UInt16(0x000D), UInt16(0x756E)])
    func rejectsUnixHardLinkMetadata(_ identifier: UInt16) {
        #expect(throws: (any Error).self) {
            try ArchiveMetadataValidator().validateUnixMetadata(
                mode: S_IFREG | 0o644,
                extraFieldIDs: [identifier]
            )
        }
    }

    @Test
    func acceptsRegularFilesAndDirectoriesWithoutLinkMetadata() throws {
        try ArchiveMetadataValidator().validateUnixMetadata(mode: S_IFREG | 0o644, extraFieldIDs: [])
        try ArchiveMetadataValidator().validateUnixMetadata(mode: S_IFDIR | 0o755, extraFieldIDs: [])
    }
}
