import Foundation

enum BackgroundTransferLedgerStorage {
    static func persist(
        _ records: [UUID: BackgroundTransferRecord],
        to fileURL: URL
    ) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let sortedRecords = records.values.sorted { $0.taskDescription < $1.taskDescription }
        let data = try encoder.encode(sortedRecords)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = fileURL
        try mutableURL.setResourceValues(values)
    }

    static func decode(_ data: Data) throws -> [UUID: BackgroundTransferRecord] {
        guard let rawRecords = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw BackgroundTransferLedgerCorruption.malformedData
        }
        for rawRecord in rawRecords {
            guard let rawState = rawRecord["state"] as? String else { continue }
            guard BackgroundTransferRecord.State(rawValue: rawState) != nil else {
                throw BackgroundTransferLedgerCorruption.unsupportedState(rawState)
            }
        }

        let stored = try JSONDecoder().decode([BackgroundTransferRecord].self, from: data)
        var decoded: [UUID: BackgroundTransferRecord] = [:]
        for record in stored {
            guard decoded.updateValue(record, forKey: record.id) == nil else {
                throw BackgroundTransferLedgerCorruption.duplicateTransferID(record.id)
            }
        }
        return decoded
    }

    static func quarantine(
        _ fileURL: URL,
        corruption: BackgroundTransferLedgerCorruption
    ) throws -> BackgroundTransferLedgerRecovery {
        let quarantinedFile = fileURL.appendingPathExtension("corrupt-\(UUID().uuidString.lowercased())")
        try FileManager.default.moveItem(at: fileURL, to: quarantinedFile)
        return BackgroundTransferLedgerRecovery(
            corruption: corruption,
            quarantinedFile: quarantinedFile
        )
    }
}
