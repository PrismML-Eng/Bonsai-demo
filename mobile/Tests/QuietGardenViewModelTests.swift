import XCTest
import MLXLMCommon
@testable import BonsaiMobile

@MainActor
final class QuietGardenViewModelTests: XCTestCase {
  func testTernaryIsUnsupportedOnIPhoneAndCannotLoad() {
    let rows = ModelLibraryViewModel.rows(
      snapshot: .fixture(.ready),
      loadedModelID: nil,
      platform: .iPhone
    )

    let ternary = try? XCTUnwrap(rows.first { $0.id == .ternary27B })
    XCTAssertEqual(ternary?.detail, "Ternary requires a verified high-memory iPad or Mac.")
    XCTAssertEqual(ternary?.primaryAction, nil)
  }

  func testLibraryMapsProgressAndRecoveryActions() throws {
    let downloading = ModelLibraryViewModel.rows(
      snapshot: .fixture(.downloading), loadedModelID: nil, platform: .mac
    )[0]
    XCTAssertEqual(try XCTUnwrap(downloading.progress), 0.4, accuracy: 0.001)
    XCTAssertEqual(downloading.status, "Downloading 2 of 5 files")

    let failed = ModelLibraryViewModel.rows(
      snapshot: .fixture(.recoverableFailure), loadedModelID: nil, platform: .mac
    )[0]
    XCTAssertEqual(failed.recovery?.label, "Retry download")
  }

  func testLibraryMapsExactByteProgressAndImportRequestsPicker() async throws {
    let snapshot = ModelLibrarySnapshot(states: [
      .oneBit27B: .transferring(completedBytes: 25, totalBytes: 100),
      .ternary27B: .notInstalled
    ])
    let service = RecordingLibraryService(snapshot: snapshot)
    let viewModel = ModelLibraryViewModel(service: service, platform: .mac, initial: snapshot)
    let row = try XCTUnwrap(viewModel.rows.first { $0.id == .oneBit27B })
    XCTAssertEqual(try XCTUnwrap(row.progress), 0.25, accuracy: 0.001)

    let importRow = try XCTUnwrap(viewModel.rows.first { $0.id == .ternary27B })
    let importAction = try XCTUnwrap(importRow.secondaryActions.first)
    await viewModel.perform(importAction, modelID: .ternary27B)
    XCTAssertEqual(viewModel.pendingImportModelID, .ternary27B)
    let recordedIntent = await service.lastIntent
    XCTAssertNil(recordedIntent)
  }

  func testSuccessfulDeleteClearsStaleLoadedIdentity() async throws {
    let snapshot = ModelLibrarySnapshot.fixture(.ready)
    let service = RecordingLibraryService(snapshot: snapshot)
    let viewModel = ModelLibraryViewModel(service: service, platform: .mac, initial: snapshot)
    let load = try XCTUnwrap(viewModel.rows.first { $0.id == .oneBit27B }?.primaryAction)
    await viewModel.perform(load, modelID: .oneBit27B)
    let delete = try XCTUnwrap(viewModel.rows.first { $0.id == .oneBit27B }?
      .secondaryActions.first { $0.intent == .delete })
    await viewModel.perform(delete, modelID: .oneBit27B)
    XCTAssertNil(viewModel.loadedModelID)
  }

  func testLibraryLoadIntentUpdatesLoadedStateAndChatReadinessContract() async throws {
    let snapshot = ModelLibrarySnapshot.fixture(.ready)
    let service = RecordingLibraryService(snapshot: snapshot)
    let viewModel = ModelLibraryViewModel(service: service, platform: .mac, initial: snapshot)
    let row = try XCTUnwrap(viewModel.rows.first { $0.id == .oneBit27B })
    let action = try XCTUnwrap(row.primaryAction)

    await viewModel.perform(action, modelID: .oneBit27B)

    let intent = await service.lastIntent
    XCTAssertEqual(intent, .load)
    XCTAssertTrue(try XCTUnwrap(viewModel.rows.first { $0.id == .oneBit27B }).isLoaded)
  }

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

  func testRuntimeFailurePreservesUserMessageAndOffersRetry() async {
    let service = ScriptedChatService(events: [.failed("Model memory was released.")])
    let viewModel = ChatViewModel(service: service, isModelReady: true)
    viewModel.draft = "Please keep this"

    await viewModel.send()

    XCTAssertEqual(viewModel.messages.first?.text, "Please keep this")
    XCTAssertEqual(viewModel.failedPrompt, "Please keep this")
    XCTAssertEqual(viewModel.recovery?.label, "Retry send")
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
    let registry = try ToolRegistry.live(notes: NotesStore(root: root))
    let gate = InteractiveApprovalGate()
    let service = AgentLoopChatService(
      loop: AgentLoop(engine: engine, registry: registry), approvals: gate, engine: engine,
      conversationStore: store, conversationID: try ConversationID("main"),
      modelRevision: revision)

    for prompt in ["first", "second"] {
      for try await _ in try await service.stream(.init(prompt: prompt, effort: .off)) {}
    }

    let loaded = try await store.load(ConversationID("main"), for: .oneBit27B)
    let saved = try XCTUnwrap(loaded)
    XCTAssertEqual(saved.completedTurns.count, 2)
    XCTAssertEqual(runtime.streamedMessages.count, 2)
    XCTAssertEqual(runtime.streamedMessages[1].map(\.role),
                   [.system, .user, .assistant, .user])
  }
}

private struct PersistingRuntimeLoader: MLXRuntimeLoading {
  let resource: PersistingRuntimeResource
  func load(_ installation: ModelInstallation) async throws -> any MLXRuntimeResource { resource }
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

private actor RecordingLibraryService: ModelLibraryServing {
  let snapshot: ModelLibrarySnapshot
  private(set) var lastIntent: ModelLibraryIntent?
  init(snapshot: ModelLibrarySnapshot) { self.snapshot = snapshot }
  func snapshots() async -> AsyncStream<ModelLibrarySnapshot> {
    AsyncStream { continuation in continuation.yield(snapshot); continuation.finish() }
  }
  func perform(_ intent: ModelLibraryIntent, for modelID: ModelID) async throws { lastIntent = intent }
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
