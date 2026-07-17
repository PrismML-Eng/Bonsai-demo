import Foundation

enum ApplicationDataClearError: Error, Equatable, Sendable {
  case unsupportedIntentSchema(Int)
}

/// Owns the durable, application-wide privacy-clear transaction.
///
/// Once the root intent is durable, failures and relaunches always roll forward.
/// Each participating store operation is idempotent, and the intent is removed
/// only after notes, conversation content/navigation, and attachments are clear.
actor ApplicationDataClearCoordinator {
  private struct ClearIntent: Codable, Sendable {
    static let currentSchemaVersion = 1
    let schemaVersion: Int
    let transactionID: UUID

    init(transactionID: UUID = UUID()) {
      schemaVersion = Self.currentSchemaVersion
      self.transactionID = transactionID
    }
  }

  private static let intentIdentifier = "intent"
  private let intentStore: AtomicJSONStore
  private let conversations: ConversationCoordinator
  private let notes: NotesStore
  private let attachments: ManagedAttachmentStore
  private var pendingAttachmentCommit: ManagedAttachmentStore.ClearTransaction?

  init(
    root: URL,
    conversations: ConversationCoordinator,
    notes: NotesStore,
    attachments: ManagedAttachmentStore
  ) throws {
    intentStore = try AtomicJSONStore(
      root: root.appending(path: "PrivateDataClear", directoryHint: .isDirectory))
    self.conversations = conversations
    self.notes = notes
    self.attachments = attachments
  }

  func clearAll() async throws {
    try await beginClearIntent()
    try await rollForward()
  }

  func recoverIfNeeded() async throws {
    guard try await readIntent() != nil else { return }
    try await rollForward()
  }

  func beginClearIntent() async throws {
    guard try await readIntent() == nil else { return }
    let data = try await intentStore.encoded(ClearIntent())
    try await intentStore.write(data, identifier: Self.intentIdentifier)
  }

  func hasPendingClearIntent() async throws -> Bool {
    try await readIntent() != nil
  }

  private func rollForward() async throws {
    try await notes.clearAll()
    try await conversations.clearAllConversations()
    try await clearAttachments()
    try await intentStore.delete(identifier: Self.intentIdentifier)
  }

  private func clearAttachments() async throws {
    if let pendingAttachmentCommit {
      try await attachments.commitClear(pendingAttachmentCommit)
      self.pendingAttachmentCommit = nil
      return
    }
    let transaction = try await attachments.prepareClear()
    pendingAttachmentCommit = transaction
    try await attachments.commitClear(transaction)
    pendingAttachmentCommit = nil
  }

  private func readIntent() async throws -> ClearIntent? {
    guard let data = try await intentStore.read(identifier: Self.intentIdentifier) else {
      return nil
    }
    let intent = try JSONDecoder().decode(ClearIntent.self, from: data)
    guard intent.schemaVersion == ClearIntent.currentSchemaVersion else {
      throw ApplicationDataClearError.unsupportedIntentSchema(intent.schemaVersion)
    }
    return intent
  }
}
