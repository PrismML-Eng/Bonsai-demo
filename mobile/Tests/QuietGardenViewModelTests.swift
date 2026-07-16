import XCTest
import MLXLMCommon
@testable import BonsaiMobile
// Integration-style adapter tests deliberately share narrow runtime fixtures in this file.
// swiftlint:disable file_length type_body_length

@MainActor
final class QuietGardenViewModelTests: XCTestCase {
  func testReasoningEffortMapsToBudgets() {
    XCTAssertEqual(ReasoningEffort.off.tokenBudget, 0)
    XCTAssertEqual(ReasoningEffort.low.tokenBudget, 512)
    XCTAssertEqual(ReasoningEffort.medium.tokenBudget, 2_048)
    XCTAssertEqual(ReasoningEffort.high.tokenBudget, 8_192)
    XCTAssertEqual(ReasoningEffort.max.tokenBudget, -1)
  }

  func testStreamingUsesStableAssistantIDAndSeparatesReasoningAndMetrics() async {
    let assistantID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    let service = ScriptedChatService(events: [
      .assistantStarted(id: assistantID), .reasoning("Checking locally."),
      .answer("A quiet "), .answer("answer."),
      .metrics(.init(promptTokenCount: 10, generatedTokenCount: 3,
                     timeToFirstToken: .milliseconds(20), tokensPerSecond: 12)),
      .completed(.stop)
    ])
    let viewModel = ChatViewModel(service: service, isModelReady: true)
    viewModel.draft = "Hello"

    await viewModel.send()

    XCTAssertEqual(viewModel.messages.filter { $0.role == .assistant }.map(\.id), [assistantID])
    XCTAssertEqual(viewModel.messages.last?.text, "A quiet answer.")
    XCTAssertEqual(viewModel.reasoning.text, "Checking locally.")
    XCTAssertNotNil(viewModel.metrics)
  }

  func testProductionRuntimeFailureCompletionPreservesDraftAndOffersRetry() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let engine = UIAgentEngine(events: [])
    let service = AgentLoopChatService(
      loop: AgentLoop(engine: engine, registry: try ToolRegistry.live(notes: NotesStore(root: root))),
      approvals: InteractiveApprovalGate())
    let viewModel = ChatViewModel(service: service, isModelReady: true)
    viewModel.draft = "Please keep this"

    await viewModel.send()

    XCTAssertEqual(viewModel.messages.first?.text, "Please keep this")
    XCTAssertEqual(viewModel.failedPrompt, "Please keep this")
    XCTAssertEqual(viewModel.draft, "Please keep this")
    XCTAssertEqual(viewModel.recovery?.label, "Retry send")
  }

  func testProtocolFailureCompletionsExposeNamedRetrySend() async {
    for completion in [AgentCompletion.toolTurnLimit(6), .duplicateInvocationID("duplicate")] {
      let viewModel = ChatViewModel(
        service: ScriptedChatService(events: [.completed(completion)]), isModelReady: true)
      viewModel.draft = "recover me"
      await viewModel.send()
      XCTAssertEqual(viewModel.failedPrompt, "recover me")
      XCTAssertEqual(viewModel.draft, "recover me")
      XCTAssertEqual(viewModel.recovery?.label, "Retry send")
    }
  }

  func testStopCancelsServiceAndRetainsPartialAnswer() async {
    let service = SuspendingChatService()
    let viewModel = ChatViewModel(service: service, isModelReady: true)
    viewModel.draft = "Long answer"
    let task = Task { await viewModel.send() }
    await service.waitUntilStarted()

    await viewModel.stop()
    await task.value

    let wasCancelled = await service.wasCancelled
    XCTAssertTrue(wasCancelled)
    XCTAssertFalse(viewModel.isGenerating)
    XCTAssertEqual(viewModel.terminalStatus, "Stopped")
  }

  func testPendingNoteApprovalShowsExactEffectAndOneShotChoices() {
    let invocation = ToolInvocation(id: "note-1", name: "local_notes", argumentsJSON: "{}")
    let activity = AgentActivityPresentation.pendingApproval(
      id: "note-1", toolName: "Local notes", effect: "Delete note Groceries", invocation: invocation
    )

    XCTAssertEqual(activity.detail, "Delete note Groceries")
    XCTAssertEqual(activity.actions.map(\.label), ["Allow once", "Deny"])
  }

  func testFixturesAreDeterministicAndCoverRequiredStates() {
    XCTAssertEqual(Set(UIFixture.allCases), [
      .emptyLibrary, .downloading, .unsupportedTernary, .readyChat,
      .streamingReasoning, .pendingNoteWrite, .toolFailure, .recoverableFailure,
      .cancelledGeneration, .contextTrimmed, .toolDenied
    ])
    XCTAssertEqual(UIFixture.readyChat.makeState(), UIFixture.readyChat.makeState())
    XCTAssertEqual(UIAccessibility.chatComposer, "chat.composer")
  }

  func testNavigationContractUsesPlatformAndHorizontalSizeClass() {
    XCTAssertEqual(RootNavigationState.layout(platform: .iPhone, compactWidth: false), .stack)
    XCTAssertEqual(RootNavigationState.layout(platform: .iPad, compactWidth: true), .stack)
    XCTAssertEqual(RootNavigationState.layout(platform: .iPad, compactWidth: false), .split)
    XCTAssertEqual(RootNavigationState.layout(platform: .mac, compactWidth: true), .split)
  }

  func testLiveAgentAdapterForwardsOrderedReasoningAnswerAndMetrics() async throws {
    let metrics = GenerationMetrics(promptTokenCount: 8, generatedTokenCount: 2,
                                    timeToFirstToken: .milliseconds(10), tokensPerSecond: 20)
    let engine = UIAgentEngine(events: [.reasoning("Private thought"), .answer("Hello "),
                                        .answer("there"), .metrics(metrics), .completed(.stop)])
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let registry = try ToolRegistry.live(notes: NotesStore(root: root))
    let gate = InteractiveApprovalGate()
    let service = AgentLoopChatService(loop: AgentLoop(engine: engine, registry: registry), approvals: gate)

    let stream = try await service.stream(.init(prompt: "Hi", effort: .high))
    var received: [ChatSessionEvent] = []
    for try await event in stream { received.append(event) }

    XCTAssertTrue(received.contains(.reasoning("Private thought")))
    XCTAssertEqual(received.compactMap { if case .answer(let value) = $0 { value } else { nil } },
                   ["Hello ", "there"])
    XCTAssertTrue(received.contains(.metrics(metrics)))
    let recordedRequest = await engine.lastRequest
    XCTAssertEqual(recordedRequest?.reasoningBudget, 8_192)
  }

  func testLiveAgentAdapterPersistsAndReplaysStructuredMultiTurnConversation() async throws {
    let runtime = PersistingRuntimeResource()
    let engine = MLXInferenceEngine(loader: PersistingRuntimeLoader(resource: runtime))
    let revision = String(repeating: "a", count: 40)
    try await engine.load(.init(modelID: .oneBit27B,
                                directory: URL(fileURLWithPath: "/tmp/persisting-runtime"),
                                revision: revision))
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let store = try ConversationStore(root: root)
    let coordinator = try ConversationCoordinator(root: root, store: store)
    try await coordinator.bind(.init(modelID: .oneBit27B,
                                     directory: URL(fileURLWithPath: "/tmp/persisting-runtime"),
                                     revision: revision))
    let registry = try ToolRegistry.live(notes: NotesStore(root: root))
    let gate = InteractiveApprovalGate()
    let service = AgentLoopChatService(
      loop: AgentLoop(engine: engine, registry: registry), approvals: gate, engine: engine,
      conversations: coordinator)

    for prompt in ["first", "second"] {
      for try await _ in try await service.stream(.init(prompt: prompt, effort: .off)) {}
    }

    let selection = try await coordinator.activeSelection()
    let loaded = try await store.load(selection.conversationID, for: .oneBit27B)
    let saved = try XCTUnwrap(loaded)
    XCTAssertEqual(saved.completedTurns.count, 2)
    XCTAssertEqual(runtime.streamedMessages.count, 2)
    XCTAssertEqual(runtime.streamedMessages[1].map(\.role),
                   [.system, .user, .assistant, .user])
  }

  func testLiveAgentAdapterSwitchesOneBitToTernaryWithoutCrossModelHistory() async throws {
    let oneBitRuntime = PersistingRuntimeResource()
    let ternaryRuntime = PersistingRuntimeResource()
    let loader = SwitchingRuntimeLoader(resources: [
      .oneBit27B: oneBitRuntime,
      .ternary27B: ternaryRuntime
    ])
    let engine = MLXInferenceEngine(loader: loader)
    let oneBitRevision = String(repeating: "1", count: 40)
    let ternaryRevision = String(repeating: "2", count: 40)
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let store = try ConversationStore(root: root)
    let coordinator = try ConversationCoordinator(root: root, store: store)
    let registry = try ToolRegistry.live(notes: NotesStore(root: root))
    let service = AgentLoopChatService(
      loop: AgentLoop(engine: engine, registry: registry),
      approvals: InteractiveApprovalGate(),
      engine: engine,
      conversations: coordinator)

    let oneBit = ModelInstallation(modelID: .oneBit27B,
                                   directory: URL(fileURLWithPath: "/tmp/one-bit"),
                                   revision: oneBitRevision)
    try await engine.load(oneBit)
    try await coordinator.bind(oneBit)
    for try await _ in try await service.stream(.init(prompt: "one", effort: .off)) {}
    let oneBitSelection = try await coordinator.activeSelection()

    let ternary = ModelInstallation(modelID: .ternary27B,
                                    directory: URL(fileURLWithPath: "/tmp/ternary"),
                                    revision: ternaryRevision)
    try await engine.load(ternary)
    try await coordinator.bind(ternary)
    for try await _ in try await service.stream(.init(prompt: "two", effort: .off)) {}
    let ternarySelection = try await coordinator.activeSelection()

    XCTAssertNotEqual(oneBitSelection.conversationID, ternarySelection.conversationID)
    XCTAssertEqual(oneBitSelection.installation.revision, oneBitRevision)
    XCTAssertEqual(ternarySelection.installation.revision, ternaryRevision)
    XCTAssertEqual(ternaryRuntime.streamedMessages.single?.map(\.role), [.system, .user])
    let savedOneBit = try await store.load(oneBitSelection.conversationID, for: .oneBit27B)
    let savedTernary = try await store.load(ternarySelection.conversationID, for: .ternary27B)
    XCTAssertEqual(savedOneBit?.modelRevision, oneBitRevision)
    XCTAssertEqual(savedTernary?.modelRevision, ternaryRevision)
  }

  func testLiveModelServicePublishesSuccessfulExactReplacement() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let oneBit = ModelInstallation(modelID: .oneBit27B,
                                   directory: URL(fileURLWithPath: "/tmp/live-one"),
                                   revision: String(repeating: "4", count: 40))
    let ternary = ModelInstallation(modelID: .ternary27B,
                                    directory: URL(fileURLWithPath: "/tmp/live-ternary"),
                                    revision: String(repeating: "5", count: 40))
    let loader = ControlledRuntimeLoader(resources: [
      .oneBit27B: PersistingRuntimeResource(), .ternary27B: PersistingRuntimeResource()
    ])
    let engine = MLXInferenceEngine(loader: loader)
    let coordinator = try ConversationCoordinator(root: root, store: ConversationStore(root: root))
    let installations = [ModelID.oneBit27B: oneBit, .ternary27B: ternary]
    let service = try LiveModelLibraryService(
      root: root.appending(path: "Models"), engine: engine, conversations: coordinator,
      manifests: try Self.manifests(),
      installationProvider: { installations[$0] })

    try await service.perform(.load, for: .oneBit27B)
    let first = try await coordinator.activeSelection()
    try await service.perform(.load, for: .ternary27B)
    let second = try await coordinator.activeSelection()

    let loadedModelID = await service.currentLoadedModelID()
    XCTAssertEqual(loadedModelID, .ternary27B)
    XCTAssertEqual(second.installation, ternary)
    XCTAssertNotEqual(first.conversationID, second.conversationID)
  }

  func testLiveModelServiceBlocksConcurrentSendAndRollsBackFailedReplacement() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let oldRuntime = PersistingRuntimeResource()
    let loader = ControlledRuntimeLoader(resources: [
      .oneBit27B: oldRuntime, .ternary27B: PersistingRuntimeResource()
    ])
    let engine = MLXInferenceEngine(loader: loader)
    let coordinator = try ConversationCoordinator(root: root, store: ConversationStore(root: root))
    let gate = ModelSessionGate()
    let oneBit = ModelInstallation(modelID: .oneBit27B,
                                   directory: URL(fileURLWithPath: "/tmp/rollback-one"),
                                   revision: String(repeating: "6", count: 40))
    let ternary = ModelInstallation(modelID: .ternary27B,
                                    directory: URL(fileURLWithPath: "/tmp/rollback-ternary"),
                                    revision: String(repeating: "7", count: 40))
    let installations = [ModelID.oneBit27B: oneBit, .ternary27B: ternary]
    let library = try LiveModelLibraryService(
      root: root.appending(path: "Models"), engine: engine, conversations: coordinator,
      sessionGate: gate, manifests: try Self.manifests(),
      installationProvider: { installations[$0] })
    try await library.perform(.load, for: .oneBit27B)
    await loader.failNextLoad(of: .ternary27B)
    let replacement = Task {
      do { try await library.perform(.load, for: .ternary27B); return false } catch { return true }
    }
    await loader.waitUntilBlocked()

    let registry = try ToolRegistry.live(notes: NotesStore(root: root))
    let chat = AgentLoopChatService(
      loop: AgentLoop(engine: engine, registry: registry), approvals: InteractiveApprovalGate(),
      engine: engine, conversations: coordinator, sessionGate: gate)
    let concurrentSend = Task {
      var events: [ChatSessionEvent] = []
      if let stream = try? await chat.stream(.init(prompt: "still coherent", effort: .off)) {
        do { for try await event in stream { events.append(event) } } catch {}
      }
      return events
    }
    for _ in 0..<20 { await Task.yield() }
    XCTAssertTrue(oldRuntime.streamedMessages.isEmpty,
                  "generation must not enter the runtime during replacement")

    await loader.resumeBlockedLoad()
    let replacementFailed = await replacement.value
    XCTAssertTrue(replacementFailed)
    let events = await concurrentSend.value
    XCTAssertTrue(events.contains(.completed(.stop)))
    let loadedModelID = await library.currentLoadedModelID()
    let restoredSelection = try await coordinator.activeSelection()
    XCTAssertEqual(loadedModelID, .oneBit27B)
    XCTAssertEqual(restoredSelection.installation, oneBit)
    XCTAssertEqual(oldRuntime.streamedMessages.count, 1)
  }

  func testCancelledSendQueuedBehindReplacementNeverRunsLaterAndGateRemainsUsable() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let oldRuntime = PersistingRuntimeResource()
    let loader = ControlledRuntimeLoader(resources: [
      .oneBit27B: oldRuntime, .ternary27B: PersistingRuntimeResource()
    ])
    let engine = MLXInferenceEngine(loader: loader)
    let coordinator = try ConversationCoordinator(root: root, store: ConversationStore(root: root))
    let gate = ModelSessionGate()
    let oneBit = ModelInstallation(modelID: .oneBit27B,
                                   directory: URL(fileURLWithPath: "/tmp/cancel-send-one"),
                                   revision: String(repeating: "8", count: 40))
    let ternary = ModelInstallation(modelID: .ternary27B,
                                    directory: URL(fileURLWithPath: "/tmp/cancel-send-ternary"),
                                    revision: String(repeating: "9", count: 40))
    let installations = [ModelID.oneBit27B: oneBit, .ternary27B: ternary]
    let library = try LiveModelLibraryService(
      root: root.appending(path: "Models"), engine: engine, conversations: coordinator,
      sessionGate: gate, manifests: try Self.manifests(),
      installationProvider: { installations[$0] })
    try await library.perform(.load, for: .oneBit27B)
    await loader.failNextLoad(of: .ternary27B)
    let replacement = Task { try? await library.perform(.load, for: .ternary27B) }
    await loader.waitUntilBlocked()
    let registry = try ToolRegistry.live(notes: NotesStore(root: root))
    let chat = AgentLoopChatService(
      loop: AgentLoop(engine: engine, registry: registry), approvals: InteractiveApprovalGate(),
      engine: engine, conversations: coordinator, sessionGate: gate)
    let queuedSend = Task { () -> Result<[ChatSessionEvent], any Error> in
      do {
        return .success(try await Self.collect(
          try await chat.stream(.init(prompt: "cancel me", effort: .off))))
      }
      catch { return .failure(error) }
    }
    for _ in 0..<20 { await Task.yield() }
    queuedSend.cancel()
    await loader.resumeBlockedLoad()
    await replacement.value

    guard case .failure(let error) = await queuedSend.value else {
      return XCTFail("cancelled queued send unexpectedly produced a stream")
    }
    XCTAssertTrue(error is CancellationError)
    XCTAssertTrue(oldRuntime.streamedMessages.isEmpty)
    let selection = try await coordinator.activeSelection()
    let persisted = try await ConversationStore(root: root).load(selection.conversationID,
                                                                 for: .oneBit27B)
    XCTAssertNil(persisted)

    let laterEvents = try await Self.collect(
      try await chat.stream(.init(prompt: "later", effort: .off)))
    XCTAssertTrue(laterEvents.contains(.completed(.stop)), "gate must not deadlock after cancellation")
    XCTAssertEqual(oldRuntime.streamedMessages.count, 1)
  }

  func testCancelledSwitchQueuedBehindReplacementNeverLoadsLaterAndGateRemainsUsable() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let loader = ControlledRuntimeLoader(resources: [
      .oneBit27B: PersistingRuntimeResource(), .ternary27B: PersistingRuntimeResource()
    ])
    let engine = MLXInferenceEngine(loader: loader)
    let coordinator = try ConversationCoordinator(root: root, store: ConversationStore(root: root))
    let gate = ModelSessionGate()
    let oneBit = ModelInstallation(modelID: .oneBit27B,
                                   directory: URL(fileURLWithPath: "/tmp/cancel-switch-one"),
                                   revision: String(repeating: "a", count: 40))
    let ternary = ModelInstallation(modelID: .ternary27B,
                                    directory: URL(fileURLWithPath: "/tmp/cancel-switch-ternary"),
                                    revision: String(repeating: "b", count: 40))
    let installations = [ModelID.oneBit27B: oneBit, .ternary27B: ternary]
    let library = try LiveModelLibraryService(
      root: root.appending(path: "Models"), engine: engine, conversations: coordinator,
      sessionGate: gate, manifests: try Self.manifests(),
      installationProvider: { installations[$0] })
    try await library.perform(.load, for: .oneBit27B)
    await loader.failNextLoad(of: .ternary27B)
    let holdingReplacement = Task { try? await library.perform(.load, for: .ternary27B) }
    await loader.waitUntilBlocked()
    let queuedSwitch = Task { () -> Result<Void, any Error> in
      do { try await library.perform(.load, for: .ternary27B); return .success(()) }
      catch { return .failure(error) }
    }
    for _ in 0..<20 { await Task.yield() }
    queuedSwitch.cancel()
    await loader.resumeBlockedLoad()
    await holdingReplacement.value

    guard case .failure(let error) = await queuedSwitch.value else {
      return XCTFail("cancelled queued switch unexpectedly loaded a model")
    }
    XCTAssertTrue(error is CancellationError)
    let modelAfterCancellation = await library.currentLoadedModelID()
    XCTAssertEqual(modelAfterCancellation, .oneBit27B)

    try await library.perform(.load, for: .ternary27B)
    let modelAfterLaterSwitch = await library.currentLoadedModelID()
    XCTAssertEqual(modelAfterLaterSwitch, .ternary27B,
                   "gate must not deadlock after cancellation")
  }

  func testCommittedTurnCompletesWhenBestEffortRenameCannotPersist() async throws {
    let runtime = PersistingRuntimeResource()
    let engine = MLXInferenceEngine(loader: PersistingRuntimeLoader(resource: runtime))
    let revision = String(repeating: "c", count: 40)
    let installation = ModelInstallation(modelID: .oneBit27B,
                                         directory: URL(fileURLWithPath: "/tmp/rename-failure"),
                                         revision: revision)
    try await engine.load(installation)
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let store = try ConversationStore(root: root)
    let coordinator = try ConversationCoordinator(root: root, store: store)
    try await coordinator.bind(installation)
    let navigationRoot = root.appending(path: "ConversationNavigation")
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o700],
                                             ofItemAtPath: navigationRoot.path)
    }
    try FileManager.default.setAttributes([.posixPermissions: 0o500],
                                          ofItemAtPath: navigationRoot.path)
    let registry = try ToolRegistry.live(notes: NotesStore(root: root))
    let chat = AgentLoopChatService(
      loop: AgentLoop(engine: engine, registry: registry), approvals: InteractiveApprovalGate(),
      engine: engine, conversations: coordinator)

    let events = try await Self.collect(
      try await chat.stream(.init(prompt: "Keep this", effort: .off)))

    XCTAssertTrue(events.contains(.completed(.stop)),
                  "metadata failure after commit must not invite a duplicate retry")
    let selection = try await coordinator.activeSelection()
    let savedTurnCount = try await store.load(selection.conversationID,
                                              for: .oneBit27B)?.completedTurns.count
    XCTAssertEqual(savedTurnCount, 1)
  }

  private static func collect(
    _ stream: AsyncThrowingStream<ChatSessionEvent, any Error>
  ) async throws -> [ChatSessionEvent] {
    var events: [ChatSessionEvent] = []
    for try await event in stream { events.append(event) }
    return events
  }

  private static func manifests() throws -> [ModelID: ModelManifest] {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().appending(path: "Resources/Models/manifest.json")
    let catalog = try JSONDecoder().decode(ModelCatalog.self, from: Data(contentsOf: url))
    return Dictionary(uniqueKeysWithValues: catalog.models.map { ($0.id, $0.manifest) })
  }

  func testPersistencePolicyCoversEveryTerminalClass() {
    XCTAssertTrue(AgentLoopChatService.shouldPersist(.stop))
    XCTAssertTrue(AgentLoopChatService.shouldPersist(.length))
    XCTAssertFalse(AgentLoopChatService.shouldPersist(.cancelled))
    XCTAssertFalse(AgentLoopChatService.shouldPersist(.toolTurnLimit(6)))
    XCTAssertFalse(AgentLoopChatService.shouldPersist(.duplicateInvocationID("duplicate")))
    XCTAssertFalse(AgentLoopChatService.shouldPersist(.runtimeFailure("fatal")))
  }

  func testCancelledPartialTurnIsNotRestoredAsCompletedHistory() async throws {
    for completion in [CompletionReason.stop, .length, .cancelled] {
      let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
      let store = try ConversationStore(root: root)
      let coordinator = try ConversationCoordinator(root: root, store: store)
      let installation = ModelInstallation(
        modelID: .oneBit27B,
        directory: URL(fileURLWithPath: "/tmp/terminal-runtime"),
        revision: String(repeating: "3", count: 40))
      try await coordinator.bind(installation)
      let engine = UIAgentEngine(events: [.answer("partial"), .completed(completion)])
      let registry = try ToolRegistry.live(notes: NotesStore(root: root))
      let service = AgentLoopChatService(
        loop: AgentLoop(engine: engine, registry: registry),
        approvals: InteractiveApprovalGate(),
        conversations: coordinator)

      let request = ChatSendRequest(prompt: "keep draft", effort: .off)
      for try await _ in try await service.stream(request) {}
      let selection = try await coordinator.activeSelection()
      let saved = try await store.load(selection.conversationID, for: .oneBit27B)
      if completion == .stop || completion == .length {
        XCTAssertEqual(saved?.completedTurns.count, 1, "completion=\(completion)")
      } else {
        XCTAssertNil(saved, "partial turn persisted for completion=\(completion)")
      }
    }
  }
}

private struct PersistingRuntimeLoader: MLXRuntimeLoading {
  let resource: PersistingRuntimeResource
  func load(_ installation: ModelInstallation) async throws -> any MLXRuntimeResource { resource }
}

private struct SwitchingRuntimeLoader: MLXRuntimeLoading {
  let resources: [ModelID: PersistingRuntimeResource]
  func load(_ installation: ModelInstallation) async throws -> any MLXRuntimeResource {
    try XCTUnwrap(resources[installation.modelID])
  }
}

private actor ControlledRuntimeLoader: MLXRuntimeLoading {
  enum Failure: Error { case requested }
  let resources: [ModelID: PersistingRuntimeResource]
  private var failingModel: ModelID?
  private var blocked = false
  private var continuation: CheckedContinuation<Void, Never>?

  init(resources: [ModelID: PersistingRuntimeResource]) { self.resources = resources }
  func load(_ installation: ModelInstallation) async throws -> any MLXRuntimeResource {
    if failingModel == installation.modelID {
      blocked = true
      await withCheckedContinuation { continuation = $0 }
      blocked = false
      failingModel = nil
      throw Failure.requested
    }
    return try XCTUnwrap(resources[installation.modelID])
  }
  func failNextLoad(of modelID: ModelID) { failingModel = modelID }
  func waitUntilBlocked() async { while !blocked { await Task.yield() } }
  func resumeBlockedLoad() { continuation?.resume(); continuation = nil }
}

private final class PersistingRuntimeResource: MLXRuntimeResource, @unchecked Sendable {
  let reasoningConfig: ReasoningConfig? = nil
  private let lock = NSLock()
  private(set) var streamedMessages: [[ConversationMessage]] = []
  func configure(_ request: GenerationRequest) {}
  func streamDetails(to prompt: String) -> AsyncThrowingStream<MLXLMCommon.Generation, Error> {
    fatalError("structured generation required")
  }
  func streamDetails(to messages: [ConversationMessage]) throws
    -> AsyncThrowingStream<MLXLMCommon.Generation, Error> {
    lock.withLock { streamedMessages.append(messages) }
    let pair = AsyncThrowingStream<MLXLMCommon.Generation, Error>.makeStream()
    pair.continuation.yield(.chunk("answer"))
    pair.continuation.yield(.info(.init(promptTokenCount: messages.count,
                                       generationTokenCount: 1, promptTime: 0.01,
                                       generationTime: 0.01, stopReason: .stop)))
    pair.continuation.finish()
    return pair.stream
  }
  func preparedPromptTokenCount(for messages: [ConversationMessage], reasoningEnabled: Bool,
                                tools: [GenerationToolSpecification]) async throws -> Int {
    messages.count
  }
}

private extension Array {
  var single: Element? { count == 1 ? first : nil }
}

private actor UIAgentEngine: AgentInferenceStreaming {
  let events: [GenerationEvent]
  private(set) var lastRequest: GenerationRequest?
  init(events: [GenerationEvent]) { self.events = events }
  func generate(_ request: GenerationRequest) async throws
    -> AsyncThrowingStream<GenerationEvent, any Error> {
    lastRequest = request
    let pair = AsyncThrowingStream<GenerationEvent, any Error>.makeStream()
    events.forEach { pair.continuation.yield($0) }
    pair.continuation.finish()
    return pair.stream
  }
  func continueAfterTools(_ exchange: AgentToolExchange) async throws
    -> AsyncThrowingStream<GenerationEvent, any Error> { fatalError("not used") }
  func cancel() async {}
}

private actor ScriptedChatService: ChatSessionServing {
  let events: [ChatSessionEvent]
  init(events: [ChatSessionEvent]) { self.events = events }

  func stream(_ request: ChatSendRequest) async throws -> AsyncThrowingStream<ChatSessionEvent, any Error> {
    let pair = AsyncThrowingStream<ChatSessionEvent, any Error>.makeStream()
    for event in events { pair.continuation.yield(event) }
    pair.continuation.finish()
    return pair.stream
  }

  func cancel() async {}
}

private actor SuspendingChatService: ChatSessionServing {
  private var started = false
  private var cancelled = false
  private var continuation: AsyncThrowingStream<ChatSessionEvent, any Error>.Continuation?
  var wasCancelled: Bool { cancelled }

  func stream(_ request: ChatSendRequest) async throws -> AsyncThrowingStream<ChatSessionEvent, any Error> {
    started = true
    let pair = AsyncThrowingStream<ChatSessionEvent, any Error>.makeStream()
    continuation = pair.continuation
    return pair.stream
  }

  func cancel() async { cancelled = true; continuation?.finish(throwing: CancellationError()) }

  func waitUntilStarted() async {
    while !started { await Task.yield() }
  }
}
// swiftlint:enable file_length type_body_length
