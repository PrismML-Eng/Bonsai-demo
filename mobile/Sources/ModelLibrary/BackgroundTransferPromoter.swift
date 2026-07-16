import Darwin
import Foundation

struct BackgroundTransferPromoter: Sendable {
    private let policy: any BackgroundTransferStoragePolicy

    init(
        policy: any BackgroundTransferStoragePolicy = DefaultBackgroundTransferStoragePolicy()
    ) {
        self.policy = policy
    }

    func promote(_ claim: BackgroundTransferClaim, record: BackgroundTransferRecord) throws {
        guard (200 ... 299).contains(claim.statusCode) else {
            throw ModelTransportError.httpStatus(claim.statusCode)
        }
        if isComplete(record.destination, record: record) {
            try removeIfPresent(claim.bodyURL)
            try policy.applyRecursively(to: record.destination)
            return
        }

        let append = record.existingBytes > 0 && claim.statusCode == 206
        if append, !URLSessionModelFileTransport.contentRangeStarts(
            claim.contentRange,
            at: record.existingBytes
        ) {
            throw ModelTransportError.invalidContentRange
        }
        try FileManager.default.createDirectory(
            at: record.destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let promotion = URL(fileURLWithPath: record.destination.path + ".promotion")
        try removeIfPresent(promotion)
        if append {
            try buildCombinedBody(record: record, tail: claim.bodyURL, at: promotion)
        } else {
            try FileManager.default.copyItem(at: claim.bodyURL, to: promotion)
        }
        try verify(promotion, record: record)
        try policy.applyRecursively(to: promotion)
        guard rename(promotion.path, record.destination.path) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        try policy.applyRecursively(to: record.destination)
        try removeIfPresent(claim.bodyURL)
    }

    private func buildCombinedBody(
        record: BackgroundTransferRecord,
        tail: URL,
        at promotion: URL
    ) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: record.destination.path)
        guard (attributes[.size] as? NSNumber)?.intValue == record.existingBytes,
              FileManager.default.createFile(atPath: promotion.path, contents: nil) else {
            throw ModelLibraryError.sizeMismatch(record.destination.lastPathComponent)
        }
        let output = try FileHandle(forWritingTo: promotion)
        defer { try? output.close() }
        for source in [record.destination, tail] {
            let input = try FileHandle(forReadingFrom: source)
            defer { try? input.close() }
            while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
                try output.write(contentsOf: chunk)
            }
        }
        try output.synchronize()
    }

    private func verify(_ url: URL, record: BackgroundTransferRecord) throws {
        let file = try ModelManifest.File.validated(
            path: "background-transfer",
            sizeBytes: record.expectedSize,
            sha256: record.sha256,
            role: .weight,
            isOptional: false
        )
        try SHA256Verifier().verify(file, at: url)
    }

    private func isComplete(_ url: URL, record: BackgroundTransferRecord) -> Bool {
        do {
            try verify(url, record: record)
            return true
        } catch {
            return false
        }
    }

    private func removeIfPresent(_ url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
