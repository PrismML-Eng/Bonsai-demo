import Foundation
import Observation

enum ConversationCoordinatorError: Error, Equatable, Sendable {
  case noLoadedModel
  case conversationNotAvailable(ConversationID)
}

struct ActiveConversationSelection: Equatable, Sendable {
  let installation: ModelInstallation
  let conversationID: ConversationID
}

struct ConversationListItem: Codable, Identifiable, Equatable, Sendable {
  let id: ConversationID
  let modelID: ModelID
  let modelRevision: String
  var title: String
}

struct ConversationNavigationSnapshot: Equatable, Sendable {
  let installation: ModelInstallation?
  let conversations: [ConversationListItem]
  let selectedID: ConversationID?
}

protocol ConversationCoordinating: Sendable {
  func activeSelection() async throws -> ActiveConversationSelection
  func loadSelected() async throws -> Conversation?
  func save(_ conversation: Conversation) async throws
}

protocol ConversationNavigationServing: Sendable {
  func snapshots() async -> AsyncStream<ConversationNavigationSnapshot>
  func createConversation() async throws
  func selectConversation(_ id: ConversationID) async throws
}

actor ConversationCoordinator: ConversationCoordinating, ConversationNavigationServing {
  private struct PersistedIndex: Codable, Sendable {
    var conversations: [ConversationListItem] = []
    var selectedByModel: [String: ConversationID] = [:]
  }

  private let store: ConversationStore
  private let indexStore: AtomicJSONStore
  private var index = PersistedIndex()
  private var didLoadIndex = false
  private var installation: ModelInstallation?
  private var observers: [UUID: AsyncStream<ConversationNavigationSnapshot>.Continuation] = [:]

  init(root: URL, store: ConversationStore) throws {
    self.store = store
    indexStore = try AtomicJSONStore(root: root.appending(path: "ConversationNavigation"))
  }

  func bind(_ installation: ModelInstallation) async throws {
    try await ensureIndexLoaded()
    self.installation = installation
    if selectedItem(for: installation) == nil {
      _ = try await createConversation(title: "New chat")
    } else {
      publish()
    }
  }

  func unbind() {
    installation = nil
    publish()
  }

  func activeSelection() throws -> ActiveConversationSelection {
    guard let installation,
          let item = selectedItem(for: installation) else {
      throw ConversationCoordinatorError.noLoadedModel
    }
    return ActiveConversationSelection(
      installation: installation,
      conversationID: item.id)
  }

  func loadSelected() async throws -> Conversation? {
    let selection = try activeSelection()
    return try await store.load(selection.conversationID, for: selection.installation.modelID)
  }

  func save(_ conversation: Conversation) async throws {
    let selection = try activeSelection()
    guard conversation.id == selection.conversationID,
          conversation.modelID == selection.installation.modelID,
          conversation.modelRevision == selection.installation.revision else {
      throw ConversationCoordinatorError.conversationNotAvailable(conversation.id)
    }
    try await store.save(conversation)
  }

  func snapshots() -> AsyncStream<ConversationNavigationSnapshot> {
    let observerID = UUID()
    return AsyncStream { continuation in
      observers[observerID] = continuation
      continuation.yield(snapshot())
      continuation.onTermination = { [weak self] _ in
        Task { await self?.removeObserver(observerID) }
      }
    }
  }

  func createConversation() async throws {
    try await ensureIndexLoaded()
    _ = try await createConversation(title: "New chat")
  }

  func selectConversation(_ id: ConversationID) async throws {
    try await ensureIndexLoaded()
    guard let installation,
          index.conversations.contains(where: {
            $0.id == id && $0.modelID == installation.modelID
              && $0.modelRevision == installation.revision
          }) else {
      throw ConversationCoordinatorError.conversationNotAvailable(id)
    }
    index.selectedByModel[selectionKey(for: installation)] = id
    try await persistIndex()
    publish()
  }

  func renameSelected(using firstPrompt: String) async throws {
    let selection = try activeSelection()
    guard let itemIndex = index.conversations.firstIndex(where: { $0.id == selection.conversationID }),
          index.conversations[itemIndex].title == "New chat" else { return }
    let normalized = firstPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    index.conversations[itemIndex].title = String(normalized.prefix(48))
    try await persistIndex()
    publish()
  }

  private func createConversation(title: String) async throws -> ConversationListItem {
    guard let installation else { throw ConversationCoordinatorError.noLoadedModel }
    let id = try ConversationID("chat-\(UUID().uuidString.lowercased())")
    let item = ConversationListItem(
      id: id,
      modelID: installation.modelID,
      modelRevision: installation.revision,
      title: title)
    index.conversations.append(item)
    index.selectedByModel[selectionKey(for: installation)] = id
    try await persistIndex()
    publish()
    return item
  }

  private func selectedItem(for installation: ModelInstallation) -> ConversationListItem? {
    guard let selectedID = index.selectedByModel[selectionKey(for: installation)] else { return nil }
    return index.conversations.first {
      $0.id == selectedID && $0.modelID == installation.modelID
        && $0.modelRevision == installation.revision
    }
  }

  private func selectionKey(for installation: ModelInstallation) -> String {
    "\(installation.modelID.rawValue)@\(installation.revision)"
  }

  private func snapshot() -> ConversationNavigationSnapshot {
    guard let installation else {
      return .init(installation: nil, conversations: [], selectedID: nil)
    }
    let items = index.conversations.filter {
      $0.modelID == installation.modelID && $0.modelRevision == installation.revision
    }
    return .init(
      installation: installation,
      conversations: items,
      selectedID: selectedItem(for: installation)?.id)
  }

  private func ensureIndexLoaded() async throws {
    guard !didLoadIndex else { return }
    if let data = try await indexStore.read(identifier: "index") {
      index = try JSONDecoder().decode(PersistedIndex.self, from: data)
    }
    didLoadIndex = true
  }

  private func persistIndex() async throws {
    let data = try await indexStore.encoded(index)
    try await indexStore.write(data, identifier: "index")
  }

  private func publish() {
    let value = snapshot()
    observers.values.forEach { $0.yield(value) }
  }

  private func removeObserver(_ id: UUID) {
    observers.removeValue(forKey: id)
  }
}

@MainActor @Observable
final class ConversationNavigationViewModel {
  private let service: any ConversationNavigationServing
  private(set) var conversations: [ConversationListItem]
  private(set) var selectedID: ConversationID?
  private(set) var errorMessage: String?
  private var observationTask: Task<Void, Never>?

  init(
    service: any ConversationNavigationServing,
    initial: ConversationNavigationSnapshot = .init(
      installation: nil, conversations: [], selectedID: nil)
  ) {
    self.service = service
    conversations = initial.conversations
    selectedID = initial.selectedID
  }

  func start() {
    guard observationTask == nil else { return }
    observationTask = Task { [weak self, service] in
      for await snapshot in await service.snapshots() {
        guard let self, !Task.isCancelled else { return }
        conversations = snapshot.conversations
        selectedID = snapshot.selectedID
      }
    }
  }

  func create() async {
    do {
      try await service.createConversation()
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func select(_ id: ConversationID) async {
    do {
      try await service.selectConversation(id)
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
