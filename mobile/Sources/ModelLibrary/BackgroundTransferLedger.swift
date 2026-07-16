import Foundation

struct BackgroundTransferRecord: Codable, Equatable, Identifiable, Sendable {
    enum State: String, Codable, Sendable {
        case pending
        case running
        case resumable
        case failed
        case completed
    }

    let id: UUID
    let source: URL
    let destination: URL
    let expectedSize: Int
    let sha256: String
    let existingBytes: Int
    var taskIdentifier: Int?
    var state: State
    var failureReason: String?

    var taskDescription: String { id.uuidString.lowercased() }
}

struct BackgroundTransferTaskIdentity: Equatable, Sendable {
    let taskIdentifier: Int
    let taskDescription: String?
}

struct BackgroundTransferAttachment: Equatable, Sendable {
    let transferID: UUID
    let taskIdentifier: Int
}

struct BackgroundTransferReconciliation: Equatable, Sendable {
    let reattached: [BackgroundTransferAttachment]
    let taskIdentifiersToCancel: [Int]
}

enum BackgroundTransferLedgerError: Error, Equatable {
    case duplicateTransfer
    case unknownTransfer
}

actor BackgroundTransferLedger {
    private let fileURL: URL
    private var records: [UUID: BackgroundTransferRecord]

    init(fileURL: URL) throws {
        self.fileURL = fileURL
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let stored = try JSONDecoder().decode(
                [BackgroundTransferRecord].self,
                from: Data(contentsOf: fileURL)
            )
            records = Dictionary(uniqueKeysWithValues: stored.map { ($0.id, $0) })
        } else {
            records = [:]
        }
    }

    func create(
        id: UUID = UUID(),
        source: URL,
        destination: URL,
        expectedSize: Int,
        sha256: String,
        existingBytes: Int
    ) throws -> BackgroundTransferRecord {
        guard records[id] == nil else { throw BackgroundTransferLedgerError.duplicateTransfer }
        let record = BackgroundTransferRecord(
            id: id,
            source: source,
            destination: destination,
            expectedSize: expectedSize,
            sha256: sha256,
            existingBytes: existingBytes,
            taskIdentifier: nil,
            state: .pending,
            failureReason: nil
        )
        records[id] = record
        try persist()
        return record
    }

    func record(id: UUID) -> BackgroundTransferRecord? {
        records[id]
    }

    func activeRecord(destination: URL) -> BackgroundTransferRecord? {
        records.values.first {
            $0.destination.standardizedFileURL == destination.standardizedFileURL &&
                $0.state != .completed && $0.state != .failed
        }
    }

    func allRecords() -> [BackgroundTransferRecord] {
        records.values.sorted { $0.taskDescription < $1.taskDescription }
    }

    func bind(id: UUID, taskIdentifier: Int) throws {
        guard var record = records[id] else { throw BackgroundTransferLedgerError.unknownTransfer }
        record.taskIdentifier = taskIdentifier
        record.state = .running
        record.failureReason = nil
        records[id] = record
        try persist()
    }

    func reconcile(tasks: [BackgroundTransferTaskIdentity]) throws -> BackgroundTransferReconciliation {
        var claimed = Set<UUID>()
        var attachments: [BackgroundTransferAttachment] = []
        var cancellations: [Int] = []

        for task in tasks.sorted(by: { $0.taskIdentifier < $1.taskIdentifier }) {
            guard let description = task.taskDescription,
                  let id = UUID(uuidString: description),
                  var record = records[id],
                  record.state != .failed,
                  record.state != .completed,
                  !claimed.contains(id),
                  record.taskIdentifier == nil || record.taskIdentifier == task.taskIdentifier else {
                cancellations.append(task.taskIdentifier)
                continue
            }
            claimed.insert(id)
            record.taskIdentifier = task.taskIdentifier
            record.state = .running
            record.failureReason = nil
            records[id] = record
            attachments.append(.init(transferID: id, taskIdentifier: task.taskIdentifier))
        }

        for (id, var record) in records where !claimed.contains(id) {
            if record.state == .pending || record.state == .running {
                record.taskIdentifier = nil
                record.state = .resumable
                record.failureReason = "background task missing after reconciliation"
                records[id] = record
            }
        }
        try persist()
        return BackgroundTransferReconciliation(
            reattached: attachments,
            taskIdentifiersToCancel: cancellations
        )
    }

    func finish(id: UUID, failure: String?, isResumable: Bool) throws {
        guard var record = records[id] else { throw BackgroundTransferLedgerError.unknownTransfer }
        record.taskIdentifier = nil
        record.failureReason = failure
        if failure == nil {
            record.state = .completed
        } else {
            record.state = isResumable ? .resumable : .failed
        }
        records[id] = record
        try persist()
    }

    func remove(id: UUID) throws {
        records.removeValue(forKey: id)
        try persist()
    }

    private func persist() throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(allRecords())
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = fileURL
        try mutableURL.setResourceValues(values)
    }
}
