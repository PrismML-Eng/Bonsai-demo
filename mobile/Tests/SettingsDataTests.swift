import Foundation
import XCTest
@testable import BonsaiMobile

final class SettingsDataTests: XCTestCase {
  func testPersistedImageDetailIsSingleSourceAcrossProcessRecreation() {
    let suite = "BonsaiMobileTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let firstProcess = PersistedImageDetailSettings(defaults: defaults)
    XCTAssertEqual(firstProcess.value, .fast1024)
    firstProcess.set(.fullDetail)

    let relaunchedProcess = PersistedImageDetailSettings(defaults: UserDefaults(suiteName: suite)!)
    XCTAssertEqual(relaunchedProcess.value, .fullDetail)
  }

  func testConfirmedClearRemovesConversationsNotesAndImagesButNotModels() async throws {
    let root = FileManager.default.temporaryDirectory.appending(
      path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try ConversationStore(root: root)
    let conversations = try ConversationCoordinator(root: root, store: store)
    let installation = ModelInstallation(
      modelID: .oneBit27B, directory: root.appending(path: "Models/one-bit"),
      revision: String(repeating: "a", count: 40))
    try await conversations.bind(installation)
    let selection = try await conversations.activeSelection()
    let conversation = try Conversation(
      id: selection.conversationID, modelID: .oneBit27B,
      modelRevision: installation.revision, revision: 1,
      systemInstruction: .init(id: MessageID("system"), role: .system, content: "Local"),
      completedTurns: [.init(id: "turn", messages: [
        .init(id: MessageID("user"), role: .user, content: "private"),
        .init(id: MessageID("assistant"), role: .assistant, content: "answer")
      ])])
    try await conversations.save(conversation)
    let notes = try NotesStore(root: root)
    _ = try await notes.create(title: "Private", body: "Local note")
    let attachmentRoot = root.appending(path: "Attachments", directoryHint: .isDirectory)
    let attachments = try ManagedAttachmentStore(root: attachmentRoot)
    try Data("image bytes".utf8).write(to: attachmentRoot.appending(path: "draft.jpg"))
    let modelMarker = root.appending(path: "Models/model.marker")
    try FileManager.default.createDirectory(
      at: modelMarker.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data().write(to: modelMarker)

    try await LiveSettingsService(
      conversations: conversations, notes: notes, attachments: attachments
    ).clearConversationsNotesAndImages()

    let deletedConversation = try await store.load(selection.conversationID, for: .oneBit27B)
    let remainingNotes = try await notes.list()
    let replacementSelection = try await conversations.activeSelection()
    XCTAssertNil(deletedConversation)
    XCTAssertTrue(remainingNotes.isEmpty)
    XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: attachmentRoot.path).isEmpty)
    XCTAssertTrue(FileManager.default.fileExists(atPath: modelMarker.path))
    XCTAssertNotEqual(replacementSelection.conversationID, selection.conversationID)
  }

  func testClearFailureRollsBackNotesConversationsAndStagedAttachments() async throws {
    let root = FileManager.default.temporaryDirectory.appending(
      path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try ConversationStore(root: root)
    let conversations = try ConversationCoordinator(root: root, store: store)
    let installation = ModelInstallation(
      modelID: .oneBit27B, directory: root.appending(path: "Models/one-bit"),
      revision: String(repeating: "a", count: 40))
    try await conversations.bind(installation)
    let selection = try await conversations.activeSelection()
    let conversation = try Conversation(
      id: selection.conversationID, modelID: .oneBit27B,
      modelRevision: installation.revision, revision: 1,
      systemInstruction: .init(id: MessageID("system"), role: .system, content: "Local"),
      completedTurns: [.init(id: "turn", messages: [
        .init(id: MessageID("user"), role: .user, content: "private"),
        .init(id: MessageID("assistant"), role: .assistant, content: "answer")
      ])])
    try await conversations.save(conversation)
    let notes = try NotesStore(root: root)
    let note = try await notes.create(title: "Private", body: "Local note")
    let attachmentRoot = root.appending(path: "Attachments", directoryHint: .isDirectory)
    let attachments = try ManagedAttachmentStore(root: attachmentRoot)
    let attachmentLeaf = attachmentRoot.appending(path: "draft.jpg")
    try Data("private image".utf8).write(to: attachmentLeaf)
    let index = root.appending(path: "ConversationNavigation/index.json")
    let sentinel = root.appending(path: "sentinel")
    try Data("do not touch".utf8).write(to: sentinel)
    try FileManager.default.removeItem(at: index)
    try FileManager.default.createSymbolicLink(at: index, withDestinationURL: sentinel)

    do {
      try await LiveSettingsService(
        conversations: conversations, notes: notes, attachments: attachments
      ).clearConversationsNotesAndImages()
      XCTFail("Expected clear failure")
    } catch {}

    XCTAssertEqual(try await notes.read(id: note.id), note)
    XCTAssertEqual(try await store.load(selection.conversationID, for: .oneBit27B), conversation)
    XCTAssertTrue(FileManager.default.fileExists(atPath: attachmentLeaf.path))
    XCTAssertEqual(try Data(contentsOf: sentinel), Data("do not touch".utf8))
  }
}
