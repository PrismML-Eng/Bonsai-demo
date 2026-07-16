import Foundation
import Testing

@testable import BonsaiMobile

@Suite("Local notes")
struct NotesToolTests {
  @Test func semanticallyInvalidArchivesAreQuarantinedAcrossStoreInstances() async throws {
    let id = UUID()
    let valid = LocalNote(
      id: id, revision: 1, title: "valid", body: "body",
      createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 2))
    let invalidArchives: [[LocalNote]] = [
      [valid, valid],
      [LocalNote(
        id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
        revision: 1, title: "valid", body: "body",
        createdAt: valid.createdAt, updatedAt: valid.updatedAt)],
      [LocalNote(
        id: UUID(), revision: 0, title: "valid", body: "body",
        createdAt: valid.createdAt, updatedAt: valid.updatedAt)],
      [LocalNote(
        id: UUID(), revision: 1, title: " ", body: "body",
        createdAt: valid.createdAt, updatedAt: valid.updatedAt)],
      [LocalNote(
        id: UUID(), revision: 1, title: String(repeating: "t", count: 257), body: "body",
        createdAt: valid.createdAt, updatedAt: valid.updatedAt)],
      [LocalNote(
        id: UUID(), revision: 1, title: "valid",
        body: String(repeating: "b", count: NotesStore.maximumBodyBytes + 1),
        createdAt: valid.createdAt, updatedAt: valid.updatedAt)],
      [LocalNote(
        id: UUID(), revision: 1, title: "valid", body: "body",
        createdAt: valid.updatedAt, updatedAt: valid.createdAt)],
      (0...NotesStore.maximumNotes).map { index in
        LocalNote(
          id: UUID(), revision: 1, title: "note-\(index)", body: "body",
          createdAt: valid.createdAt, updatedAt: valid.updatedAt)
      }
    ]

    for notes in invalidArchives {
      let root = temporaryDirectory(prefix: "CorruptNotes")
      try await writeArchive(notes, root: root)
      let first = try NotesStore(root: root)
      await #expect(throws: NotesStoreError.corruptStore) { try await first.list() }
      let reloaded = try NotesStore(root: root)
      #expect(try await reloaded.list().isEmpty)
    }
  }

  @Test func mutationQuarantinesSemanticallyInvalidArchive() async throws {
    let root = temporaryDirectory(prefix: "MutationCorruptNotes")
    let note = LocalNote(
      id: UUID(), revision: 1, title: "duplicate", body: "body",
      createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 2))
    try await writeArchive([note, note], root: root)
    let writer = try NotesStore(root: root)

    await #expect(throws: NotesStoreError.corruptStore) {
      try await writer.create(title: "new", body: "body")
    }
    let reader = try NotesStore(root: root)
    #expect(try await reader.list().isEmpty)
  }

  @Test func maximumRevisionReturnsTypedOverflowAcrossStoreInstances() async throws {
    let root = temporaryDirectory(prefix: "OverflowNotes")
    let note = LocalNote(
      id: UUID(), revision: .max, title: "maximum", body: "body",
      createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 2))
    try await writeArchive([note], root: root)
    let writer = try NotesStore(root: root)

    await #expect(throws: NotesStoreError.revisionOverflow(id: note.id, current: .max)) {
      try await writer.update(
        id: note.id, expectedRevision: .max, title: "next", body: "body",
        now: Date(timeIntervalSince1970: 3))
    }
    let reader = try NotesStore(root: root)
    #expect(try await reader.read(id: note.id)?.revision == .max)
  }

  @Test func maximumRevisionCannotTrapDuringToolSerialization() async throws {
    let root = temporaryDirectory(prefix: "OverflowToolNotes")
    let note = LocalNote(
      id: UUID(), revision: .max, title: "maximum", body: "body",
      createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 2))
    try await writeArchive([note], root: root)
    let tool = NotesTool(store: try NotesStore(root: root))
    let arguments = try ToolJSON.decode(
      "{\"action\":\"read\",\"id\":\"\(note.id.uuidString)\"}")

    await #expect(throws: NotesStoreError.revisionOverflow(id: note.id, current: .max)) {
      try await tool.execute(arguments: arguments)
    }
  }

  @Test func persistsCRUDAndRejectsStaleRevision() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "NotesToolTests-\(UUID())")
    let store = try NotesStore(root: root)
    let created = try await store.create(
      title: "Shopping", body: "Tea", now: .init(timeIntervalSince1970: 1))
    let reloaded = try NotesStore(root: root)
    #expect(try await reloaded.read(id: created.id)?.body == "Tea")
    let updated = try await reloaded.update(
      id: created.id, expectedRevision: 1, title: "Shopping", body: "Tea and rice",
      now: .init(timeIntervalSince1970: 2))
    #expect(updated.revision == 2)
    await #expect(throws: NotesStoreError.staleRevision(current: 2, attempted: 1)) {
      try await reloaded.update(
        id: created.id, expectedRevision: 1, title: "x", body: "y", now: .now)
    }
  }

  @Test func writeActionsRequireFreshApprovalAndDenialDoesNotMutate() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "NotesToolApproval-\(UUID())")
    let store = try NotesStore(root: root)
    let tool = NotesTool(store: store)
    let arguments = try ToolJSON.decode(
      "{\"action\":\"create\",\"title\":\"Private\",\"body\":\"Local\"}")
    #expect(try tool.approval(for: arguments) == .requireAllowOnce)
    #expect(try tool.effect(for: arguments) == "Create note titled ‘Private’ with body ‘Local’")
    #expect(try await store.list().isEmpty)
  }

  @Test func concurrentStoresAllowOnlyOneWriterForARevision() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "NotesRace-\(UUID())")
    let first = try NotesStore(root: root)
    let second = try NotesStore(root: root)
    let note = try await first.create(title: "v1", body: "body")

    let outcomes = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
      for (store, title) in [(first, "v2-a"), (second, "v2-b")] {
        group.addTask {
          do {
            _ = try await store.update(
              id: note.id, expectedRevision: 1, title: title, body: "body")
            return true
          } catch { return false }
        }
      }
      var values: [Bool] = []
      for await value in group { values.append(value) }
      return values
    }
    #expect(outcomes.filter { $0 }.count == 1)
    #expect(try await first.read(id: note.id)?.revision == 2)
  }

  private func temporaryDirectory(prefix: String) -> URL {
    FileManager.default.temporaryDirectory.appending(path: "\(prefix)-\(UUID())")
  }

  private func writeArchive(_ notes: [LocalNote], root: URL) async throws {
    struct Archive: Encodable { let notes: [LocalNote] }
    let storage = try AtomicJSONStore(root: root.appending(path: "Notes"))
    try await storage.write(try JSONEncoder().encode(Archive(notes: notes)), identifier: "notes")
  }
}
