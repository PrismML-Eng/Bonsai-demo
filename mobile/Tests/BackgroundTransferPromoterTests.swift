import Foundation
import Testing
@testable import BonsaiMobile

@Suite("Durable background body promotion")
struct BackgroundTransferPromoterTests {
    @Test(arguments: [false, true])
    func promotionIsAtomicAndIdempotent(resuming: Bool) async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let ledger = try BackgroundTransferLedger(fileURL: root.appending(path: "transfers.json"))
        let payload = Data((0 ..< 4_096).map { UInt8($0 % 251) })
        let prefixCount = resuming ? 1_337 : 0
        let destination = root.appending(path: "model.partial")
        if resuming { try payload.prefix(prefixCount).write(to: destination) }
        let record = try await ledger.create(
            source: URL(string: "https://models.example/model")!,
            destination: destination,
            expectedSize: payload.count,
            sha256: SHA256Verifier.digest(payload),
            existingBytes: prefixCount
        )
        let temporary = root.appending(path: "callback.tmp")
        try (resuming ? Data(payload.dropFirst(prefixCount)) : payload).write(to: temporary)
        let claim = try await ledger.claimBody(
            id: record.id,
            temporaryBody: temporary,
            statusCode: resuming ? 206 : 200,
            contentRange: resuming ? "bytes \(prefixCount)-\(payload.count - 1)/\(payload.count)" : nil
        )
        let promoter = BackgroundTransferPromoter()

        try promoter.promote(claim, record: record)
        try promoter.promote(claim, record: record)

        #expect(try Data(contentsOf: destination) == payload)
        #expect(!FileManager.default.fileExists(atPath: claim.bodyURL.path))
        #expect(!FileManager.default.fileExists(atPath: destination.path + ".promotion"))
    }
}
