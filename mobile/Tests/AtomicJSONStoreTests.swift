import Foundation
import Testing
@testable import BonsaiMobile

@Suite("Atomic protected JSON storage")
struct AtomicJSONStoreTests {
    @Test
    func failedWriteLeavesLastSynchronizedFileIntact() async throws {
        let root = try Self.temporaryDirectory()
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: root.path
            )
            try? FileManager.default.removeItem(at: root)
        }
        let store = try AtomicJSONStore(root: root)
        try await store.write(Data("last-good".utf8), identifier: "record")
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)

        await #expect(throws: (any Error).self) {
            try await store.write(Data("partial-new".utf8), identifier: "record")
        }

        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        #expect(try await store.read(identifier: "record") == Data("last-good".utf8))
    }

    @Test
    func symlinkedLeafIsRejectedWithoutReadingItsTarget() async throws {
        let root = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appending(path: "outside")
        try Data("outside-secret".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(
            at: root.appending(path: "record.json"),
            withDestinationURL: target
        )
        let store = try AtomicJSONStore(root: root)

        await #expect(throws: AtomicJSONStoreError.symbolicLink) {
            _ = try await store.read(identifier: "record")
        }
        #expect(try String(contentsOf: target, encoding: .utf8) == "outside-secret")
    }

    private static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "bonsai-atomic-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
