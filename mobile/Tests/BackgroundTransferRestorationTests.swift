import Foundation
import Testing
@testable import BonsaiMobile

@Suite("Durable background transfer restoration")
struct BackgroundTransferRestorationTests {
    @Test
    func durablyBoundSuspendedTaskResumesAfterReconciliation() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "bonsai-restoration-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let ledgerURL = root.appending(path: "transfers.json")
        let id = UUID()
        let initial = try BackgroundTransferLedger(fileURL: ledgerURL)
        _ = try await initial.create(
            id: id,
            source: URL(string: "https://example.com/model.bin")!,
            destination: root.appending(path: "model.partial"),
            expectedSize: 10,
            sha256: String(repeating: "a", count: 64),
            existingBytes: 0
        )
        try await initial.bind(id: id, taskIdentifier: 42)

        let relaunched = try BackgroundTransferLedger(fileURL: ledgerURL)
        let result = try await relaunched.reconcile(tasks: [
            .init(
                taskIdentifier: 42,
                taskDescription: id.uuidString.lowercased(),
                state: .suspended
            )
        ])

        #expect(result.reattached == [
            .init(transferID: id, taskIdentifier: 42, decision: .resume)
        ])
        #expect(await relaunched.record(id: id)?.state == .running)
    }
}
