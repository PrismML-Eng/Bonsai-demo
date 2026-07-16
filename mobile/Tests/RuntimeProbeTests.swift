import Foundation
import Testing
@testable import BonsaiMobile

@Suite("Runtime probe")
struct RuntimeProbeTests {
    @Test
    func rejectsMissingModelDirectory() async {
        let missing = URL(fileURLWithPath: "/tmp/bonsai-model-does-not-exist")

        await #expect(throws: RuntimeProbe.Error.modelDirectoryMissing) {
            for try await _ in RuntimeProbe.run(modelDirectory: missing) {}
        }
    }
}
