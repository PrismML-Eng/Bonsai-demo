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
      .cancelledGeneration, .contextTrimmed, .toolDenied, .attachmentDraft,
      .fullDetailWarning, .permissionDenied, .preprocessingError, .visionStreaming,
      .attachmentRecovery
    ])
    XCTAssertEqual(UIFixture.readyChat.makeState(), UIFixture.readyChat.makeState())
    XCTAssertEqual(UIAccessibility.chatComposer, "chat.composer")
  }

  func testSendWithAttachmentRejectsBeforeServiceWhenModelLacksVision() async {
    let service = RecordingChatService(events: [.completed(.stop)])
    let viewModel = ChatViewModel(service: service, isModelReady: true)
    viewModel.supportsVisionInput = false
    viewModel.applyFixture(UIFixture.attachmentDraft.makeState())
    viewModel.draft = "What is in this image?"

    await viewModel.send()

    let requestCount = await service.requestCount
    XCTAssertEqual(requestCount, 0)
    XCTAssertEqual(viewModel.draft, "What is in this image?")
    XCTAssertNotNil(viewModel.draftAttachment)
    XCTAssertEqual(
      viewModel.attachmentError,
      "This model does not support images. Remove the attachment or load a vision-capable model.")
  }

    func testLargeFullDetailRequiresConfirmationBeforeServiceStarts() async {
    let service = RecordingChatService(events: [.completed(.stop)])
    let viewModel = ChatViewModel(service: service, isModelReady: true)
    viewModel.applyFixture(UIFixture.fullDetailWarning.makeState())
    viewModel.dismissFullDetailWarning()
    viewModel.draft = "Read the small text"

    await viewModel.send()

    XCTAssertTrue(viewModel.showsFullDetailWarning)
    let requestsBeforeConfirmation = await service.requestCount
    XCTAssertEqual(requestsBeforeConfirmation, 0)
    await viewModel.confirmFullDetailSend()
    let requestsAfterConfirmation = await service.requestCount
    XCTAssertEqual(requestsAfterConfirmation, 1)
    XCTAssertNil(viewModel.draftAttachment)
  }

  func testGenerationFailurePreservesPromptAndManagedAttachmentDraft() async {
    let service = RecordingChatService(events: [.completed(.runtimeFailure("Memory pressure"))])
    let viewModel = ChatViewModel(service: service, isModelReady: true)
    let attachment = UIFixture.attachmentRecovery.makeState().draftAttachment
    viewModel.applyFixture(UIFixture.attachmentRecovery.makeState())
    viewModel.draft = "Describe this"

    await viewModel.send()

    XCTAssertEqual(viewModel.draft, "Describe this")
    XCTAssertEqual(viewModel.draftAttachment, attachment)
    XCTAssertEqual(viewModel.recovery?.label, "Retry send")
  }

  func testTokenLimitClearsPersistedDraftAndMutationIsDisabledInFlight() async {
    let service = SuspendingChatService()
    let viewModel = ChatViewModel(service: service, isModelReady: true)
    viewModel.applyFixture(UIFixture.attachmentDraft.makeState())
    viewModel.draft = "Describe this"
    let send = Task { await viewModel.send() }
    await service.waitUntilStarted()
    XCTAssertTrue(viewModel.isGenerating)
    await viewModel.removeAttachment()
    viewModel.setDetailPolicy(.fullDetail)
    XCTAssertNotNil(viewModel.draftAttachment)
    await service.finish(.length)
    await send.value
    XCTAssertNil(viewModel.draftAttachment)
  }

  func testReplacingDraftDeletesSupersededManagedCopy() async {
    let first = UIFixture.attachmentDraft.makeState().draftAttachment!
    let second = ImageAttachment(
      id: UUID(), originalFilename: "second.jpg", managedRelativePath: "second.jpg",
      pixelSize: .init(width: 640, height: 480), byteCount: 100,
      contentType: "image/jpeg", detailPolicy: .fast1024, lifecycle: .managedDraft,
      accessibleLabel: "Second image")
    let attachments = AttachmentLifecycleService(imports: [first, second])
    let viewModel = ChatViewModel(
      service: RecordingChatService(events: []), isModelReady: true, attachments: attachments)

    await viewModel.importAttachment(data: Data([1]), filename: "first.jpg")
    await viewModel.importAttachment(data: Data([2]), filename: "second.jpg")

    XCTAssertEqual(viewModel.draftAttachment?.id, second.id)
    let deletedIDs = await attachments.deletedIDs
    XCTAssertEqual(deletedIDs, [first.id])
  }

  func testClearDataSuccessResetsDraftUIAndFailureOffersNamedRetry() async {
    let viewModel = ChatViewModel(
      service: RecordingChatService(events: []), isModelReady: true)
    viewModel.applyFixture(UIFixture.attachmentRecovery.makeState())
    viewModel.draft = "private draft"

    await viewModel.clearLocalData(using: StubSettingsService(shouldFail: true))
    XCTAssertNotNil(viewModel.draftAttachment)
    XCTAssertEqual(viewModel.recovery?.label, "Retry clear data")
    XCTAssertNotNil(viewModel.clearDataError)

    await viewModel.clearLocalData(using: StubSettingsService(shouldFail: false))
    XCTAssertNil(viewModel.draftAttachment)
    XCTAssertTrue(viewModel.draft.isEmpty)
    XCTAssertTrue(viewModel.messages.isEmpty)
    XCTAssertNil(viewModel.clearDataError)
    XCTAssertNil(viewModel.recovery)
  }

  func testClearWaitsForCompletedImportOwnershipAndDeletesLosingCopyBeforeRollback() async {
    let attachment = ImageAttachment(
      id: UUID(), originalFilename: "race.jpg", managedRelativePath: "race.jpg",
      pixelSize: .init(width: 32, height: 32), byteCount: 100,
      contentType: "image/jpeg", detailPolicy: .fast1024, lifecycle: .managedDraft,
      accessibleLabel: "Race")
    let attachments = SuspendingAttachmentLifecycleService(attachment: attachment)
    let settings = SequencedSettingsService(failuresBeforeSuccess: 1)
    let viewModel = ChatViewModel(
      service: RecordingChatService(events: []), isModelReady: true, attachments: attachments)
    let importing = Task { await viewModel.importAttachment(data: Data([1]), filename: "race.jpg") }
    await attachments.waitUntilWritten()
    let clearing = Task { await viewModel.clearLocalData(using: settings) }
    await Task.yield()
    let callsBeforeOwnership = await settings.callCount
    XCTAssertEqual(callsBeforeOwnership, 0)

    await attachments.resumeReturn()
    await importing.value
    await clearing.value

    let deleted = await attachments.deletedIDs
    let callsAfterOwnership = await settings.callCount
    XCTAssertEqual(deleted, [attachment.id])
    XCTAssertNil(viewModel.draftAttachment)
    XCTAssertEqual(callsAfterOwnership, 1)
    XCTAssertNotNil(viewModel.clearDataError)
  }

  func testPersistentRetryClearActionRetriesClearAndNeverSendsChat() async {
    let chat = RecordingChatService(events: [])
    let settings = SequencedSettingsService(failuresBeforeSuccess: 1)
    let viewModel = ChatViewModel(service: chat, isModelReady: true)
    viewModel.draft = "must not send"
    await viewModel.clearLocalData(using: settings)

    XCTAssertEqual(viewModel.recovery?.intent, .retryClear)
    await viewModel.performRecovery()

    let settingsCallCount = await settings.callCount
    let chatRequestCount = await chat.requestCount
    XCTAssertEqual(settingsCallCount, 2)
    XCTAssertEqual(chatRequestCount, 0)
    XCTAssertNil(viewModel.recovery)
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
      } catch { return .failure(error) }
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
      do { try await library.perform(.load, for: .ternary27B); return .success(()) } catch {
        return .failure(error)
      }
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

  func testImageSendFailsBeforeRuntimeWhenModelLacksVisionCapability() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let engine = UIAgentEngine(events: [.answer("must not run"), .completed(.stop)])
    let registry = try ToolRegistry.live(notes: NotesStore(root: root))
    let coordinator = try ConversationCoordinator(root: root, store: ConversationStore(root: root))
    let installation = ModelInstallation(
      modelID: .oneBit27B,
      directory: URL(fileURLWithPath: "/tmp/text-only-vision"),
      revision: String(repeating: "d", count: 40))
    try await coordinator.bind(installation)
    let catalog = try Self.catalog()
    let baseline = try XCTUnwrap(catalog.models.first(where: { $0.id == .oneBit27B }))
    let textOnly = try ModelDescriptor.validated(
      id: baseline.id,
      family: baseline.family,
      displayName: baseline.displayName,
      manifest: baseline.manifest,
      requirements: .init(
        capabilities: baseline.capabilities.subtracting([.vision]),
        minimumPhysicalMemoryBytes: baseline.minimumPhysicalMemoryBytes,
        storageSafetyMarginBytes: baseline.storageSafetyMarginBytes))
    let attachment = ImageAttachment(
      id: UUID(), originalFilename: "photo.jpg", managedRelativePath: "photo.jpg",
      pixelSize: .init(width: 64, height: 64), byteCount: 10, contentType: "image/jpeg",
      detailPolicy: .fast1024, lifecycle: .managedDraft, accessibleLabel: "Photo")
    let chat = AgentLoopChatService(
      loop: AgentLoop(engine: engine, registry: registry), approvals: InteractiveApprovalGate(),
      conversations: coordinator,
      descriptors: [.oneBit27B: textOnly])

    do {
      _ = try await Self.collect(try await chat.stream(.init(
        prompt: "Describe", effort: .off, attachment: attachment)))
      XCTFail("expected vision rejection before generation")
    } catch let error as LiveUIServiceError {
      XCTAssertEqual(
        error.errorDescription,
        "\(textOnly.displayName) does not support images. Remove the attachment or load a vision-capable model.")
    }
  }

    private static func catalog() throws -> ModelCatalog {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().appending(path: "Resources/Models/manifest.json")
    return try JSONDecoder().decode(ModelCatalog.self, from: Data(contentsOf: url))
  }

  private static func manifests() throws -> [ModelID: ModelManifest] {
    try Dictionary(uniqueKeysWithValues: catalog().models.map { ($0.id, $0.manifest) })
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

private actor RecordingChatService: ChatSessionServing {
  let events: [ChatSessionEvent]
  private(set) var requests: [ChatSendRequest] = []
  var requestCount: Int { requests.count }

  init(events: [ChatSessionEvent]) { self.events = events }

  func stream(
    _ request: ChatSendRequest
  ) async throws -> AsyncThrowingStream<ChatSessionEvent, any Error> {
    requests.append(request)
    let pair = AsyncThrowingStream<ChatSessionEvent, any Error>.makeStream()
    events.forEach { pair.continuation.yield($0) }
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

  func finish(_ completion: AgentCompletion) {
    continuation?.yield(.completed(completion))
    continuation?.finish()
  }
}

private actor AttachmentLifecycleService: AttachmentServing {
  private var imports: [ImageAttachment]
  private(set) var deletedIDs: [UUID] = []

  init(imports: [ImageAttachment]) { self.imports = imports }

  func importImage(
    from source: URL, policy: ImageDetailPolicy, accessibleLabel: String
  ) throws -> ImageAttachment { imports.removeFirst() }

  func importImage(
    data: Data, filename: String, policy: ImageDetailPolicy, accessibleLabel: String
  ) throws -> ImageAttachment { imports.removeFirst() }

  func delete(_ attachment: ImageAttachment) { deletedIDs.append(attachment.id) }
}

private actor SuspendingAttachmentLifecycleService: AttachmentServing {
  let attachment: ImageAttachment
  private var written = false
  private var continuation: CheckedContinuation<Void, Never>?
  private(set) var deletedIDs: [UUID] = []
  init(attachment: ImageAttachment) { self.attachment = attachment }
  func importImage(
    from source: URL, policy: ImageDetailPolicy, accessibleLabel: String
  ) async throws -> ImageAttachment { await suspendAfterWrite() }
  func importImage(
    data: Data, filename: String, policy: ImageDetailPolicy, accessibleLabel: String
  ) async throws -> ImageAttachment { await suspendAfterWrite() }
  func delete(_ attachment: ImageAttachment) { deletedIDs.append(attachment.id) }
  func waitUntilWritten() async { while !written { await Task.yield() } }
  func resumeReturn() { continuation?.resume(); continuation = nil }
  private func suspendAfterWrite() async -> ImageAttachment {
    written = true
    await withCheckedContinuation { continuation = $0 }
    return attachment
  }
}

private actor StubSettingsService: SettingsServing {
  enum Failure: Error { case requested }
  let shouldFail: Bool
  init(shouldFail: Bool) { self.shouldFail = shouldFail }
  func clearConversationsNotesAndImages() throws {
    if shouldFail { throw Failure.requested }
  }
}

private actor SequencedSettingsService: SettingsServing {
  enum Failure: Error { case requested }
  private var failuresRemaining: Int
  private(set) var callCount = 0

  init(failuresBeforeSuccess: Int) { failuresRemaining = failuresBeforeSuccess }

  func clearConversationsNotesAndImages() throws {
    callCount += 1
    if failuresRemaining > 0 {
      failuresRemaining -= 1
      throw Failure.requested
    }
  }
}
// swiftlint:enable file_length type_body_length
