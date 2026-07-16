import Foundation
import Testing
@testable import BonsaiMobile

@Suite("Runtime probe")
struct RuntimeProbeTests {
    @Test
    func rejectsMissingModelDirectory() async throws {
        let fileManager = FileManager.default
        let fixture = fileManager.temporaryDirectory.appending(
            path: "RuntimeProbeTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: fixture, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: fixture) }

        let missing = fixture.appending(path: "missing-model", directoryHint: .isDirectory)
        #expect(!fileManager.fileExists(atPath: missing.path))

        await #expect(throws: RuntimeProbe.Error.modelDirectoryMissing) {
            for try await _ in RuntimeProbe.run(modelDirectory: missing) {}
        }
    }

    @Test
    func usesFiniteDeterministicGeneration() {
        let parameters = RuntimeProbe.generationParameters

        #expect(parameters.maxTokens == 256)
        #expect(parameters.temperature == 0)
        #expect(parameters.seed == 0)
    }
}
