import Foundation

enum ToolBoundaryError: Error, Equatable, Sendable {
  case excessiveBytes
  case excessiveDepth
  case excessiveContainer
  case excessiveString
  case invalidJSON
  case expectedObject
  case missing(String)
  case invalid(String)
  case unknownTool(String)
  case duplicateToolName(String)
}

indirect enum ToolJSON: Codable, Equatable, Sendable {
  case null
  case bool(Bool)
  case int(Int)
  case double(Double)
  case string(String)
  case array([ToolJSON])
  case object([String: ToolJSON])

  static let maximumBytes = 16_384
  static let maximumDepth = 16
  static let maximumContainerCount = 128
  static let maximumStringBytes = 8_192

  static func decode(_ string: String) throws -> ToolJSON {
    guard string.utf8.count <= maximumBytes else { throw ToolBoundaryError.excessiveBytes }
    try ToolJSONPreflight.validate(Data(string.utf8))
    let value: ToolJSON
    do { value = try JSONDecoder().decode(ToolJSON.self, from: Data(string.utf8)) } catch {
      throw ToolBoundaryError.invalidJSON
    }
    try value.validate(depth: 0)
    return value
  }

  var jsonString: String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = (try? encoder.encode(self)) ?? Data("null".utf8)
    return String(data: data, encoding: .utf8) ?? "null"
  }

  func boundedJSONString() throws -> String {
    try validate(depth: 0)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(self)
    guard data.count <= Self.maximumBytes else { throw ToolBoundaryError.excessiveBytes }
    return String(data: data, encoding: .utf8) ?? "null"
  }

  func object() throws -> [String: ToolJSON] {
    guard case .object(let value) = self else { throw ToolBoundaryError.expectedObject }
    return value
  }

  func requiredString(_ key: String) throws -> String {
    let values = try object()
    guard let value = values[key] else { throw ToolBoundaryError.missing(key) }
    guard case .string(let string) = value else { throw ToolBoundaryError.invalid(key) }
    return string
  }

  func optionalString(_ key: String) throws -> String? {
    guard let value = try object()[key] else { return nil }
    guard case .string(let string) = value else { throw ToolBoundaryError.invalid(key) }
    return string
  }

  func requiredInt(_ key: String) throws -> Int {
    let values = try object()
    guard let value = values[key] else { throw ToolBoundaryError.missing(key) }
    guard case .int(let int) = value else { throw ToolBoundaryError.invalid(key) }
    return int
  }

  func requireObjectKeys(allowed: Set<String>, required: Set<String>) throws {
    let values = try object()
    guard Set(values.keys).isSubset(of: allowed) else {
      throw ToolBoundaryError.invalid("additionalProperties")
    }
    guard required.isSubset(of: Set(values.keys)) else {
      throw ToolBoundaryError.missing(required.subtracting(values.keys).sorted().first ?? "field")
    }
  }

  // Exhaustively traverses every JSON case and enforces independent limits.
  // swiftlint:disable:next cyclomatic_complexity
  private func validate(depth: Int) throws {
    guard depth <= Self.maximumDepth else { throw ToolBoundaryError.excessiveDepth }
    switch self {
    case .string(let string):
      guard string.utf8.count <= Self.maximumStringBytes else {
        throw ToolBoundaryError.excessiveString
      }
    case .array(let values):
      guard values.count <= Self.maximumContainerCount else {
        throw ToolBoundaryError.excessiveContainer
      }
      try values.forEach { try $0.validate(depth: depth + 1) }
    case .object(let values):
      guard values.count <= Self.maximumContainerCount else {
        throw ToolBoundaryError.excessiveContainer
      }
      for (key, value) in values {
        guard key.utf8.count <= Self.maximumStringBytes else {
          throw ToolBoundaryError.excessiveString
        }
        try value.validate(depth: depth + 1)
      }
    case .double(let value):
      guard value.isFinite else { throw ToolBoundaryError.invalidJSON }
    case .null, .bool, .int: break
    }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Int.self) {
      self = .int(value)
    } else if let value = try? container.decode(Double.self) {
      self = .double(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([ToolJSON].self) {
      self = .array(value)
    } else if let value = try? container.decode([String: ToolJSON].self) {
      self = .object(value)
    } else {
      throw ToolBoundaryError.invalidJSON
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null: try container.encodeNil()
    case .bool(let value): try container.encode(value)
    case .int(let value): try container.encode(value)
    case .double(let value): try container.encode(value)
    case .string(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .object(let value): try container.encode(value)
    }
  }
}

private enum ToolJSONPreflight {
  private struct Container {
    let opener: UInt8
    var separators = 0
    var hasContent = false
  }

  // Scanner exhaustively handles structural bytes before recursive decoding.
  // swiftlint:disable:next cyclomatic_complexity
  static func validate(_ data: Data) throws {
    let bytes = Array(data)
    var stack: [Container] = []
    var index = 0
    while index < bytes.count {
      let byte = bytes[index]
      switch byte {
      case 0x22:
        if !stack.isEmpty { stack[stack.count - 1].hasContent = true }
        index = try scanString(bytes, from: index + 1)
      case 0x5B, 0x7B:
        if !stack.isEmpty { stack[stack.count - 1].hasContent = true }
        stack.append(Container(opener: byte))
        guard stack.count <= ToolJSON.maximumDepth else {
          throw ToolBoundaryError.excessiveDepth
        }
        index += 1
      case 0x5D, 0x7D:
        guard let container = stack.popLast(),
              (container.opener == 0x5B && byte == 0x5D)
                || (container.opener == 0x7B && byte == 0x7D) else {
          throw ToolBoundaryError.invalidJSON
        }
        try validateCount(container)
        index += 1
      case 0x2C:
        guard !stack.isEmpty else { throw ToolBoundaryError.invalidJSON }
        stack[stack.count - 1].separators += 1
        try validateCount(stack[stack.count - 1])
        index += 1
      case 0x20, 0x09, 0x0A, 0x0D, 0x3A:
        index += 1
      default:
        if !stack.isEmpty { stack[stack.count - 1].hasContent = true }
        index += 1
      }
    }
    guard stack.isEmpty else { throw ToolBoundaryError.invalidJSON }
  }

  private static func scanString(_ bytes: [UInt8], from start: Int) throws -> Int {
    var index = start
    var rawBytes = 0
    while index < bytes.count {
      if bytes[index] == 0x22 {
        guard rawBytes <= ToolJSON.maximumStringBytes else {
          throw ToolBoundaryError.excessiveString
        }
        return index + 1
      }
      if bytes[index] == 0x5C {
        index += 1
        guard index < bytes.count else { throw ToolBoundaryError.invalidJSON }
        if bytes[index] == 0x75 {
          guard index + 4 < bytes.count else { throw ToolBoundaryError.invalidJSON }
          index += 4
        }
      }
      rawBytes += 1
      guard rawBytes <= ToolJSON.maximumStringBytes else {
        throw ToolBoundaryError.excessiveString
      }
      index += 1
    }
    throw ToolBoundaryError.invalidJSON
  }

  private static func validateCount(_ container: Container) throws {
    let count = container.hasContent ? container.separators + 1 : 0
    guard count <= ToolJSON.maximumContainerCount else {
      throw ToolBoundaryError.excessiveContainer
    }
  }
}

struct OfflineToolSchema: Equatable, Sendable {
  let name: String
  let description: String
  let parametersJSON: String
}

protocol OfflineTool: Sendable {
  var schema: OfflineToolSchema { get }
  func validate(arguments: ToolJSON) throws
  func approval(for arguments: ToolJSON) throws -> ToolApproval
  func effect(for arguments: ToolJSON) throws -> String
  func execute(arguments: ToolJSON) async throws -> ToolJSON
  func cancel() async
}

extension OfflineTool {
  func approval(for arguments: ToolJSON) throws -> ToolApproval { .automaticReadOnly }
  func effect(for arguments: ToolJSON) throws -> String { schema.description }
  func cancel() async {}
}
