import Foundation

struct NotesTool: OfflineTool {
  let schema = OfflineToolSchema(
    name: "local_notes",
    description: "List, read, create, update, or delete private local notes.",
    parametersJSON:
      // swiftlint:disable:next line_length
      "{\"additionalProperties\":false,\"properties\":{\"action\":{\"enum\":[\"list\",\"read\",\"create\",\"update\",\"delete\"],\"type\":\"string\"},\"body\":{\"maxLength\":8192,\"type\":\"string\"},\"expectedRevision\":{\"minimum\":1,\"type\":\"integer\"},\"id\":{\"type\":\"string\"},\"title\":{\"maxLength\":256,\"type\":\"string\"}},\"required\":[\"action\"],\"type\":\"object\"}"
  )
  let store: NotesStore

  // Action-specific schemas deliberately share one exhaustive boundary.
  // swiftlint:disable:next cyclomatic_complexity
  func validate(arguments: ToolJSON) throws {
    let action = try arguments.requiredString("action")
    let allowed: Set<String>
    let required: Set<String>
    switch action {
    case "list":
      allowed = ["action"]
      required = ["action"]
    case "read":
      allowed = ["action", "id"]
      required = allowed
    case "create":
      allowed = ["action", "title", "body"]
      required = allowed
    case "update":
      allowed = ["action", "id", "expectedRevision", "title", "body"]
      required = allowed
    case "delete":
      allowed = ["action", "id", "expectedRevision"]
      required = allowed
    default: throw ToolBoundaryError.invalid("action")
    }
    try arguments.requireObjectKeys(allowed: allowed, required: required)
    if allowed.contains("id") { _ = try noteID(arguments) }
    if allowed.contains("expectedRevision") {
      guard try arguments.requiredInt("expectedRevision") >= 1 else {
        throw ToolBoundaryError.invalid("expectedRevision")
      }
    }
    if allowed.contains("title") {
      let title = try arguments.requiredString("title")
      guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            title.utf8.count <= NotesStore.maximumTitleBytes else {
        throw ToolBoundaryError.invalid("title")
      }
    }
    if allowed.contains("body") {
      guard try arguments.requiredString("body").utf8.count <= ToolJSON.maximumStringBytes else {
        throw ToolBoundaryError.invalid("body")
      }
    }
  }

  func approval(for arguments: ToolJSON) throws -> ToolApproval {
    try validate(arguments: arguments)
    return switch try arguments.requiredString("action") {
    case "list", "read": ToolApproval.automaticReadOnly
    default: ToolApproval.requireAllowOnce
    }
  }

  func effect(for arguments: ToolJSON) throws -> String {
    try validate(arguments: arguments)
    return switch try arguments.requiredString("action") {
    case "list": "List local notes"
    case "read": "Read local note \(try noteID(arguments).uuidString)"
    case "create":
      // swiftlint:disable:next line_length
      "Create note titled ‘\(try arguments.requiredString("title"))’ with body ‘\(try arguments.requiredString("body"))’"
    case "update":
      // swiftlint:disable:next line_length
      "Update note \(try noteID(arguments).uuidString) at revision \(try arguments.requiredInt("expectedRevision")) to title ‘\(try arguments.requiredString("title"))’ and body ‘\(try arguments.requiredString("body"))’"
    case "delete":
      "Delete note \(try noteID(arguments).uuidString) at revision \(try arguments.requiredInt("expectedRevision"))"
    default: throw ToolBoundaryError.invalid("action")
    }
  }

  func execute(arguments: ToolJSON) async throws -> ToolJSON {
    try validate(arguments: arguments)
    switch try arguments.requiredString("action") {
    case "list": return .object(["notes": .array(try await store.list().map(Self.json))])
    case "read":
      return .object(["note": try await store.read(id: noteID(arguments)).map(Self.json) ?? .null])
    case "create":
      return try Self.json(
        try await store.create(
          title: arguments.requiredString("title"), body: arguments.requiredString("body")
        ))
    case "update":
      return try Self.json(
        try await store.update(
          id: noteID(arguments),
          expectedRevision: UInt64(try arguments.requiredInt("expectedRevision")),
          title: arguments.requiredString("title"),
          body: arguments.requiredString("body")
        ))
    case "delete":
      return try Self.json(
        try await store.delete(
          id: noteID(arguments),
          expectedRevision: UInt64(try arguments.requiredInt("expectedRevision"))
        ))
    default: throw ToolBoundaryError.invalid("action")
    }
  }

  private func noteID(_ arguments: ToolJSON) throws -> UUID {
    guard let id = UUID(uuidString: try arguments.requiredString("id")) else {
      throw ToolBoundaryError.invalid("id")
    }
    return id
  }

  private static func json(_ note: LocalNote) throws -> ToolJSON {
    guard let revision = Int(exactly: note.revision) else {
      throw NotesStoreError.revisionOverflow(id: note.id, current: note.revision)
    }
    return .object([
      "id": .string(note.id.uuidString),
      "revision": .int(revision),
      "title": .string(note.title),
      "body": .string(note.body),
      "createdAt": .string(ISO8601DateFormatter().string(from: note.createdAt)),
      "updatedAt": .string(ISO8601DateFormatter().string(from: note.updatedAt))
    ])
  }
}
