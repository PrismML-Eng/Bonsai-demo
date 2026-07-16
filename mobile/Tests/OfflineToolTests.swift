import Foundation
import Testing

@testable import BonsaiMobile

@Suite("Fixed offline tool registry")
struct OfflineToolTests {
  @Test func exposesExactlyFourStableTools() throws {
    let registry = try ToolRegistry.live(notes: NotesStore(root: temporaryDirectory()))
    #expect(
      registry.specifications.map(\.name) == [
        "calculator", "current_date_time", "device_information", "local_notes"
      ])
    #expect(registry.specifications.allSatisfy { !$0.parametersJSON.isEmpty })
  }

  @Test func boundedJSONRejectsDeepAndOversizedInput() {
    let deep = String(repeating: "{\"x\":", count: 17) + "0" + String(repeating: "}", count: 17)
    #expect(throws: ToolBoundaryError.excessiveDepth) { try ToolJSON.decode(deep) }
    #expect(throws: ToolBoundaryError.excessiveBytes) {
      try ToolJSON.decode("{\"x\":\"" + String(repeating: "a", count: 20_000) + "\"}")
    }
  }

  @Test func boundedEncoderRejectsEveryResultBoundary() {
    #expect(throws: ToolBoundaryError.excessiveDepth) {
      try nestedJSON(depth: 17).boundedJSONString()
    }
    #expect(throws: ToolBoundaryError.excessiveContainer) {
      try ToolJSON.array(Array(repeating: .null, count: 129)).boundedJSONString()
    }
    #expect(throws: ToolBoundaryError.excessiveString) {
      try ToolJSON.string(String(repeating: "x", count: 8_193)).boundedJSONString()
    }
    #expect(throws: ToolBoundaryError.excessiveBytes) {
      let values = (0..<128).map { ToolJSON.string(String(repeating: "x", count: 127) + "\($0)") }
      _ = try ToolJSON.array(values).boundedJSONString()
    }
  }

  @Test func preflightRejectsExtremeNestingBeforeFoundationDecode() {
    let deep = String(repeating: "[", count: 500) + "0" + String(repeating: "]", count: 500)
    #expect(throws: ToolBoundaryError.excessiveDepth) { try ToolJSON.decode(deep) }
  }

  @Test func dateAndDeviceResultsAreDeterministicAndPrivate() async throws {
    let date = DateTool(
      now: { Date(timeIntervalSince1970: 0) }, locale: Locale(identifier: "en_US_POSIX"),
      timeZone: TimeZone(secondsFromGMT: 0)!)
    let dateResult = try await date.execute(arguments: .object([:])).jsonString
    #expect(dateResult.contains("1970-01-01T00:00:00Z"))

    let device = DeviceInfoTool(provider: FixedDeviceInfoProvider())
    let result = try await device.execute(arguments: .object([:])).jsonString
    #expect(result.contains("phone"))
    #expect(!result.contains("Alice"))
    #expect(!result.contains("vendor"))
  }

  private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "OfflineToolTests-\(UUID())")
  }

  private func nestedJSON(depth: Int) -> ToolJSON {
    (0..<depth).reduce(.null) { value, _ in .array([value]) }
  }
}

private struct FixedDeviceInfoProvider: DeviceInfoProviding {
  let modelClass = "phone"
  let operatingSystem = "iOS"
  let operatingSystemVersion = "26.0"
  let localeIdentifier = "en_US"
  let physicalMemoryBytes: UInt64 = 8 * 1_024 * 1_024 * 1_024
  let thermalState = "nominal"
}
