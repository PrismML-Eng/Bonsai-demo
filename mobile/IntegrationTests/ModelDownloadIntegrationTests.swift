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
