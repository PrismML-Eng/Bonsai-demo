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
}

extension OfflineTool {
  func approval(for arguments: ToolJSON) throws -> ToolApproval { .automaticReadOnly }
  func effect(for arguments: ToolJSON) throws -> String { schema.description }
}
