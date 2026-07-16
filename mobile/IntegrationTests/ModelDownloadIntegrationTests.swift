import Foundation
import Testing
@testable import BonsaiMobile

@Suite("Real loopback model download")
struct ModelDownloadIntegrationTests {
    @Test
    func interruptedTransferResumesWithRangeAndIgnoredRangeRestarts() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let payload = Data((0 ..< 1_500_000).map { UInt8($0 % 251) })
        let payloadURL = directory.appending(path: "payload")
        let portURL = directory.appending(path: "port")
        let logURL = directory.appending(path: "requests.jsonl")
        try payload.write(to: payloadURL)
        let process = try launchServer(payload: payloadURL, portFile: portURL, logFile: logURL)
        defer {
            process.terminate()
            process.waitUntilExit()
        }
        let port = try await waitForPort(at: portURL)
        let file = try ModelManifest.File.validated(
            path: "model.safetensors",
            sizeBytes: payload.count,
            sha256: SHA256Verifier.digest(payload),
            role: .weight,
            isOptional: false
        )
        let destination = directory.appending(path: "partial/model.safetensors")
        let transport = URLSessionModelFileTransport(configuration: .ephemeral)
        let modelURL = try #require(URL(string: "http://127.0.0.1:\(port)/model"))

        await #expect(throws: (any Error).self) {
            try await transport.download(file, from: modelURL, to: destination)
        }
        let interruptedSize = try #require(
            destination.resourceValues(forKeys: [.fileSizeKey]).fileSize
        )
        #expect(interruptedSize > 0)
        #expect(interruptedSize < payload.count)

        try await transport.download(file, from: modelURL, to: destination)
        try SHA256Verifier().verify(file, at: destination)

        let ignoredRangeDestination = directory.appending(path: "ignored/model.safetensors")
        try FileManager.default.createDirectory(
            at: ignoredRangeDestination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try payload.prefix(777).write(to: ignoredRangeDestination, options: .atomic)
        let ignoreURL = try #require(URL(string: "http://127.0.0.1:\(port)/ignore"))
        try await transport.download(file, from: ignoreURL, to: ignoredRangeDestination)
        try SHA256Verifier().verify(file, at: ignoredRangeDestination)

        let log = try String(contentsOf: logURL, encoding: .utf8)
        #expect(log.contains("bytes=\(interruptedSize)-"))
        #expect(log.contains("bytes=777-"))
    }

    @Test
    func cancellationClosesTransferPreservesPartialAndResumesExactlyOnce() async throws {
        let fixture = try await LoopbackFixture.start()
        defer { fixture.stop() }
        let destination = fixture.directory.appending(path: "cancelled/model.safetensors")
        let transport = URLSessionModelFileTransport(configuration: .ephemeral)
        let slowURL = try #require(URL(string: "http://127.0.0.1:\(fixture.port)/slow"))
        let task = Task {
            try await transport.download(fixture.file, from: slowURL, to: destination)
        }
        let partialSize = try await waitForPartial(at: destination, lessThan: fixture.payload.count)

        task.cancel()
        await #expect(throws: (any Error).self) { try await task.value }
        let retainedSize = try #require(
            FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber
        ).intValue
        #expect(retainedSize >= partialSize)
        #expect(retainedSize < fixture.payload.count)

        try await transport.download(fixture.file, from: slowURL, to: destination)
        try SHA256Verifier().verify(fixture.file, at: destination)
        let log = try String(contentsOf: fixture.logURL, encoding: .utf8)
        #expect(log.contains("bytes=\(retainedSize)-"))
    }

    @Test
    func cancellationBeforeSessionStoreCompletesPromptly() async throws {
        let fixture = try await LoopbackFixture.start()
        defer { fixture.stop() }
        let destination = fixture.directory.appending(path: "precancel/model.safetensors")
        let transport = URLSessionModelFileTransport(configuration: .ephemeral)
        let slowURL = try #require(URL(string: "http://127.0.0.1:\(fixture.port)/slow"))
        let clock = ContinuousClock()
        let started = clock.now
        let task = Task {
            try await transport.download(fixture.file, from: slowURL, to: destination)
        }
        task.cancel()

        await #expect(throws: (any Error).self) { try await task.value }
        #expect(started.duration(to: clock.now) < .seconds(1))
    }

    private func waitForPartial(at url: URL, lessThan total: Int) async throws -> Int {
        for _ in 0 ..< 200 {
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
            if size > 0, size < total { return size }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw CocoaError(.fileReadUnknown)
    }

    private func launchServer(payload: URL, portFile: URL, logFile: URL) throws -> Process {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "scripts/loopback_range_server.py")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [
            script.path,
            "--payload", payload.path,
            "--port-file", portFile.path,
            "--log-file", logFile.path
        ]
        try process.run()
        return process
    }

    private func waitForPort(at url: URL) async throws -> Int {
        for _ in 0 ..< 100 {
            if let value = try? String(contentsOf: url, encoding: .utf8), let port = Int(value) {
                return port
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw CocoaError(.fileReadNoSuchFile)
    }
}

private final class LoopbackFixture: @unchecked Sendable {
    let directory: URL
    let payload: Data
    let logURL: URL
    let port: Int
    let file: ModelManifest.File
    private let process: Process

    private init(
        directory: URL,
        payload: Data,
        logURL: URL,
        port: Int,
        file: ModelManifest.File,
        process: Process
    ) {
        self.directory = directory
        self.payload = payload
        self.logURL = logURL
        self.port = port
        self.file = file
        self.process = process
    }

    static func start() async throws -> LoopbackFixture {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let payload = Data((0 ..< 1_500_000).map { UInt8($0 % 251) })
        let payloadURL = directory.appending(path: "payload")
        let portURL = directory.appending(path: "port")
        let logURL = directory.appending(path: "requests.jsonl")
        try payload.write(to: payloadURL)
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "scripts/loopback_range_server.py")
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
        return Self(
            directory: directory,
            payload: payload,
            logURL: logURL,
            port: resolvedPort,
            file: file,
            process: process
        )
    }

    func stop() {
        process.terminate()
        process.waitUntilExit()
    }
}
