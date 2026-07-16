import Foundation
import XCTest
@testable import BonsaiMobile

final class RuntimeProbeIntegrationTests: XCTestCase {
    func testStreamsFromPublicOneBitModel() async throws {
        guard let path = ProcessInfo.processInfo.environment["BONSAI_MODEL_DIR"],
              !path.isEmpty else {
            throw XCTSkip("Set BONSAI_MODEL_DIR to the public 1-bit Bonsai-27B MLX directory.")
        }

        let clock = ContinuousClock()
        let started = clock.now
        var firstTokenDuration: Duration?
        var output = ""
        var chunkCount = 0

        for try await chunk in RuntimeProbe.run(modelDirectory: URL(fileURLWithPath: path)) {
            if firstTokenDuration == nil {
                firstTokenDuration = started.duration(to: clock.now)
            }
            output += chunk
            chunkCount += 1
        }

        let elapsed = started.duration(to: clock.now)
        print(
            "RuntimeProbe first-token=\(String(describing: firstTokenDuration)) "
                + "elapsed=\(elapsed) chunks=\(chunkCount)"
        )
        print("RuntimeProbe output=\(output)")
        XCTAssertFalse(output.isEmpty)
        XCTAssertTrue(output.localizedCaseInsensitiveContains("bonsai ready"))
    }
}
