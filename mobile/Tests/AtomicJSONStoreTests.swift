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

    @Test
    func retainedRootDescriptorSurvivesPathReplacementWithoutTouchingExternalTarget() async throws {
        let parent = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = parent.appending(path: "root", directoryHint: .isDirectory)
        let retained = parent.appending(path: "retained", directoryHint: .isDirectory)
        let external = parent.appending(path: "external", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: false)
        try Data("external".utf8).write(to: external.appending(path: "record.json"))
        let synchronizer = RecordingDirectorySynchronizer()
        let store = try AtomicJSONStore(root: root, directorySynchronizer: synchronizer)

        try FileManager.default.moveItem(at: root, to: retained)
        try FileManager.default.createSymbolicLink(at: root, withDestinationURL: external)
        try await store.write(Data("confined".utf8), identifier: "record")

        #expect(try await store.read(identifier: "record") == Data("confined".utf8))
        #expect(try Data(contentsOf: external.appending(path: "record.json")) == Data("external".utf8))
        try await store.quarantine(identifier: "record")
        #expect(!FileManager.default.fileExists(atPath: retained.appending(path: "record.json").path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: retained.path)
            .contains { $0.hasPrefix("record.corrupt.") })
        #expect(try Data(contentsOf: external.appending(path: "record.json")) == Data("external".utf8))
        #expect(synchronizer.count == 2)
    }

    @Test
    func leafReplacedBySymlinkAfterInitializationIsNeverFollowedForWriteOrQuarantine() async throws {
        let root = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let external = root.appending(path: "outside")
        try Data("external".utf8).write(to: external)
        let store = try AtomicJSONStore(root: root)
        try FileManager.default.createSymbolicLink(
            at: root.appending(path: "record.json"),
            withDestinationURL: external
        )

        await #expect(throws: AtomicJSONStoreError.symbolicLink) {
            try await store.write(Data("replacement".utf8), identifier: "record")
        }
        await #expect(throws: AtomicJSONStoreError.symbolicLink) {
            try await store.quarantine(identifier: "record")
        }
        #expect(try Data(contentsOf: external) == Data("external".utf8))
    }

    @Test
    func leafReplacementBetweenValidationAndPromotionIsAtomicallyOverwrittenNotFollowed() async throws {
        let root = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let external = root.appending(path: "outside")
        try Data("external".utf8).write(to: external)
        let hook = ReplacingPromotionHook(root: root, external: external)
        let synchronizer = RecordingDirectorySynchronizer()
        let store = try AtomicJSONStore(
            root: root,
            directorySynchronizer: synchronizer,
            promotionHook: hook
        )
        try await store.write(Data("old".utf8), identifier: "record")
        hook.arm()

        try await store.write(Data("new".utf8), identifier: "record")

        #expect(try await store.read(identifier: "record") == Data("new".utf8))
        #expect(try Data(contentsOf: external) == Data("external".utf8))
        #expect(synchronizer.count == 2)
    }

    private static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "bonsai-atomic-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class RecordingDirectorySynchronizer: DirectorySynchronizing, @unchecked Sendable {
    private let lock = NSLock()
    private var synchronizationCount = 0
    var count: Int { lock.withLock { synchronizationCount } }

    func synchronize(directoryDescriptor: Int32) throws {
        lock.withLock { synchronizationCount += 1 }
    }
}

private final class ReplacingPromotionHook: AtomicStorePromotionHook, @unchecked Sendable {
    private let lock = NSLock()
    private let root: URL
    private let external: URL
    private var armed = false

    init(root: URL, external: URL) {
        self.root = root
        self.external = external
    }

    func arm() { lock.withLock { armed = true } }

    func willPromote(identifier: String) throws {
        let shouldReplace = lock.withLock {
            defer { armed = false }
            return armed
        }
        guard shouldReplace else { return }
        let destination = root.appending(path: "\(identifier).json")
        try FileManager.default.removeItem(at: destination)
        try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: external)
    }
}
