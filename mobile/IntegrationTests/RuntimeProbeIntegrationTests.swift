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
        var modelLoadDuration: Duration?
        var generationTokenCount: Int?
        var tokensPerSecond: Double?
        var output = ""

        for try await event in RuntimeProbe.measuredRun(
            modelDirectory: URL(fileURLWithPath: path)
        ) {
            switch event {
            case .modelLoaded(let duration):
                modelLoadDuration = duration
            case .chunk(let chunk):
                if firstTokenDuration == nil {
                    firstTokenDuration = started.duration(to: clock.now)
                }
                output += chunk
            case .completed(let info):
                generationTokenCount = info.generationTokenCount
                tokensPerSecond = info.tokensPerSecond
            }
        }

        let elapsed = started.duration(to: clock.now)
        print(
            "RuntimeProbe model-load=\(String(describing: modelLoadDuration)) "
                + "first-token=\(String(describing: firstTokenDuration)) elapsed=\(elapsed)"
        )
        print(
            "RuntimeProbe generated-tokens=\(String(describing: generationTokenCount)) "
                + "tokens-per-second=\(String(describing: tokensPerSecond))"
        )
        print("RuntimeProbe output=\(output)")
        XCTAssertNotNil(modelLoadDuration)
        XCTAssertNotNil(firstTokenDuration)
        XCTAssertGreaterThan(generationTokenCount ?? 0, 0)
        XCTAssertGreaterThan(tokensPerSecond ?? 0, 0)
        XCTAssertFalse(output.isEmpty)
        XCTAssertTrue(output.localizedCaseInsensitiveContains("bonsai ready"))
    }
}
