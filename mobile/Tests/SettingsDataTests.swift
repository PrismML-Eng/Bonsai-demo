import Foundation
import XCTest
@testable import BonsaiMobile

final class SettingsDataTests: XCTestCase {
  func testDurableApplicationClearRollsForwardAfterEveryCrossStoreCrashBoundary() async throws {
    for boundary in ClearCrashBoundary.allCases {
      let root = FileManager.default.temporaryDirectory.appending(
        path: UUID().uuidString, directoryHint: .isDirectory)
      defer { try? FileManager.default.removeItem(at: root) }
      let seed = try await simulateClearCrash(at: boundary, root: root)

      let relaunchedStore = try ConversationStore(root: root)
      let relaunchedConversations = try ConversationCoordinator(root: root, store: relaunchedStore)
      let relaunchedNotes = try NotesStore(root: root)
      let relaunchedAttachments = try ManagedAttachmentStore(
        root: root.appending(path: "Attachments", directoryHint: .isDirectory))
      let relaunched = try ApplicationDataClearCoordinator(
        root: root, conversations: relaunchedConversations,
        notes: relaunchedNotes, attachments: relaunchedAttachments)
      let service = try LiveSettingsService(
        root: root, conversations: relaunchedConversations,
        notes: relaunchedNotes, attachments: relaunchedAttachments)

      try await service.recoverPendingClear()
      try await assertCoherentClearedRelaunch(
        seed: seed, conversations: relaunchedConversations,
        store: relaunchedStore, notes: relaunchedNotes, boundary: boundary)
      let hasPendingIntent = try await relaunched.hasPendingClearIntent()
      XCTAssertFalse(
        hasPendingIntent,
        "\(boundary) must remove the root intent only after every store is clear")
    }
  }

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
      root: root, conversations: conversations, notes: notes, attachments: attachments
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

  func testClearFailureRetainsIntentAndRetryRollsForwardWithoutTouchingSymlinkTarget() async throws {
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
    let (index, sentinel) = try replaceNavigationIndexWithSymlink(root: root)

    let service = try LiveSettingsService(
      root: root, conversations: conversations, notes: notes, attachments: attachments)
    do {
      try await service.clearConversationsNotesAndImages()
      XCTFail("Expected clear failure")
    } catch {}

    let savedNote = try await notes.read(id: note.id)
    XCTAssertNil(savedNote)
    let savedConversation = try await store.load(selection.conversationID, for: .oneBit27B)
    XCTAssertEqual(savedConversation, conversation)
    XCTAssertTrue(FileManager.default.fileExists(atPath: attachmentLeaf.path))
    XCTAssertEqual(try Data(contentsOf: sentinel), Data("do not touch".utf8))
    XCTAssertTrue(FileManager.default.fileExists(
      atPath: root.appending(path: "PrivateDataClear/intent.json").path))

    try FileManager.default.removeItem(at: index)
    try await service.clearConversationsNotesAndImages()

    let clearedConversation = try await store.load(selection.conversationID, for: .oneBit27B)
    XCTAssertNil(clearedConversation)
    XCTAssertFalse(FileManager.default.fileExists(atPath: attachmentLeaf.path))
    XCTAssertEqual(try Data(contentsOf: sentinel), Data("do not touch".utf8))
    XCTAssertFalse(FileManager.default.fileExists(
      atPath: root.appending(path: "PrivateDataClear/intent.json").path))
  }

  func testSameProcessRetryResumesCommittedAttachmentPurge() async throws {
    let root = FileManager.default.temporaryDirectory.appending(
      path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let conversations = try ConversationCoordinator(
      root: root, store: ConversationStore(root: root))
    let notes = try NotesStore(root: root)
    let attachmentRoot = root.appending(path: "Attachments", directoryHint: .isDirectory)
    let attachments = try ManagedAttachmentStore(
      root: attachmentRoot, faultInjector: AttachmentStoreFaultInjector([.purgeUnlink]))
    try Data("private".utf8).write(to: attachmentRoot.appending(path: "draft.jpg"))
    let service = try LiveSettingsService(
      root: root, conversations: conversations, notes: notes, attachments: attachments)

    do {
      try await service.clearConversationsNotesAndImages()
      XCTFail("Expected injected purge failure")
    } catch {}
    XCTAssertTrue(FileManager.default.fileExists(
      atPath: attachmentRoot.appending(path: ".clear-journal").path))

    try await service.clearConversationsNotesAndImages()

    XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: attachmentRoot.path).isEmpty)
    XCTAssertFalse(FileManager.default.fileExists(
      atPath: root.appending(path: "PrivateDataClear/intent.json").path))
  }
}

private extension SettingsDataTests {
  enum ClearCrashBoundary: String, CaseIterable {
    case durableIntent
    case notesCleared
    case conversationsAndIndexCleared
    case attachmentsPrepared
    case attachmentsCommitted
  }

  struct ClearSeed {
    let installation: ModelInstallation
    let conversationID: ConversationID
    let noteID: UUID
    let attachmentURL: URL
    let intentURL: URL
  }

  func simulateClearCrash(at boundary: ClearCrashBoundary, root: URL) async throws -> ClearSeed {
    let store = try ConversationStore(root: root)
    let conversations = try ConversationCoordinator(root: root, store: store)
    let installation = ModelInstallation(
      modelID: .oneBit27B, directory: root.appending(path: "Models/one-bit"),
      revision: String(repeating: "c", count: 40))
    try await conversations.bind(installation)
    let selection = try await conversations.activeSelection()
    try await conversations.save(try populatedConversation(selection: selection))
    let notes = try NotesStore(root: root)
    let note = try await notes.create(title: "Crash private", body: "Must stay deleted")
    let attachmentRoot = root.appending(path: "Attachments", directoryHint: .isDirectory)
    let attachments = try ManagedAttachmentStore(root: attachmentRoot)
    let attachmentURL = attachmentRoot.appending(path: "crash-private.jpg")
    try Data("private image bytes".utf8).write(to: attachmentURL)
    let coordinator = try ApplicationDataClearCoordinator(
      root: root, conversations: conversations, notes: notes, attachments: attachments)
    try await coordinator.beginClearIntent()

    if boundary != .durableIntent { try await notes.clearAll() }
    if [.conversationsAndIndexCleared, .attachmentsPrepared, .attachmentsCommitted].contains(boundary) {
      try await conversations.clearAllConversations()
    }
    if boundary == .attachmentsPrepared {
      _ = try await attachments.prepareClear()
    } else if boundary == .attachmentsCommitted {
      let transaction = try await attachments.prepareClear()
      try await attachments.commitClear(transaction)
    }
    return .init(
      installation: installation, conversationID: selection.conversationID,
      noteID: note.id, attachmentURL: attachmentURL,
      intentURL: root.appending(path: "PrivateDataClear/intent.json"))
  }

  func populatedConversation(selection: ActiveConversationSelection) throws -> Conversation {
    try Conversation(
      id: selection.conversationID, modelID: selection.installation.modelID,
      modelRevision: selection.installation.revision, revision: 1,
      systemInstruction: .init(id: MessageID("system"), role: .system, content: "Local"),
      completedTurns: [.init(id: "clear-crash-turn", messages: [
        .init(id: MessageID("user"), role: .user, content: "private"),
        .init(id: MessageID("assistant"), role: .assistant, content: "answer")
      ])])
  }

  func assertCoherentClearedRelaunch(
    seed: ClearSeed,
    conversations: ConversationCoordinator,
    store: ConversationStore,
    notes: NotesStore,
    boundary: ClearCrashBoundary
  ) async throws {
    let deletedConversation = try await store.load(seed.conversationID, for: .oneBit27B)
    let deletedNote = try await notes.read(id: seed.noteID)
    XCTAssertNil(deletedConversation, "\(boundary)")
    XCTAssertNil(deletedNote, "\(boundary)")
    XCTAssertFalse(FileManager.default.fileExists(atPath: seed.attachmentURL.path), "\(boundary)")
    try await conversations.bind(seed.installation)
    let snapshots = await conversations.snapshots()
    var iterator = snapshots.makeAsyncIterator()
    let nextNavigation = await iterator.next()
    let navigation = try XCTUnwrap(nextNavigation, "\(boundary)")
    XCTAssertEqual(navigation.conversations.count, 1, "\(boundary)")
    XCTAssertEqual(navigation.selectedID, navigation.conversations.first?.id, "\(boundary)")
    XCTAssertNotEqual(navigation.selectedID, seed.conversationID, "\(boundary)")
    XCTAssertFalse(FileManager.default.fileExists(atPath: seed.intentURL.path), "\(boundary)")
  }

  func replaceNavigationIndexWithSymlink(root: URL) throws -> (index: URL, sentinel: URL) {
    let index = root.appending(path: "ConversationNavigation/index.json")
    let sentinel = root.appending(path: "sentinel")
    try Data("do not touch".utf8).write(to: sentinel)
    try FileManager.default.removeItem(at: index)
    try FileManager.default.createSymbolicLink(at: index, withDestinationURL: sentinel)
    return (index, sentinel)
  }
}
