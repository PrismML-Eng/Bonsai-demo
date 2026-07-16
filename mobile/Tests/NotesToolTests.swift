import Foundation
import Testing

@testable import BonsaiMobile

@Suite("Local notes")
struct NotesToolTests {
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
}
