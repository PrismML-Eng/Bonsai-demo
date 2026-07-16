import Foundation

struct BackgroundTransferRecord: Codable, Equatable, Identifiable, Sendable {
    enum State: String, Codable, Sendable {
        case pending
        case running
        case bodyClaimed
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
    var claimedBodyPath: String?
    var responseStatusCode: Int?
    var responseContentRange: String?

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
    let claimedBodies: [BackgroundTransferClaim]
}

enum BackgroundTransferLedgerError: Error, Equatable {
    case duplicateTransfer
    case unknownTransfer
}

actor BackgroundTransferLedger {
    private let fileURL: URL
    nonisolated private let bodyStore: BackgroundTransferBodyStore
    private var records: [UUID: BackgroundTransferRecord]

    init(
        fileURL: URL,
        storagePolicy: any BackgroundTransferStoragePolicy = DefaultBackgroundTransferStoragePolicy()
    ) throws {
        self.fileURL = fileURL
        bodyStore = try BackgroundTransferBodyStore(ledgerFileURL: fileURL, policy: storagePolicy)
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
            failureReason: nil,
            claimedBodyPath: nil,
            responseStatusCode: nil,
            responseContentRange: nil
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

    nonisolated func claimBodySynchronously(
        id: UUID,
        temporaryBody: URL,
        statusCode: Int,
        contentRange: String?
    ) throws -> BackgroundTransferClaim {
        try bodyStore.claim(
            id: id,
            temporaryBody: temporaryBody,
            statusCode: statusCode,
            contentRange: contentRange
        )
    }

    func claimBody(
        id: UUID,
        temporaryBody: URL,
        statusCode: Int,
        contentRange: String?
    ) throws -> BackgroundTransferClaim {
        let claim = try claimBodySynchronously(
            id: id,
            temporaryBody: temporaryBody,
            statusCode: statusCode,
            contentRange: contentRange
        )
        try adopt(claim)
        return claim
    }

    func adoptPersistedClaim(id: UUID) throws -> BackgroundTransferClaim? {
        let claims = try bodyStore.reconcile(validTransferIDs: Set(records.keys))
        guard let claim = claims.first(where: { $0.transferID == id }) else { return nil }
        try adopt(claim)
        return claim
    }

    func reconcile(tasks: [BackgroundTransferTaskIdentity]) throws -> BackgroundTransferReconciliation {
        let diskClaims = try bodyStore.reconcile(validTransferIDs: Set(records.keys))
        let claimedIDs = Set(diskClaims.map(\.transferID))
        for claim in diskClaims { try adopt(claim) }
        for (id, var record) in records where record.state == .bodyClaimed && !claimedIDs.contains(id) {
            if try destinationIsComplete(record) {
                record.state = .completed
                record.failureReason = nil
            } else {
                record.state = .resumable
                record.failureReason = "claimed body missing after reconciliation"
            }
            clearClaimFields(&record)
            records[id] = record
        }
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
            taskIdentifiersToCancel: cancellations,
            claimedBodies: diskClaims
        )
    }

    func finish(id: UUID, failure: String?, isResumable: Bool) throws {
        guard var record = records[id] else { throw BackgroundTransferLedgerError.unknownTransfer }
        record.taskIdentifier = nil
        record.failureReason = failure
        if failure != nil { try bodyStore.removeClaim(id: id, removeBody: true) }
        clearClaimFields(&record)
        if failure == nil {
            record.state = .completed
        } else {
            record.state = isResumable ? .resumable : .failed
        }
        records[id] = record
        try persist()
    }

    func markPromoted(id: UUID) throws {
        guard var record = records[id] else { throw BackgroundTransferLedgerError.unknownTransfer }
        if record.state == .completed { return }
        record.taskIdentifier = nil
        record.state = .completed
        record.failureReason = nil
        clearClaimFields(&record)
        records[id] = record
        try persist()
        try bodyStore.removeClaim(id: id, removeBody: false)
    }

    func remove(id: UUID) throws {
        records.removeValue(forKey: id)
        try persist()
        try bodyStore.removeClaim(id: id, removeBody: true)
    }

    private func adopt(_ claim: BackgroundTransferClaim) throws {
        guard var record = records[claim.transferID] else {
            try bodyStore.removeClaim(id: claim.transferID, removeBody: true)
            throw BackgroundTransferLedgerError.unknownTransfer
        }
        record.taskIdentifier = nil
        record.state = .bodyClaimed
        record.failureReason = nil
        record.claimedBodyPath = claim.bodyURL.path
        record.responseStatusCode = claim.statusCode
        record.responseContentRange = claim.contentRange
        records[record.id] = record
        try persist()
    }

    private func destinationIsComplete(_ record: BackgroundTransferRecord) throws -> Bool {
        guard FileManager.default.fileExists(atPath: record.destination.path),
              let file = try? ModelManifest.File.validated(
                  path: "background-transfer",
                  sizeBytes: record.expectedSize,
                  sha256: record.sha256,
                  role: .weight,
                  isOptional: false
              ) else { return false }
        do {
            try SHA256Verifier().verify(file, at: record.destination)
            return true
        } catch {
            return false
        }
    }

    private func clearClaimFields(_ record: inout BackgroundTransferRecord) {
        record.claimedBodyPath = nil
        record.responseStatusCode = nil
        record.responseContentRange = nil
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
