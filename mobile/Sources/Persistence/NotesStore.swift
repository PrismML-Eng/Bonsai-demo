import Foundation

struct LocalNote: Codable, Equatable, Sendable {
  let id: UUID
  let revision: UInt64
  let title: String
  let body: String
  let createdAt: Date
  let updatedAt: Date
}

enum NotesStoreError: Error, Equatable, Sendable {
  case missing(UUID)
  case staleRevision(current: UInt64, attempted: UInt64)
  case invalidTitle
  case invalidBody
  case noteLimitReached
  case corruptStore
  case revisionOverflow(id: UUID, current: UInt64)
}

actor NotesStore {
  private struct Archive: Codable, Sendable { var notes: [LocalNote] }
  static let maximumNotes = 1_000
  static let maximumTitleBytes = 256
  static let maximumBodyBytes = 32_768

  private let storage: AtomicJSONStore
  private let identifier = "notes"

  init(root: URL) throws {
    storage = try AtomicJSONStore(root: root.appending(path: "Notes"))
  }

  func list() async throws -> [LocalNote] {
    try await archive().notes.sorted { $0.updatedAt > $1.updatedAt }
  }

  func read(id: UUID) async throws -> LocalNote? {
    try await archive().notes.first { $0.id == id }
  }

  func create(title: String, body: String, now: Date = .now) async throws -> LocalNote {
    try Self.validate(title: title, body: body)
    let note = LocalNote(
      id: UUID(), revision: 1, title: title, body: body, createdAt: now, updatedAt: now
    )
    return try await transaction { data in
      var current = try Self.decodeArchive(data)
      guard current.notes.count < Self.maximumNotes else {
        throw NotesStoreError.noteLimitReached
      }
      current.notes.append(note)
      return (try Self.encode(current), note)
    }
  }

  func update(
    id: UUID,
    expectedRevision: UInt64,
    title: String,
    body: String,
    now: Date = .now
  ) async throws -> LocalNote {
    try Self.validate(title: title, body: body)
    return try await transaction { data in
      var current = try Self.decodeArchive(data)
      guard let index = current.notes.firstIndex(where: { $0.id == id }) else {
        throw NotesStoreError.missing(id)
      }
      let old = current.notes[index]
      guard old.revision == expectedRevision else {
        throw NotesStoreError.staleRevision(current: old.revision, attempted: expectedRevision)
      }
      let nextRevision = old.revision.addingReportingOverflow(1)
      guard !nextRevision.overflow else {
        throw NotesStoreError.revisionOverflow(id: id, current: old.revision)
      }
      let note = LocalNote(
        id: id, revision: nextRevision.partialValue, title: title, body: body,
        createdAt: old.createdAt, updatedAt: now)
      current.notes[index] = note
      return (try Self.encode(current), note)
    }
  }

  func delete(id: UUID, expectedRevision: UInt64) async throws -> LocalNote {
    return try await transaction { data in
      var current = try Self.decodeArchive(data)
      guard let index = current.notes.firstIndex(where: { $0.id == id }) else {
        throw NotesStoreError.missing(id)
      }
      let note = current.notes[index]
      guard note.revision == expectedRevision else {
        throw NotesStoreError.staleRevision(current: note.revision, attempted: expectedRevision)
      }
      current.notes.remove(at: index)
      return (try Self.encode(current), note)
    }
  }

  private func archive() async throws -> Archive {
    guard let data = try await storage.read(identifier: identifier) else {
      return Archive(notes: [])
    }
    do { return try Self.decodeArchive(data) } catch {
      try await storage.quarantine(identifier: identifier)
      throw NotesStoreError.corruptStore
    }
  }

  private func transaction<Result: Sendable>(
    _ transform: @Sendable (Data?) throws -> (data: Data, result: Result)
  ) async throws -> Result {
    do {
      return try await storage.transaction(identifier: identifier, transform)
    } catch NotesStoreError.corruptStore {
      try await storage.quarantine(identifier: identifier)
      throw NotesStoreError.corruptStore
    }
  }

  private static func decodeArchive(_ data: Data?) throws -> Archive {
    guard let data else { return Archive(notes: []) }
    do {
      let archive = try JSONDecoder().decode(Archive.self, from: data)
      try validate(archive)
      return archive
    } catch {
      throw NotesStoreError.corruptStore
    }
  }

  private static func encode(_ archive: Archive) throws -> Data {
    try validate(archive)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(archive)
  }

  private static func validate(title: String, body: String) throws {
    guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      title.utf8.count <= maximumTitleBytes
    else { throw NotesStoreError.invalidTitle }
    guard body.utf8.count <= maximumBodyBytes else { throw NotesStoreError.invalidBody }
  }

  private static func validate(_ archive: Archive) throws {
    guard archive.notes.count <= maximumNotes else { throw NotesStoreError.corruptStore }
    let zeroID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    var identifiers: Set<UUID> = []
    for note in archive.notes {
      guard note.id != zeroID, identifiers.insert(note.id).inserted, note.revision > 0,
        note.createdAt.timeIntervalSinceReferenceDate.isFinite,
        note.updatedAt.timeIntervalSinceReferenceDate.isFinite,
        note.createdAt <= note.updatedAt
      else { throw NotesStoreError.corruptStore }
      do {
        try validate(title: note.title, body: note.body)
      } catch {
        throw NotesStoreError.corruptStore
      }
    }
  }
}
