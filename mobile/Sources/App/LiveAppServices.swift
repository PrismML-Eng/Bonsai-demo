import Foundation
// Live adapters remain colocated so their shared session transaction is reviewable as one unit.
// swiftlint:disable file_length
#if os(iOS)
import UIKit
#endif

enum LiveUIServiceError: Error, LocalizedError {
  case missingManifest(ModelID)
  case modelNotInstalled
  case importRequiresPicker
  case emptyPersistedAnswer
  case visionUnsupportedByModel(displayName: String)

  var errorDescription: String? {
    switch self {
    case .missingManifest: "The bundled model manifest is unavailable."
    case .modelNotInstalled: "Install and verify this model before loading it."
    case .importRequiresPicker: "Choose Import from a platform file picker."
    case .emptyPersistedAnswer: "Generation ended before a complete answer could be persisted."
    case .visionUnsupportedByModel(let name):
      "\(name) does not support images. Remove the attachment or load a vision-capable model."
    }
  }
}

/// Serializes model replacement and chat generation so the runtime and conversation binding
/// are never observed at different installations.
actor ModelSessionGate {
  private struct Waiter {
    let id: UUID
    let continuation: CheckedContinuation<Void, any Error>
  }

  private var isHeld = false
  private var waiters: [Waiter] = []

  func acquire() async throws {
    try Task.checkCancellation()
    if !isHeld {
      isHeld = true
      return
    }
    let id = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
        if Task.isCancelled {
          continuation.resume(throwing: CancellationError())
        } else {
          waiters.append(.init(id: id, continuation: continuation))
        }
      }
    } onCancel: {
      Task { await self.cancelWaiter(id) }
    }
    do {
      try Task.checkCancellation()
    } catch {
      release()
      throw error
    }
  }

  func release() {
    if waiters.isEmpty {
      isHeld = false
    } else {
      waiters.removeFirst().continuation.resume()
    }
  }

  private func cancelWaiter(_ id: UUID) {
    guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
    waiters.remove(at: index).continuation.resume(throwing: CancellationError())
  }
}

actor LiveModelLibraryService: ModelLibraryServing {
  private let library: ModelLibrary
  private let engine: MLXInferenceEngine
  private let conversations: ConversationCoordinator
  private let manifests: [ModelID: ModelManifest]
  private let sessionGate: ModelSessionGate
  private let installationProvider: (@Sendable (ModelID) async -> ModelInstallation?)?
  private var loadedInstallation: ModelInstallation?

  init(root: URL, engine: MLXInferenceEngine, conversations: ConversationCoordinator,
       sessionGate: ModelSessionGate = ModelSessionGate(),
       manifests injectedManifests: [ModelID: ModelManifest]? = nil,
       installationProvider: (@Sendable (ModelID) async -> ModelInstallation?)? = nil) throws {
    library = try ModelLibrary(root: root)
    self.engine = engine
    self.conversations = conversations
    self.sessionGate = sessionGate
    self.installationProvider = installationProvider
    if let injectedManifests {
      manifests = injectedManifests
    } else if let url = Bundle.main.url(forResource: "manifest", withExtension: "json", subdirectory: "Models"),
       let catalog = try? JSONDecoder().decode(ModelCatalog.self, from: Data(contentsOf: url)) {
      manifests = Dictionary(uniqueKeysWithValues: catalog.models.map { ($0.id, $0.manifest) })
    } else { manifests = [:] }
  }

  func snapshots() async -> AsyncStream<ModelLibrarySnapshot> { await library.snapshots() }
  func currentLoadedModelID() async -> ModelID? { loadedInstallation?.modelID }

  // swiftlint:disable:next cyclomatic_complexity function_body_length
  func perform(_ intent: ModelLibraryIntent, for modelID: ModelID) async throws {
    guard let manifest = manifests[modelID] else { throw LiveUIServiceError.missingManifest(modelID) }
    switch intent {
    case .download, .retryDownload:
      let qualification = await qualification(for: modelID)
      try await library.install(manifest, qualification: qualification)
    case .verify:
      try await library.verify(manifest)
    case .importModel:
      throw LiveUIServiceError.importRequiresPicker
    case .load:
      let installation: ModelInstallation?
      if let installationProvider {
        installation = await installationProvider(modelID)
      } else if case .ready(let ready) = await library.state(for: modelID) {
        installation = ready
      } else {
        installation = nil
      }
      guard let installation else {
        throw LiveUIServiceError.modelNotInstalled
      }
      try await sessionGate.acquire()
      defer { Task { await sessionGate.release() } }
      try Task.checkCancellation()
      let previous = loadedInstallation
      do {
        try await engine.load(installation)
        try await conversations.bind(installation)
      } catch {
        await restore(previous)
        throw error
      }
      loadedInstallation = installation
    case .unload:
      try await sessionGate.acquire()
      defer { Task { await sessionGate.release() } }
      try Task.checkCancellation()
      await engine.unload()
      await conversations.unbind()
      loadedInstallation = nil
    case .delete:
      if loadedInstallation?.modelID == modelID {
        try await sessionGate.acquire()
        defer { Task { await sessionGate.release() } }
        try Task.checkCancellation()
        await engine.unload()
        await conversations.unbind()
        loadedInstallation = nil
      }
      try await library.delete(modelID)
    }
  }

  private func restore(_ installation: ModelInstallation?) async {
    guard let installation else {
      await engine.unload()
      await conversations.unbind()
      loadedInstallation = nil
      return
    }
    do {
      try await engine.load(installation)
      try await conversations.bind(installation)
      loadedInstallation = installation
    } catch {
      await engine.unload()
      await conversations.unbind()
      loadedInstallation = nil
    }
  }

  func importModel(_ modelID: ModelID, from source: URL) async throws {
    guard let manifest = manifests[modelID] else { throw LiveUIServiceError.missingManifest(modelID) }
    try await library.importModel(manifest, from: source, qualification: await qualification(for: modelID))
  }

  private func qualification(for modelID: ModelID) async -> DeviceQualification {
    #if os(iOS)
    let idiom = await MainActor.run { UIDevice.current.userInterfaceIdiom }
    if modelID == .ternary27B, idiom == .phone {
      return .unsupported(.ternaryProhibitedOnIPhone)
    }
    #endif
    return .qualified([.textGeneration, .thinking, .toolCalling, .vision])
  }
}
actor InteractiveApprovalGate: ToolApprovalGate {
  private var observers: [UUID: AsyncStream<ToolApprovalRequest>.Continuation] = [:]
  private var pending: [String: CheckedContinuation<ToolApprovalDecision, any Error>] = [:]

  func requests() -> AsyncStream<ToolApprovalRequest> {
    let id = UUID()
    return AsyncStream { continuation in
      observers[id] = continuation
      continuation.onTermination = { [weak self] _ in Task { await self?.removeObserver(id) } }
    }
  }

  func requestAllowOnce(_ request: ToolApprovalRequest) async throws -> ToolApprovalDecision {
    observers.values.forEach { $0.yield(request) }
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        pending[request.invocation.id] = continuation
      }
    } onCancel: { [weak self] in Task { await self?.cancel(id: request.invocation.id) } }
  }

  func resolve(id: String, decision: ToolApprovalDecision) {
    pending.removeValue(forKey: id)?.resume(returning: decision)
  }

  func cancelPending() {
    let continuations = pending.values
    pending.removeAll()
    continuations.forEach { $0.resume(throwing: CancellationError()) }
  }

  private func cancel(id: String) { pending.removeValue(forKey: id)?.resume(throwing: CancellationError()) }
  private func removeObserver(_ id: UUID) { observers.removeValue(forKey: id) }
}

// Persistence, event forwarding, image lifetime, and session-gate release form one transaction.
// swiftlint:disable:next type_body_length
actor AgentLoopChatService: ChatSessionServing {
  private struct PersistentGeneration {
    let conversation: Conversation
    let trimNotice: ContextTrimNotice?
    let request: GenerationRequest?
    let processedImages: [ProcessedImage]
  }

  private let loop: AgentLoop
  private let approvals: InteractiveApprovalGate
  private let engine: MLXInferenceEngine?
  private let conversations: ConversationCoordinator?
  private let sessionGate: ModelSessionGate?
  private let attachmentStore: ManagedAttachmentStore?
  private let attachmentRoot: URL?
  private let imagePreprocessor: ImagePreprocessor
  private let descriptors: [ModelID: ModelDescriptor]

  static func shouldPersist(_ completion: AgentCompletion) -> Bool {
    completion == .stop || completion == .length
  }

  init(loop: AgentLoop, approvals: InteractiveApprovalGate,
       engine: MLXInferenceEngine? = nil, conversations: ConversationCoordinator? = nil,
       sessionGate: ModelSessionGate? = nil,
       attachmentStore: ManagedAttachmentStore? = nil,
       attachmentRoot: URL? = nil,
       imagePreprocessor: ImagePreprocessor = .init(),
       descriptors: [ModelID: ModelDescriptor] = ModelCatalogLoader.bundledDescriptors()) {
    self.loop = loop
    self.approvals = approvals
    self.engine = engine
    self.conversations = conversations
    self.sessionGate = sessionGate
    self.attachmentStore = attachmentStore
    self.attachmentRoot = attachmentRoot
    self.imagePreprocessor = imagePreprocessor
    self.descriptors = descriptors
  }

  // This function owns the lifecycle boundary for forwarding, persistence, and completion.
  // swiftlint:disable:next cyclomatic_complexity function_body_length
  func stream(_ request: ChatSendRequest) async throws -> AsyncThrowingStream<ChatSessionEvent, any Error> {
    if let sessionGate {
      try await sessionGate.acquire()
      do {
        try Task.checkCancellation()
      } catch {
        await sessionGate.release()
        throw error
      }
    }
    let persistedAttachment = try request.attachment?.persistedReference()
    let userMessage = ConversationMessage(id: MessageID(UUID().uuidString), role: .user,
                                          content: request.prompt,
                                          attachments: persistedAttachment.map { [$0] } ?? [])
    let persistence: PersistentGeneration?
    do {
      persistence = try await persistentGeneration(userMessage: userMessage,
                                                    effort: request.effort)
    } catch {
      if let sessionGate { await sessionGate.release() }
      throw error
    }
    let generation: GenerationRequest
    if let prepared = persistence?.request {
      generation = prepared
    } else {
      generation = try GenerationRequest(prompt: request.prompt,
                                         reasoningBudget: request.effort.tokenBudget)
    }
    do {
      try Task.checkCancellation()
    } catch {
      if let sessionGate { await sessionGate.release() }
      throw error
    }
    let liveEvents = await loop.events()
    return AsyncThrowingStream { continuation in
      let task = Task { [loop] in
        defer { self.cleanProcessed(persistence?.processedImages ?? []) }
        defer { if let sessionGate = self.sessionGate { Task { await sessionGate.release() } } }
        do {
          try Task.checkCancellation()
        } catch {
          continuation.finish(throwing: error)
          return
        }
        let assistantID = UUID()
        continuation.yield(.assistantStarted(id: assistantID))
        if let notice = persistence?.trimNotice, notice.removedTurnCount > 0 {
          continuation.yield(.contextTrimmed(notice))
        }
        let forwardingTask = Task {
          var index = 0
          for await event in liveEvents {
            switch event {
            case .reasoning(let text): continuation.yield(.reasoning(text))
            case .answer(let text): continuation.yield(.answer(text))
            case .metrics(let metrics): continuation.yield(.metrics(metrics))
            case .toolRequest(let invocation):
              continuation.yield(.activity(.init(
                id: invocation.id,
                kind: .requested,
                title: "\(Self.toolTitle(invocation.name)) requested",
                detail: nil,
                actions: []
              )))
            case .activity(let activity):
              if let presentation = Self.presentation(activity, index: index) {
                continuation.yield(.activity(presentation))
              }
            case .completed: return
            }
            index += 1
          }
        }
        defer { forwardingTask.cancel() }
        do {
          let result = try await loop.run(generation)
          await forwardingTask.value
          if let conversation = persistence?.conversation {
            try await self.persist(result: result, userMessage: userMessage,
                                   conversation: conversation)
          }
          continuation.yield(.completed(result.completion))
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  func cancel() async { await loop.cancel() }

  func history() async throws -> [ChatMessagePresentation] {
    guard let conversation = try await conversations?.loadSelected() else { return [] }
    return conversation.completedTurns.flatMap { turn in
      turn.messages.compactMap { message in
        switch message.role {
        case .user: ChatMessagePresentation(id: UUID(), role: .user, text: message.content)
        case .assistant: ChatMessagePresentation(id: UUID(), role: .assistant, text: message.content)
        default: nil
        }
      }
    }
  }

  func respond(to action: ActivityAction) async {
    switch action {
    case .allowOnce(let id): await approvals.resolve(id: id, decision: .allowOnce)
    case .deny(let id): await approvals.resolve(id: id, decision: .deny)
    }
  }

  private static func toolTitle(_ name: String) -> String {
    switch name {
    case "local_notes": "Local notes"
    case "calculator": "Calculator"
    case "current_date_time": "Date and time"
    case "device_information": "Device information"
    default: name
    }
  }

  private func persistentGeneration(userMessage: ConversationMessage, effort: ReasoningEffort)
    async throws -> PersistentGeneration? {
    guard let conversations else { return nil }
    let selection = try await conversations.activeSelection()
    let conversation = try await conversations.loadSelected()
      ?? Conversation(id: selection.conversationID,
                      modelID: selection.installation.modelID,
                      modelRevision: selection.installation.revision,
                      revision: 0,
                      systemInstruction: .init(id: MessageID("system"), role: .system,
                                               content: "You are Bonsai, a private on-device assistant."),
                      completedTurns: [])
    if !userMessage.attachments.isEmpty {
      try Self.requireVisionSupport(modelID: selection.installation.modelID, descriptors: descriptors)
    }
    guard let engine else {
      return PersistentGeneration(
        conversation: conversation, trimNotice: nil, request: nil, processedImages: [])
    }
    let imageTrim = try ImageRequestBudget.live.trim(
      conversation, appending: [userMessage])
    let tools = await loop.toolSpecifications()
    let prepared = try await engine.preparedGeneration(
      for: imageTrim.conversation, appending: [userMessage],
      reasoningBudget: effort.tokenBudget, tools: tools)
    let processed = try await processedImages(for: prepared.trim.keptMessages)
    let combinedNotice = ContextTrimNotice(
      removedTurnCount: imageTrim.removedTurnCount + prepared.trim.notice.removedTurnCount,
      removedMessageCount: imageTrim.removedMessageCount + prepared.trim.notice.removedMessageCount)
    return PersistentGeneration(
      conversation: conversation,
      trimNotice: combinedNotice,
      request: prepared.request.replacingImages(processed.bindings),
      processedImages: processed.images)
  }

  private static func requireVisionSupport(
    modelID: ModelID, descriptors: [ModelID: ModelDescriptor]
  ) throws {
    guard let descriptor = descriptors[modelID], descriptor.supportsVisionInput else {
      let name = descriptors[modelID]?.displayName ?? modelID.rawValue
      throw LiveUIServiceError.visionUnsupportedByModel(displayName: name)
    }
  }

  private func processedImages(
    for messages: [ConversationMessage]
  ) async throws -> (bindings: [GenerationImage], images: [ProcessedImage]) {
    guard let attachmentStore else { return ([], []) }
    var bindings: [GenerationImage] = []
    var images: [ProcessedImage] = []
    do {
      for message in messages where message.role == .user {
        for attachment in message.attachments {
          let sourceData = try await attachmentStore.data(for: attachment)
          let processed = try await imagePreprocessor.process(
            data: sourceData, policy: attachment.detailPolicy)
          images.append(processed)
          bindings.append(.init(
            messageID: message.id, attachmentID: attachment.id, buffer: processed.buffer))
        }
      }
      return (bindings, images)
    } catch {
      cleanProcessed(images)
      throw error
    }
  }

  private nonisolated func cleanProcessed(_ images: [ProcessedImage]) {
    guard let attachmentRoot else { return }
    for image in images { try? imagePreprocessor.removeProcessed(image, managedRoot: attachmentRoot) }
  }

  private func persist(result: AgentRunResult, userMessage: ConversationMessage,
                       conversation: Conversation) async throws {
    guard let conversations, Self.shouldPersist(result.completion) else { return }
    guard !result.answer.isEmpty else { throw LiveUIServiceError.emptyPersistedAnswer }
    var messages = [userMessage]
    var knownInvocations: [String: ToolInvocation] = [:]
    for activity in result.activities {
      switch activity {
      case .pendingApproval(let request): knownInvocations[request.invocation.id] = request.invocation
      case .running(let invocation): knownInvocations[invocation.id] = invocation
      default: break
      }
    }
    for result in result.toolResults {
      guard let invocation = knownInvocations[result.invocationID] else { continue }
      messages.append(.init(id: MessageID(UUID().uuidString), role: .toolCall,
                            content: String(data: try JSONEncoder().encode(invocation), encoding: .utf8)!,
                            transactionID: invocation.id))
      messages.append(.init(id: MessageID(UUID().uuidString), role: .toolResult,
                            content: result.contentJSON, transactionID: invocation.id))
    }
    messages.append(.init(id: MessageID(UUID().uuidString), role: .assistant, content: result.answer))
    let updated = try Conversation(id: conversation.id, modelID: conversation.modelID,
                                   modelRevision: conversation.modelRevision,
                                   revision: conversation.revision + 1,
                                   systemInstruction: conversation.systemInstruction,
                                   completedTurns: conversation.completedTurns + [
                                    .init(id: UUID().uuidString, messages: messages,
                                          reasoningText: result.reasoning.isEmpty ? nil : result.reasoning)
                                   ])
    try await conversations.save(updated)
    try? await conversations.renameSelected(using: userMessage.content)
  }

  private static func presentation(_ activity: AgentActivity, index: Int) -> AgentActivityPresentation? {
    switch activity {
    case .generating:
      return .init(id: "generating-\(index)", kind: .requested, title: "Generating locally",
                   detail: nil, actions: [])
    case .pendingApproval(let request):
      return .pendingApproval(id: request.invocation.id,
                              toolName: toolTitle(request.invocation.name),
                              effect: request.effect, invocation: request.invocation)
    case .running(let invocation):
      return .init(id: invocation.id, kind: .running,
                   title: "Running \(toolTitle(invocation.name))",
                   detail: "On this device", actions: [])
    case .result(let result):
      let kind: AgentActivityKind = switch result.status {
      case .succeeded: .result
      case .denied: .denied
      case .failed: .failed
      }
      return .init(id: result.invocationID, kind: kind,
                   title: result.status == .succeeded ? "Tool finished" : "Tool \(result.status.rawValue)",
                   detail: result.contentJSON, actions: [])
    case .terminal(let completion):
      return .init(id: "terminal", kind: .terminal, title: "Agent finished",
                   detail: String(describing: completion), actions: [])
    }
  }
}
// swiftlint:enable file_length
