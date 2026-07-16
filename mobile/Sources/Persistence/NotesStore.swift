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
    var current = try await archive()
    guard current.notes.count < Self.maximumNotes else { throw NotesStoreError.noteLimitReached }
    let note = LocalNote(
      id: UUID(), revision: 1, title: title, body: body, createdAt: now, updatedAt: now
    )
    current.notes.append(note)
    try Task.checkCancellation()
    try await save(current)
    return note
  }

  func update(
    id: UUID,
    expectedRevision: UInt64,
    title: String,
    body: String,
    now: Date = .now
  ) async throws -> LocalNote {
    try Self.validate(title: title, body: body)
    var current = try await archive()
    guard let index = current.notes.firstIndex(where: { $0.id == id }) else {
      throw NotesStoreError.missing(id)
    }
    let old = current.notes[index]
    guard old.revision == expectedRevision else {
      throw NotesStoreError.staleRevision(current: old.revision, attempted: expectedRevision)
    }
    let note = LocalNote(
      id: id,
      revision: old.revision + 1,
      title: title,
      body: body,
      createdAt: old.createdAt,
      updatedAt: now
    )
    current.notes[index] = note
    try Task.checkCancellation()
    try await save(current)
    return note
  }

  func delete(id: UUID, expectedRevision: UInt64) async throws -> LocalNote {
    var current = try await archive()
    guard let index = current.notes.firstIndex(where: { $0.id == id }) else {
      throw NotesStoreError.missing(id)
    }
    let note = current.notes[index]
    guard note.revision == expectedRevision else {
      throw NotesStoreError.staleRevision(current: note.revision, attempted: expectedRevision)
    }
    current.notes.remove(at: index)
    try Task.checkCancellation()
    try await save(current)
    return note
  }

  private func archive() async throws -> Archive {
    guard let data = try await storage.read(identifier: identifier) else {
      return Archive(notes: [])
    }
    do { return try JSONDecoder().decode(Archive.self, from: data) } catch {
      try await storage.quarantine(identifier: identifier)
      throw NotesStoreError.corruptStore
    }
  }

  private func save(_ archive: Archive) async throws {
    let data = try await storage.encoded(archive)
    try await storage.write(data, identifier: identifier)
  }

  private static func validate(title: String, body: String) throws {
    guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      title.utf8.count <= maximumTitleBytes
    else { throw NotesStoreError.invalidTitle }
    guard body.utf8.count <= maximumBodyBytes else { throw NotesStoreError.invalidBody }
  }
}
