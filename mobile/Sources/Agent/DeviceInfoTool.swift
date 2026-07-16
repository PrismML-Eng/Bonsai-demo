import Foundation

protocol DeviceInfoProviding: Sendable {
  var modelClass: String { get }
  var operatingSystem: String { get }
  var operatingSystemVersion: String { get }
  var localeIdentifier: String { get }
  var physicalMemoryBytes: UInt64 { get }
  var thermalState: String { get }
}

struct SystemDeviceInfoProvider: DeviceInfoProviding {
  var modelClass: String {
    #if os(iOS)
      "phone-or-tablet"
    #else
      "mac"
    #endif
  }
  var operatingSystem: String { ProcessInfo.processInfo.operatingSystemVersionString }
  var operatingSystemVersion: String {
    let version = ProcessInfo.processInfo.operatingSystemVersion
    return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
  }
  var localeIdentifier: String { Locale.current.identifier }
  var physicalMemoryBytes: UInt64 { ProcessInfo.processInfo.physicalMemory }
  var thermalState: String {
    switch ProcessInfo.processInfo.thermalState {
    case .nominal: "nominal"
    case .fair: "fair"
    case .serious: "serious"
    case .critical: "critical"
    @unknown default: "unknown"
    }
  }
}

struct DeviceInfoTool: OfflineTool {
  let schema = OfflineToolSchema(
    name: "device_information",
    description: "Return coarse, privacy-preserving device capabilities.",
    parametersJSON: "{\"additionalProperties\":false,\"properties\":{},\"type\":\"object\"}"
  )
  let provider: any DeviceInfoProviding

  init(provider: any DeviceInfoProviding = SystemDeviceInfoProvider()) {
    self.provider = provider
  }

  func validate(arguments: ToolJSON) throws {
    guard try arguments.object().isEmpty else { throw ToolBoundaryError.invalid("arguments") }
  }

  func execute(arguments: ToolJSON) async throws -> ToolJSON {
    try validate(arguments: arguments)
    return .object([
      "modelClass": .string(provider.modelClass),
      "operatingSystem": .string(provider.operatingSystem),
      "operatingSystemVersion": .string(provider.operatingSystemVersion),
      "locale": .string(provider.localeIdentifier),
      "physicalMemoryBucket": .string(Self.memoryBucket(provider.physicalMemoryBytes)),
      "thermalState": .string(provider.thermalState)
    ])
  }

  private static func memoryBucket(_ bytes: UInt64) -> String {
    let gibibytes = bytes / (1_024 * 1_024 * 1_024)
    return switch gibibytes {
    case ..<4: "under-4-GiB"
    case 4..<8: "4-7-GiB"
    case 8..<16: "8-15-GiB"
    default: "16-GiB-or-more"
    }
  }
}
