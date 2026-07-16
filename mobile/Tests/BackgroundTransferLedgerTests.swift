import Foundation
import Testing
@testable import BonsaiMobile

@Suite("Durable background transfer ledger")
struct BackgroundTransferLedgerTests {
    @Test
    func createPersistsUniqueTransferBeforeTaskBinding() async throws {
        let fixture = try Fixture()
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let ledger = try BackgroundTransferLedger(fileURL: fixture.ledgerURL)

        let first = try await ledger.create(
            id: firstID,
            source: fixture.source,
            destination: fixture.root.appending(path: "first.partial"),
            expectedSize: 100,
            sha256: String(repeating: "a", count: 64),
            existingBytes: 20
        )
        let second = try await ledger.create(
            id: secondID,
            source: fixture.source,
            destination: fixture.root.appending(path: "second.partial"),
            expectedSize: 200,
            sha256: String(repeating: "b", count: 64),
            existingBytes: 0
        )

        #expect(first.state == .pending)
        #expect(first.taskIdentifier == nil)
        #expect(first.taskDescription == firstID.uuidString.lowercased())
        #expect(first.taskDescription != second.taskDescription)
        #expect(FileManager.default.fileExists(atPath: fixture.ledgerURL.path))

        let relaunched = try BackgroundTransferLedger(fileURL: fixture.ledgerURL)
        #expect(await relaunched.record(id: firstID) == first)
        #expect(await relaunched.record(id: secondID) == second)
        #expect(await relaunched.activeRecord(destination: first.destination)?.id == firstID)
    }

    @Test
    func reconciliationReattachesKnownTaskAndMakesMissingTaskResumable() async throws {
        let fixture = try Fixture()
        let attachedID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
        let missingID = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
        let ledger = try BackgroundTransferLedger(fileURL: fixture.ledgerURL)
        for (id, taskIdentifier) in [(attachedID, 10), (missingID, 11)] {
            _ = try await ledger.create(
                id: id,
                source: fixture.source,
                destination: fixture.root.appending(path: "\(id).partial"),
                expectedSize: 100,
                sha256: String(repeating: "c", count: 64),
                existingBytes: 0
            )
            try await ledger.bind(id: id, taskIdentifier: taskIdentifier)
        }

        let reconciliation = try await ledger.reconcile(tasks: [
            .init(taskIdentifier: 10, taskDescription: attachedID.uuidString.lowercased()),
            .init(taskIdentifier: 99, taskDescription: "orphan"),
            .init(taskIdentifier: 100, taskDescription: attachedID.uuidString.lowercased())
        ])

        #expect(reconciliation.reattached == [.init(transferID: attachedID, taskIdentifier: 10)])
        #expect(reconciliation.taskIdentifiersToCancel == [99, 100])
        #expect(await ledger.record(id: attachedID)?.state == .running)
        #expect(await ledger.record(id: missingID)?.state == .resumable)
        #expect(await ledger.record(id: missingID)?.taskIdentifier == nil)
    }

    @Test
    func completionClassifiesOrphansAsResumableOrFailedDeterministically() async throws {
        let fixture = try Fixture()
        let resumableID = UUID(uuidString: "00000000-0000-0000-0000-000000000020")!
        let failedID = UUID(uuidString: "00000000-0000-0000-0000-000000000021")!
        let ledger = try BackgroundTransferLedger(fileURL: fixture.ledgerURL)
        for id in [resumableID, failedID] {
            _ = try await ledger.create(
                id: id,
                source: fixture.source,
                destination: fixture.root.appending(path: "\(id).partial"),
                expectedSize: 100,
                sha256: String(repeating: "d", count: 64),
                existingBytes: 0
            )
        }

        try await ledger.finish(id: resumableID, failure: "network lost", isResumable: true)
        try await ledger.finish(id: failedID, failure: "invalid response", isResumable: false)

        #expect(await ledger.record(id: resumableID)?.state == .resumable)
        #expect(await ledger.record(id: resumableID)?.failureReason == "network lost")
        #expect(await ledger.record(id: failedID)?.state == .failed)
        #expect(await ledger.record(id: failedID)?.failureReason == "invalid response")

        let relaunched = try BackgroundTransferLedger(fileURL: fixture.ledgerURL)
        #expect(await relaunched.record(id: resumableID)?.state == .resumable)
        #expect(await relaunched.record(id: failedID)?.state == .failed)
    }
}

private struct Fixture {
    let root: URL
    let ledgerURL: URL
    let source: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        ledgerURL = root.appending(path: "transfers.json")
        source = try #require(URL(string: "https://models.example/model.safetensors"))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
}
