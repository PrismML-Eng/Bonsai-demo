import Foundation
import XCTest

@testable import BonsaiMobile

// swiftlint:disable:next type_body_length
final class MLXInferenceIntegrationTests: XCTestCase {
  // One real-model lane intentionally keeps timing, result, and identity proof together.
  // swiftlint:disable:next function_body_length
  func testRealToolRoundTrip() async throws {
    let modelDirectory = try Self.modelDirectory()
    let engine = MLXInferenceEngine()
    let clock = ContinuousClock()
    let loadStart = clock.now
    try await engine.load(
      .init(
        modelID: .oneBit27B,
        directory: modelDirectory,
        revision: "public-local-fixture"
      ))
    let loadDuration = loadStart.duration(to: clock.now)
    let notesRoot = FileManager.default.temporaryDirectory.appending(
      path: "RealAgentNotes-\(UUID())"
    )
    let registry = try ToolRegistry.live(notes: NotesStore(root: notesRoot))
    let before = await engine.debugSnapshot()
    let continuationBefore = await engine.continuationDebugSnapshot()
    let runStart = clock.now
    let result = try await AgentLoop(
      engine: engine, registry: registry
    ).run(
      try GenerationRequest(
        messages: [
          .init(
            id: MessageID("user-tool"),
            role: .user,
            content:
              // swiftlint:disable:next line_length
              "You must use the calculator tool to compute (37 * 19) + 5. After the tool result, answer with the number only."
          )
        ],
        reasoningEnabled: false,
        maxTokens: 128
      ))
    let runDuration = runStart.duration(to: clock.now)
    let after = await engine.debugSnapshot()
    let continuationAfter = await engine.continuationDebugSnapshot()

    XCTAssertEqual(result.toolResults.count, 1)
    XCTAssertEqual(result.toolResults.first?.status, .succeeded)
    XCTAssertEqual(result.toolResults.first?.invocationID.isEmpty, false)
    XCTAssertEqual(result.toolResults.first?.contentJSON, "{\"result\":708}")
    XCTAssertEqual(result.completion, .stop)
    XCTAssertEqual(result.answer.trimmingCharacters(in: .whitespacesAndNewlines), "708")
    XCTAssertEqual(before.loadedModelID, after.loadedModelID)
    XCTAssertTrue(before.hasContainer && after.hasContainer)
    XCTAssertTrue(before.hasSession && after.hasSession)
    XCTAssertEqual(continuationBefore.runtimeIdentity, continuationAfter.runtimeIdentity)
    XCTAssertEqual(
      continuationAfter.generationSessionIdentity,
      continuationAfter.continuationSessionIdentity)
    XCTAssertEqual(continuationAfter.sessionIdentity, continuationAfter.continuationSessionIdentity)
    XCTAssertEqual(continuationAfter.continuationCount, 1)
    XCTAssertEqual(continuationAfter.fullHistoryReplayCount, 1)
    print(
      // swiftlint:disable:next line_length
      "RealToolRoundTrip load=\(loadDuration) total=\(runDuration) result=\(result.toolResults[0].contentJSON) answer=\(result.answer)"
    )
    await engine.unload()
  }

  func testPublicOneBitTokenizerBackedContextComposition() async throws {
    let modelDirectory = try Self.modelDirectory()
    let engine = MLXInferenceEngine()
    try await engine.load(
      ModelInstallation(
        modelID: .oneBit27B,
        directory: modelDirectory,
        revision: "public-local-fixture"
      )
    )
    let before = await engine.debugSnapshot()

    let prepared = try await engine.preparedGeneration(
      for: Self.contextConversation(),
      reasoningEnabled: false,
      maxTokens: 1
    )
    let result = prepared.trim

    XCTAssertGreaterThan(result.keptTokenCount, 0)
    XCTAssertLessThanOrEqual(result.keptTokenCount, ContextTrimmer.defaultLimit)
    XCTAssertEqual(
      result.removedMessageIDs.map(\.rawValue),
      ["old-user", "old-assistant"]
    )
    XCTAssertFalse(
      prepared.request.messages?.contains { $0.content.contains("old context") } == true)
    let events = try await Self.collect(try await engine.generate(prepared.request))
    XCTAssertEqual(events.compactMap(\.metrics).map(\.promptTokenCount), [result.keptTokenCount])
    let after = await engine.debugSnapshot()
    XCTAssertEqual(after, before)
    await engine.unload()
  }

  func testPublicOneBitBoundedReasoningClosesAndProducesFinalAnswer() async throws {
    let engine = MLXInferenceEngine()
    try await engine.load(.init(modelID: .oneBit27B, directory: try Self.modelDirectory(),
                                revision: "public-local-fixture"))
    let budget = 32
    let events = try await Self.collect(try await engine.generate(
      try GenerationRequest(prompt: "Think briefly, then answer with exactly: green",
                            reasoningBudget: budget, maxTokens: 128)
    ))
    let reasoning = events.text(for: .reasoning)
    let answer = events.text(for: .answer)
    print("BoundedReasoningRaw reasoning=\(reasoning) answer=\(answer)")
    XCTAssertFalse(reasoning.isEmpty)
    XCTAssertFalse(answer.isEmpty)
    XCTAssertFalse(answer.contains("</think>"))
    XCTAssertEqual(events.terminalCount, 1)
    let generated = try XCTUnwrap(events.compactMap(\.metrics).last?.generatedTokenCount)
    XCTAssertGreaterThan(generated, budget, "generation continued after the forced reasoning close")
    print("BoundedReasoning budget=\(budget) totalGenerated=\(generated) answer=\(answer)")
    await engine.unload()
  }

  func testPublicOneBitReasoningCancellationAndReloadCycles() async throws {
    let modelDirectory = try Self.modelDirectory()
    let installation = ModelInstallation(
      modelID: .oneBit27B,
      directory: modelDirectory,
      revision: "public-local-fixture"
    )
    let engine = MLXInferenceEngine()
    let clock = ContinuousClock()

    let loadStarted = clock.now
    try await engine.load(installation)
    let loadDuration = loadStarted.duration(to: clock.now)

    try await Self.verifyReasoningOn(engine)
    try await Self.verifyReasoningOff(engine)
    let cancellationDuration = try await Self.verifyCancellation(engine, clock: clock)
    await Self.verifyUnload(engine)
    let cycleDurations = try await Self.verifyReloadCycles(engine, installation: installation)

    print("MLXInference model-load=\(loadDuration)")
    print("MLXInference cancellation=\(cancellationDuration)")
    print("MLXInference cycles=\(cycleDurations)")
  }

  private static func verifyReasoningOn(_ engine: MLXInferenceEngine) async throws {
    let events = try await collect(
      try await engine.generate(
        try GenerationRequest(
          prompt: "Think briefly, then answer with exactly: green",
          reasoningBudget: 32,
          maxTokens: 256
        )
      )
    )
    let reasoning = events.text(for: .reasoning)
    let reasoningAnswer = events.text(for: .answer)
    XCTAssertFalse(reasoning.isEmpty)
    XCTAssertFalse(reasoningAnswer.isEmpty)
    XCTAssertFalse(reasoning.contains("<think>"))
    XCTAssertFalse(reasoningAnswer.contains("</think>"))
    XCTAssertEqual(events.terminalCount, 1)
    printMetrics(label: "reasoning-on", events: events)
  }

  private static func verifyReasoningOff(_ engine: MLXInferenceEngine) async throws {
    let events = try await collect(
      try await engine.generate(
        try GenerationRequest(
          prompt: "Reply with exactly: blue",
          reasoningEnabled: false,
          maxTokens: 64
        )
      )
    )
    XCTAssertTrue(events.text(for: .reasoning).isEmpty)
    let answer = events.text(for: .answer)
    XCTAssertFalse(answer.isEmpty)
    XCTAssertFalse(answer.contains("<think>"))
    XCTAssertFalse(answer.contains("</think>"))
    XCTAssertEqual(events.terminalCount, 1)
    printMetrics(label: "reasoning-off", events: events)
  }

  private static func verifyCancellation(
    _ engine: MLXInferenceEngine,
    clock: ContinuousClock
  ) async throws -> Duration {
    let cancellationStream = try await engine.generate(
      try GenerationRequest(
        prompt: "Write a detailed 100-section field guide to botany.",
        reasoningEnabled: true,
        maxTokens: 4_096
      )
    )
    var iterator = cancellationStream.makeAsyncIterator()
    var cancellationEvents: [GenerationEvent] = []
    var sawDecodedPayload = false
    while let event = try await iterator.next() {
      cancellationEvents.append(event)
      if event.isDecodedPayload {
        sawDecodedPayload = true
        break
      }
    }
    XCTAssertTrue(sawDecodedPayload)

    let cancellationStarted = clock.now
    await engine.cancel()
    while let event = try await iterator.next() { cancellationEvents.append(event) }
    let cancellationDuration = cancellationStarted.duration(to: clock.now)
    XCTAssertEqual(cancellationEvents.terminalReasons, [.cancelled])
    XCTAssertEqual(cancellationEvents.last?.terminalReason, .cancelled)
    XCTAssertLessThan(cancellationDuration, .seconds(30))
    let snapshot = await engine.debugSnapshot()
    XCTAssertEqual(
      snapshot,
      .init(
        loadedModelID: .oneBit27B,
        hasContainer: true,
        hasSession: true,
        hasActiveGeneration: false,
        hasActiveLoad: false
      )
    )
    return cancellationDuration
  }

  private static func verifyUnload(_ engine: MLXInferenceEngine) async {
    await engine.unload()
    let unloadedSnapshot = await engine.debugSnapshot()
    XCTAssertEqual(
      unloadedSnapshot,
      .init(
        loadedModelID: nil,
        hasContainer: false,
        hasSession: false,
        hasActiveGeneration: false,
        hasActiveLoad: false
      )
    )
  }

  private static func verifyReloadCycles(
    _ engine: MLXInferenceEngine,
    installation: ModelInstallation
  ) async throws -> [Duration] {
    let clock = ContinuousClock()
    var cycleDurations: [Duration] = []
    for cycle in 1...3 {
      let cycleStarted = clock.now
      try await engine.load(installation)
      let events = try await Self.collect(
        try await engine.generate(
          try GenerationRequest(
            prompt: "Reply OK",
            reasoningEnabled: false,
            maxTokens: 16
          )
        )
      )
      XCTAssertFalse(events.text(for: .answer).isEmpty, "cycle \(cycle)")
      await engine.unload()
      let snapshot = await engine.debugSnapshot()
      XCTAssertFalse(snapshot.hasContainer, "cycle \(cycle)")
      XCTAssertFalse(snapshot.hasSession, "cycle \(cycle)")
      XCTAssertFalse(snapshot.hasActiveGeneration, "cycle \(cycle)")
      XCTAssertFalse(snapshot.hasActiveLoad, "cycle \(cycle)")
      cycleDurations.append(cycleStarted.duration(to: clock.now))
    }
    return cycleDurations
  }

  private static func modelDirectory() throws -> URL {
    guard let path = ProcessInfo.processInfo.environment["BONSAI_MODEL_DIR"],
      !path.isEmpty
    else {
      throw XCTSkip("Set BONSAI_MODEL_DIR to the public 1-bit Bonsai-27B MLX directory.")
    }
    let directory = URL(fileURLWithPath: path, isDirectory: true)
    guard
      FileManager.default.fileExists(
        atPath: directory.appending(path: "model.safetensors").path
      )
    else {
      XCTFail("BONSAI_MODEL_DIR does not contain model.safetensors")
      throw MLXInferenceError.modelDirectoryMissing
    }
    return directory
  }

  private static func contextConversation() throws -> Conversation {
    try Conversation(
      id: ConversationID("real-context"),
      modelID: .oneBit27B,
      modelRevision: String(repeating: "a", count: 40),
      revision: 1,
      systemInstruction: .init(
        id: MessageID("system"),
        role: .system,
        content: "You are Bonsai."
      ),
      completedTurns: [
        .init(
          id: "old",
          messages: [
            .init(
              id: MessageID("old-user"),
              role: .user,
              content: String(repeating: "old context ", count: 6_000)
            ),
            .init(
              id: MessageID("old-assistant"),
              role: .assistant,
              content: "old answer"
            )
          ]),
        .init(
          id: "new",
          messages: [
            .init(
              id: MessageID("new-user"),
              role: .user,
              content: "What stays?"
            ),
            .init(
              id: MessageID("new-assistant"),
              role: .assistant,
              content: "The newest complete turn."
            )
          ])
      ]
    )
  }

  private static func collect(
    _ stream: AsyncThrowingStream<GenerationEvent, any Error>
  ) async throws -> [GenerationEvent] {
    var events: [GenerationEvent] = []
    for try await event in stream { events.append(event) }
    return events
  }

  private static func printMetrics(label: String, events: [GenerationEvent]) {
    for event in events {
      if case .metrics(let metrics) = event {
        print(
          "MLXInference \(label) ttft=\(metrics.timeToFirstToken) "
            + "generated=\(metrics.generatedTokenCount) "
            + "tokens-per-second=\(metrics.tokensPerSecond)"
        )
      }
    }
  }
}

private enum TextEventKind { case reasoning, answer }

extension Array where Element == GenerationEvent {
  fileprivate func text(for kind: TextEventKind) -> String {
    compactMap { event in
      switch (kind, event) {
      case (.reasoning, .reasoning(let text)), (.answer, .answer(let text)): text
      default: nil
      }
    }.joined()
  }

  fileprivate var terminalReasons: [CompletionReason] {
    compactMap { event in
      if case .completed(let reason) = event { reason } else { nil }
    }
  }

  fileprivate var terminalCount: Int { terminalReasons.count }
}

extension GenerationEvent {
  fileprivate var metrics: GenerationMetrics? {
    if case .metrics(let metrics) = self { metrics } else { nil }
  }

  fileprivate var isDecodedPayload: Bool {
    switch self {
    case .reasoning, .answer, .toolRequest: true
    case .metrics, .completed: false
    }
  }

  fileprivate var terminalReason: CompletionReason? {
    if case .completed(let reason) = self { reason } else { nil }
  }
}
