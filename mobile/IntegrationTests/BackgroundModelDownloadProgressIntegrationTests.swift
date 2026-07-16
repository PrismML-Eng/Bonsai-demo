import Foundation
import Testing
@testable import BonsaiMobile

@Suite("Real background URLSession download progress")
struct BackgroundDownloadProgressTests {
    @Test
    func downloadReusesDurableCompletionAfterSeparateRelaunchRestore() async throws {
        let fixture = try await BackgroundProgressLoopbackFixture.start()
        defer { fixture.stop() }
        let ledgerURL = fixture.directory.appending(path: "separate-restore-ledger.json")
        let destination = fixture.directory.appending(path: "separate-restore/model.safetensors")
        let transferID = UUID()
        let initialLedger = try BackgroundTransferLedger(fileURL: ledgerURL)
        _ = try await initialLedger.create(
            id: transferID,
            source: fixture.slowURL,
            destination: destination,
            expectedSize: fixture.file.sizeBytes,
            sha256: fixture.file.sha256,
            existingBytes: 0
        )
        let callbackBody = fixture.directory.appending(path: "separate-restore.download")
        try fixture.payload.write(to: callbackBody)
        _ = try await initialLedger.claimBody(
            id: transferID,
            temporaryBody: callbackBody,
            statusCode: 200,
            contentRange: nil
        )

        let relaunchedLedger = try BackgroundTransferLedger(fileURL: ledgerURL)
        let coordinator = BackgroundModelDownloadCoordinator(
            ledger: relaunchedLedger,
            configuration: .ephemeral,
            permitsLoopback: true
        )
        coordinator.restoreBackgroundTasks()
        try await waitForCompletedTransfer(transferID, in: relaunchedLedger)
        try SHA256Verifier().verify(fixture.file, at: destination)
        let recorder = BackgroundProgressRecorder()

        try await coordinator.download(
            fixture.file,
            from: fixture.slowURL,
            to: destination,
            progress: { await recorder.append($0) }
        )

        #expect(await recorder.values == [fixture.payload.count])
        #expect(fixture.requestCount == 0)
        #expect(await relaunchedLedger.allRecords().count == 1)
        #expect(await relaunchedLedger.record(id: transferID)?.state == .completed)
    }

    @Test
    func relaunchPromotesClaimWithoutCreatingReplacementDownload() async throws {
        let fixture = try await BackgroundProgressLoopbackFixture.start()
        defer { fixture.stop() }
        let ledgerURL = fixture.directory.appending(path: "relaunch-ledger.json")
        let destination = fixture.directory.appending(path: "relaunched/model.safetensors")
        let transferID = UUID()
        let initialLedger = try BackgroundTransferLedger(fileURL: ledgerURL)
        _ = try await initialLedger.create(
            id: transferID,
            source: fixture.slowURL,
            destination: destination,
            expectedSize: fixture.file.sizeBytes,
            sha256: fixture.file.sha256,
            existingBytes: 0
        )
        let callbackBody = fixture.directory.appending(path: "persisted-callback.download")
        try fixture.payload.write(to: callbackBody)
        _ = try await initialLedger.claimBody(
            id: transferID,
            temporaryBody: callbackBody,
            statusCode: 200,
            contentRange: nil
        )

        let relaunchedLedger = try BackgroundTransferLedger(fileURL: ledgerURL)
        let coordinator = BackgroundModelDownloadCoordinator(
            ledger: relaunchedLedger,
            configuration: .ephemeral,
            permitsLoopback: true
        )
        let recorder = BackgroundProgressRecorder()

        try await coordinator.download(
            fixture.file,
            from: fixture.slowURL,
            to: destination,
            progress: { await recorder.append($0) }
        )

        #expect(await recorder.values == [fixture.payload.count])
        #expect(fixture.requestCount == 0)
        #expect(await relaunchedLedger.allRecords().count == 1)
        #expect(await relaunchedLedger.record(id: transferID)?.state == .completed)
        try SHA256Verifier().verify(fixture.file, at: destination)
    }

    @Test
    func rangeDownloadReportsExistingPlusReceivedBytesAndFinishesExactly() async throws {
        let fixture = try await BackgroundProgressLoopbackFixture.start()
        defer { fixture.stop() }
        let existingBytes = 131_072
        let destination = fixture.directory.appending(path: "range/model.safetensors")
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fixture.payload.prefix(existingBytes).write(to: destination)
        let ledger = try BackgroundTransferLedger(fileURL: fixture.directory.appending(path: "ledger.json"))
        let coordinator = BackgroundModelDownloadCoordinator(
            ledger: ledger,
            configuration: .ephemeral,
            permitsLoopback: true
        )
        let recorder = BackgroundProgressRecorder()

        try await coordinator.download(
            fixture.file,
            from: fixture.slowURL,
            to: destination,
            progress: { await recorder.append($0) }
        )

        let values = await recorder.values
        #expect(values.first == existingBytes)
        #expect(values.last == fixture.payload.count)
        #expect(values.count > 2)
        #expect(values == values.sorted())
        #expect(Set(values).count == values.count)
        try SHA256Verifier().verify(fixture.file, at: destination)
    }

    @Test
    func sequentialFilesKeepAggregateProgressMonotonic() async throws {
        let fixture = try await BackgroundProgressLoopbackFixture.start()
        defer { fixture.stop() }
        let ledger = try BackgroundTransferLedger(fileURL: fixture.directory.appending(path: "ledger.json"))
        let coordinator = BackgroundModelDownloadCoordinator(
            ledger: ledger,
            configuration: .ephemeral,
            permitsLoopback: true
        )
        let recorder = BackgroundProgressRecorder()
        for index in 0 ..< 2 {
            let base = index * fixture.payload.count
            try await coordinator.download(
                fixture.file,
                from: fixture.slowURL,
                to: fixture.directory.appending(path: "file-\(index)/model.safetensors"),
                progress: { await recorder.append(base + $0) }
            )
        }

        let values = await recorder.values
        #expect(values.first == 0)
        #expect(values.last == fixture.payload.count * 2)
        #expect(values == values.sorted())
    }

    @Test
    func cancellationStopsProgressDeliveryAndLeavesResumableRecord() async throws {
        let fixture = try await BackgroundProgressLoopbackFixture.start()
        defer { fixture.stop() }
        let ledger = try BackgroundTransferLedger(fileURL: fixture.directory.appending(path: "ledger.json"))
        let coordinator = BackgroundModelDownloadCoordinator(
            ledger: ledger,
            configuration: .ephemeral,
            permitsLoopback: true
        )
        let recorder = BackgroundProgressRecorder()
        let destination = fixture.directory.appending(path: "cancel/model.safetensors")
        let task = Task {
            try await coordinator.download(
                fixture.file,
                from: fixture.slowURL,
                to: destination,
                progress: { await recorder.append($0) }
            )
        }
        try await recorder.waitUntilAtLeast(32_768)

        task.cancel()
        await #expect(throws: (any Error).self) { try await task.value }
        let countAfterCancellation = await recorder.values.count
        try await Task.sleep(for: .milliseconds(150))

        #expect(await recorder.values.count == countAfterCancellation)
        let record = try #require(await ledger.activeRecord(destination: destination))
        #expect(record.state == .resumable)
    }

    private func waitForCompletedTransfer(
        _ id: UUID,
        in ledger: BackgroundTransferLedger
    ) async throws {
        for _ in 0 ..< 300 {
            if await ledger.record(id: id)?.state == .completed { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw CocoaError(.fileReadUnknown)
    }
}

private actor BackgroundProgressRecorder {
    private(set) var values: [Int] = []

    func append(_ value: Int) {
        values.append(value)
    }

    func waitUntilAtLeast(_ target: Int) async throws {
        for _ in 0 ..< 300 {
            if values.last ?? 0 >= target { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw CocoaError(.fileReadUnknown)
    }
}

private final class BackgroundProgressLoopbackFixture: @unchecked Sendable {
    let directory: URL
    let payload: Data
    let file: ModelManifest.File
    let slowURL: URL
    let logURL: URL
    private let process: Process

    var requestCount: Int {
        guard let text = try? String(contentsOf: logURL, encoding: .utf8) else { return 0 }
        return text.split(whereSeparator: \.isNewline).count
    }

    private init(
        directory: URL,
        payload: Data,
        file: ModelManifest.File,
        slowURL: URL,
        logURL: URL,
        process: Process
    ) {
        self.directory = directory
        self.payload = payload
        self.file = file
        self.slowURL = slowURL
        self.logURL = logURL
        self.process = process
    }

    static func start() async throws -> BackgroundProgressLoopbackFixture {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "background-progress-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let payload = Data((0 ..< 786_432).map { UInt8($0 % 251) })
        let payloadURL = directory.appending(path: "payload")
        let portURL = directory.appending(path: "port")
        let logURL = directory.appending(path: "requests.jsonl")
        try payload.write(to: payloadURL)
        let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "scripts/loopback_range_server.py")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [
            script.path, "--payload", payloadURL.path,
            "--port-file", portURL.path, "--log-file", logURL.path
        ]
        try process.run()
        var port: Int?
        for _ in 0 ..< 100 where port == nil {
            if let value = try? String(contentsOf: portURL, encoding: .utf8) { port = Int(value) }
            if port == nil { try await Task.sleep(for: .milliseconds(20)) }
        }
        let resolvedPort = try #require(port)
        let file = try ModelManifest.File.validated(
            path: "model.safetensors",
            sizeBytes: payload.count,
            sha256: SHA256Verifier.digest(payload),
            role: .weight,
            isOptional: false
        )
        return try Self(
            directory: directory,
            payload: payload,
            file: file,
            slowURL: #require(URL(string: "http://127.0.0.1:\(resolvedPort)/slow")),
            logURL: logURL,
            process: process
        )
    }

    func stop() {
        process.terminate()
        process.waitUntilExit()
    }
}
