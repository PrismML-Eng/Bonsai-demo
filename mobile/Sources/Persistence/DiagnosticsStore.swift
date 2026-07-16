import Foundation

enum DiagnosticsStoreError: Error, Equatable, Sendable {
    case invalidRetentionLimit
    case corruptLog
}

actor DiagnosticsStore {
    private struct Envelope: Codable, Sendable {
        let records: [DiagnosticRecord]
    }

    private let storage: any AtomicDataStoring
    private let retentionLimit: Int

    init(root: URL, retentionLimit: Int = 200) throws {
        try self.init(
            storage: AtomicJSONStore(root: root.appending(path: "Diagnostics")),
            retentionLimit: retentionLimit
        )
    }

    init(storage: any AtomicDataStoring, retentionLimit: Int = 200) throws {
        guard retentionLimit > 0 else {
            throw DiagnosticsStoreError.invalidRetentionLimit
        }
        self.storage = storage
        self.retentionLimit = retentionLimit
    }

    func append(_ record: DiagnosticRecord) async throws {
        var current = try await loadRecords()
        current.append(record)
        if current.count > retentionLimit {
            current.removeFirst(current.count - retentionLimit)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(Envelope(records: current))
        try await storage.write(data, identifier: "events")
    }

    func records() async throws -> [DiagnosticRecord] {
        try await loadRecords()
    }

    private func loadRecords() async throws -> [DiagnosticRecord] {
        guard let data = try await storage.read(identifier: "events") else { return [] }
        do {
            return try JSONDecoder().decode(Envelope.self, from: data).records
        } catch {
            try await storage.quarantine(identifier: "events")
            throw DiagnosticsStoreError.corruptLog
        }
    }
}
