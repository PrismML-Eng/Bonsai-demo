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

    @Test
    func claimedBodySurvivesProcessMemoryLossAndReconcilesForPromotion() async throws {
        let fixture = try Fixture()
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000030")!
        let policy = RecordingStoragePolicy()
        let ledger = try BackgroundTransferLedger(fileURL: fixture.ledgerURL, storagePolicy: policy)
        _ = try await ledger.create(
            id: id,
            source: fixture.source,
            destination: fixture.root.appending(path: "model.partial"),
            expectedSize: fixture.payload.count,
            sha256: SHA256Verifier.digest(fixture.payload),
            existingBytes: 0
        )
        let temporary = fixture.root.appending(path: "callback.tmp")
        try fixture.payload.write(to: temporary)

        let claimed = try await ledger.claimBody(
            id: id,
            temporaryBody: temporary,
            statusCode: 200,
            contentRange: nil
        )

        #expect(claimed.bodyURL == fixture.claimedBodyURL(id: id))
        #expect(await ledger.record(id: id)?.state == .bodyClaimed)
        #expect(policy.appliedURLs.contains(claimed.bodyURL))
        let resourceValues = try claimed.bodyURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(resourceValues.isExcludedFromBackup == true)

        let relaunched = try BackgroundTransferLedger(fileURL: fixture.ledgerURL)
        let reconciliation = try await relaunched.reconcile(tasks: [])
        #expect(reconciliation.claimedBodies == [claimed])
        #expect(await relaunched.record(id: id)?.state == .bodyClaimed)
    }

    @Test
    func duplicateClaimAndCompletionCallbacksAreIdempotent() async throws {
        let fixture = try Fixture()
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000031")!
        let ledger = try BackgroundTransferLedger(fileURL: fixture.ledgerURL)
        _ = try await ledger.create(
            id: id,
            source: fixture.source,
            destination: fixture.root.appending(path: "model.partial"),
            expectedSize: fixture.payload.count,
            sha256: SHA256Verifier.digest(fixture.payload),
            existingBytes: 0
        )
        let first = fixture.root.appending(path: "first.tmp")
        let duplicate = fixture.root.appending(path: "duplicate.tmp")
        try fixture.payload.write(to: first)
        try Data("duplicate".utf8).write(to: duplicate)

        let initial = try await ledger.claimBody(
            id: id,
            temporaryBody: first,
            statusCode: 200,
            contentRange: nil
        )
        let repeated = try await ledger.claimBody(
            id: id,
            temporaryBody: duplicate,
            statusCode: 200,
            contentRange: nil
        )

        #expect(initial == repeated)
        #expect(try Data(contentsOf: initial.bodyURL) == fixture.payload)
        #expect(!FileManager.default.fileExists(atPath: duplicate.path))
        try await ledger.markPromoted(id: id)
        try await ledger.markPromoted(id: id)
        #expect(await ledger.record(id: id)?.state == .completed)
    }

    @Test
    func reconciliationCleansUnknownAndUnpersistedClaimBodies() async throws {
        let fixture = try Fixture()
        let knownID = UUID(uuidString: "00000000-0000-0000-0000-000000000032")!
        let unknownID = UUID(uuidString: "00000000-0000-0000-0000-000000000033")!
        let ledger = try BackgroundTransferLedger(fileURL: fixture.ledgerURL)
        _ = try await ledger.create(
            id: knownID,
            source: fixture.source,
            destination: fixture.root.appending(path: "model.partial"),
            expectedSize: fixture.payload.count,
            sha256: SHA256Verifier.digest(fixture.payload),
            existingBytes: 0
        )
        try FileManager.default.createDirectory(
            at: fixture.downloadsRoot,
            withIntermediateDirectories: true
        )
        let knownOrphan = fixture.claimedBodyURL(id: knownID)
        let unknownOrphan = fixture.claimedBodyURL(id: unknownID)
        try fixture.payload.write(to: knownOrphan)
        try fixture.payload.write(to: unknownOrphan)

        let reconciliation = try await ledger.reconcile(tasks: [])

        #expect(reconciliation.claimedBodies.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: knownOrphan.path))
        #expect(!FileManager.default.fileExists(atPath: unknownOrphan.path))
        #expect(await ledger.record(id: knownID)?.state == .resumable)
    }

    @Test
    func reconciliationRecognizesPromotionCompletedBeforeLedgerUpdate() async throws {
        let fixture = try Fixture()
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000034")!
        let destination = fixture.root.appending(path: "model.partial")
        let ledger = try BackgroundTransferLedger(fileURL: fixture.ledgerURL)
        _ = try await ledger.create(
            id: id,
            source: fixture.source,
            destination: destination,
            expectedSize: fixture.payload.count,
            sha256: SHA256Verifier.digest(fixture.payload),
            existingBytes: 0
        )
        let temporary = fixture.root.appending(path: "callback.tmp")
        try fixture.payload.write(to: temporary)
        let claim = try await ledger.claimBody(
            id: id,
            temporaryBody: temporary,
            statusCode: 200,
            contentRange: nil
        )
        try FileManager.default.moveItem(at: claim.bodyURL, to: destination)

        let relaunched = try BackgroundTransferLedger(fileURL: fixture.ledgerURL)
        let reconciliation = try await relaunched.reconcile(tasks: [])

        #expect(reconciliation.claimedBodies.isEmpty)
        #expect(await relaunched.record(id: id)?.state == .completed)
    }
}

private final class RecordingStoragePolicy: BackgroundTransferStoragePolicy, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []

    var appliedURLs: [URL] { lock.withLock { storage } }

    func applyRecursively(to url: URL) throws {
        lock.withLock { storage.append(url) }
        try DefaultBackgroundTransferStoragePolicy().applyRecursively(to: url)
    }
}

private struct Fixture {
    let root: URL
    let ledgerURL: URL
    let source: URL
    let payload = Data("durable model body".utf8)

    var downloadsRoot: URL {
        root.appending(path: "Downloads", directoryHint: .isDirectory)
    }

    func claimedBodyURL(id: UUID) -> URL {
        downloadsRoot.appending(path: "\(id.uuidString.lowercased()).download")
    }

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        ledgerURL = root.appending(path: "transfers.json")
        source = try #require(URL(string: "https://models.example/model.safetensors"))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
}
