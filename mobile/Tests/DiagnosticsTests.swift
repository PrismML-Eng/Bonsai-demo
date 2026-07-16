import Foundation
import Testing
@testable import BonsaiMobile

@Suite("Content-free diagnostics")
struct DiagnosticsTests {
    @Test
    func encodedRecordUsesOnlyTheAllowlistAndCannotContainContentSentinels() throws {
        let record = try Self.record(index: 1)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let text = try #require(String(data: encoder.encode(record), encoding: .utf8))

        for forbidden in [
            "SECRET_PROMPT", "SECRET_REASONING", "SECRET_ANSWER", "SECRET_IMAGE_PATH",
            "SECRET_NOTE", "SECRET_TOOL", "https://download.example/model", "metadata"
        ] {
            #expect(!text.contains(forbidden))
        }
        #expect(Set(try Self.jsonKeys(text)) == [
            "category", "elapsedMilliseconds", "generatedTokenCount", "memoryWarningCount",
            "modelID", "modelRevision", "promptTokenCount", "stage", "thermalState",
            "timestamp", "tokenRate"
        ])
    }

    @Test
    func storeRetainsOnlyNewestRecordsInDeterministicOrder() async throws {
        let root = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try DiagnosticsStore(root: root, retentionLimit: 3)

        for index in 0..<5 {
            try await store.append(Self.record(index: index))
        }

        #expect(try await store.records().map(\.elapsedMilliseconds) == [2, 3, 4])
    }

    @Test
    func corruptDiagnosticsAreQuarantinedWithTypedError() async throws {
        let root = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appending(path: "Diagnostics")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("sentinel-corrupt".utf8).write(to: directory.appending(path: "events.json"))
        let store = try DiagnosticsStore(root: root, retentionLimit: 3)

        await #expect(throws: DiagnosticsStoreError.corruptLog) {
            _ = try await store.records()
        }

        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(names.count == 1)
        #expect(names[0].hasPrefix("events.corrupt."))
    }

    @Test
    func failedAppendPreservesPriorSynchronizedEnvelopeBytesAndRecords() async throws {
        let root = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let backing = try AtomicJSONStore(root: root)
        let storage = FailingAtomicDiagnosticStorage(backing: backing)
        let store = try DiagnosticsStore(storage: storage, retentionLimit: 3)
        let original = try Self.record(index: 1)
        try await store.append(original)
        let originalBytes = try #require(await backing.read(identifier: "events"))
        await storage.failNextWrite()

        await #expect(throws: DiagnosticStorageFailure.injected) {
            try await store.append(Self.record(index: 2))
        }

        #expect(try await backing.read(identifier: "events") == originalBytes)
        #expect(try await store.records() == [original])
    }

    private static func record(index: Int) throws -> DiagnosticRecord {
        try DiagnosticRecord(
            stage: .generation,
            category: .completed,
            elapsedMilliseconds: index,
            promptTokenCount: 10,
            generatedTokenCount: 20,
            tokenRate: 11.5,
            thermalState: .nominal,
            memoryWarningCount: 0,
            modelID: .oneBit27B,
            modelRevision: String(repeating: "a", count: 40),
            timestamp: Date(timeIntervalSince1970: TimeInterval(index))
        )
    }

    private static func jsonKeys(_ text: String) throws -> [String] {
        let object = try JSONSerialization.jsonObject(with: Data(text.utf8))
        return try #require(object as? [String: Any]).keys.map { $0 }
    }

    private static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "bonsai-diagnostics-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private enum DiagnosticStorageFailure: Error { case injected }

private actor FailingAtomicDiagnosticStorage: AtomicDataStoring {
    private let backing: AtomicJSONStore
    private var shouldFailWrite = false

    init(backing: AtomicJSONStore) { self.backing = backing }

    func read(identifier: String) async throws -> Data? {
        try await backing.read(identifier: identifier)
    }

    func write(_ data: Data, identifier: String) async throws {
        if shouldFailWrite {
            shouldFailWrite = false
            throw DiagnosticStorageFailure.injected
        }
        try await backing.write(data, identifier: identifier)
    }

    func quarantine(identifier: String) async throws {
        try await backing.quarantine(identifier: identifier)
    }

    func failNextWrite() { shouldFailWrite = true }
}
