import Foundation
import Testing

@testable import BonsaiMobile

@Suite("Bounded offline agent loop")
struct AgentLoopTests {
  @Test func denialIsCorrelatedAndDoesNotExecuteWrite() async throws {
    let invocation = ToolInvocation(
      id: "write-1", name: "local_notes",
      argumentsJSON: "{\"action\":\"create\",\"title\":\"Secret\",\"body\":\"Local\"}")
    let engine = ScriptedAgentEngine(
      initial: [.toolRequest(invocation), .completed(.toolRequest)],
      continuations: [[.answer("denied handled"), .completed(.stop)]])
    let gate = RecordingGate(decision: .deny)
    let notes = try NotesStore(root: temporaryDirectory())
    let loop = AgentLoop(engine: engine, registry: try .live(notes: notes), approvals: gate)

    let result = try await loop.run(try GenerationRequest(prompt: "write", reasoningEnabled: false))

    #expect(result.completion == .stop)
    #expect(
      result.toolResults == [
        .init(invocationID: "write-1", status: .denied, contentJSON: "{\"error\":\"user_denied\"}")
      ])
    #expect(try await notes.list().isEmpty)
    #expect(await gate.effects == ["Create note titled ‘Secret’ with body ‘Local’"])
  }

  @Test func seventhToolTurnStopsBeforeExecution() async throws {
    let calls = (1...7).map {
      ToolInvocation(
        id: "call-\($0)", name: "calculator", argumentsJSON: "{\"expression\":\"1+1\"}")
    }
    let engine = ScriptedAgentEngine(
      initial: [.toolRequest(calls[0]), .completed(.toolRequest)],
      continuations: calls.dropFirst().map { [.toolRequest($0), .completed(.toolRequest)] }
    )
    let notes = try NotesStore(root: temporaryDirectory())
    let loop = AgentLoop(
      engine: engine, registry: try .live(notes: notes), approvals: AllowingApprovalGate())

    let result = try await loop.run(try GenerationRequest(prompt: "loop", reasoningEnabled: false))

    #expect(result.completion == .toolTurnLimit(6))
    #expect(result.toolResults.count == 6)
    #expect(await engine.continuationCount == 6)
  }

  @Test func duplicateInvocationIDBecomesTypedTerminalBeforeSecondExecution() async throws {
    let call = ToolInvocation(
      id: "same", name: "calculator", argumentsJSON: "{\"expression\":\"2+2\"}")
    let engine = ScriptedAgentEngine(
      initial: [.toolRequest(call), .completed(.toolRequest)],
      continuations: [[.toolRequest(call), .completed(.toolRequest)]])
    let notes = try NotesStore(root: temporaryDirectory())
    let loop = AgentLoop(
      engine: engine, registry: try .live(notes: notes), approvals: AllowingApprovalGate())
    let result = try await loop.run(try GenerationRequest(prompt: "loop", reasoningEnabled: false))
    #expect(result.completion == .duplicateInvocationID("same"))
    #expect(result.toolResults.count == 1)
  }

  @Test func unknownAndMalformedToolsReturnOrderedModelVisibleErrors() async throws {
    let calls = [
      ToolInvocation(id: "unknown", name: "shell", argumentsJSON: "{}"),
      ToolInvocation(id: "bad", name: "calculator", argumentsJSON: "{\"expression\":4}")
    ]
    let engine = ScriptedAgentEngine(
      initial: calls.map(GenerationEvent.toolRequest) + [.completed(.toolRequest)],
      continuations: [[.answer("handled"), .completed(.stop)]]
    )
    let notes = try NotesStore(root: temporaryDirectory())
    let result = try await AgentLoop(
      engine: engine, registry: try .live(notes: notes)
    ).run(try GenerationRequest(prompt: "unsafe", reasoningEnabled: false))
    #expect(result.toolResults.map(\.invocationID) == ["unknown", "bad"])
    #expect(result.toolResults.allSatisfy { $0.status == .failed })
    #expect(result.answer == "handled")
  }

  @Test func mlxContinuationPromptPreservesCorrelationAndRejectsMismatch() throws {
    let call = ToolInvocation(
      id: "call-7", name: "calculator", argumentsJSON: "{\"expression\":\"2+2\"}")
    let result = AgentToolResult(
      invocationID: "call-7", status: .succeeded, contentJSON: "{\"result\":4}")
    let prompt = try MLXPromptComposer.toolContinuationPrompt(
      .init(invocations: [call], results: [result])
    )
    #expect(prompt.contains("\"invocation_id\":\"call-7\""))
    #expect(prompt.contains("\"tool_name\":\"calculator\""))
    #expect(prompt.contains("<tool_response>"))
    #expect(throws: MLXInferenceError.invalidToolArgumentsEncoding) {
      try MLXPromptComposer.toolContinuationPrompt(
        .init(
          invocations: [call],
          results: [.init(invocationID: "wrong", status: .succeeded, contentJSON: "{}")]
        ))
    }
  }

  @Test func invalidSchemaNeverRequestsApprovalOrExecutes() async throws {
    let call = ToolInvocation(
      id: "invalid-note", name: "local_notes",
      argumentsJSON: "{\"action\":\"create\",\"title\":\"x\",\"body\":\"y\",\"extra\":true}")
    let engine = ScriptedAgentEngine(
      initial: [.toolRequest(call), .completed(.toolRequest)],
      continuations: [[.answer("invalid handled"), .completed(.stop)]])
    let gate = RecordingGate(decision: .allowOnce)
    let notes = try NotesStore(root: temporaryDirectory())
    let result = try await AgentLoop(
      engine: engine, registry: try .live(notes: notes), approvals: gate
    ).run(try GenerationRequest(prompt: "invalid", reasoningEnabled: false))
    #expect(result.toolResults.first?.status == .failed)
    #expect(await gate.effects.isEmpty)
    #expect(try await notes.list().isEmpty)
  }

  @Test func multipleToolsExecuteAndContinueInRequestOrder() async throws {
    let calls = [
      ToolInvocation(id: "first", name: "calculator", argumentsJSON: "{\"expression\":\"2+2\"}"),
      ToolInvocation(id: "second", name: "calculator", argumentsJSON: "{\"expression\":\"3+3\"}")
    ]
    let engine = ScriptedAgentEngine(
      initial: calls.map(GenerationEvent.toolRequest) + [.completed(.toolRequest)],
      continuations: [[.answer("done"), .completed(.stop)]])
    let notes = try NotesStore(root: temporaryDirectory())
    let result = try await AgentLoop(engine: engine, registry: try .live(notes: notes))
      .run(try GenerationRequest(prompt: "two", reasoningEnabled: false))
    #expect(result.toolResults.map(\.invocationID) == ["first", "second"])
    #expect(result.toolResults.map(\.contentJSON) == ["{\"result\":4}", "{\"result\":6}"])
    #expect(await engine.exchanges.first?.invocations.map(\.id) == ["first", "second"])
  }

  @Test func cancelInterruptsPendingApprovalAndPublishesCancelledTerminal() async throws {
    let call = ToolInvocation(
      id: "pending", name: "local_notes",
      argumentsJSON: "{\"action\":\"create\",\"title\":\"x\",\"body\":\"y\"}")
    let engine = ScriptedAgentEngine(
      initial: [.toolRequest(call), .completed(.toolRequest)], continuations: [])
    let gate = SuspendingApprovalGate()
    let notes = try NotesStore(root: temporaryDirectory())
    let loop = AgentLoop(engine: engine, registry: try .live(notes: notes), approvals: gate)
    let run = Task { try await loop.run(try GenerationRequest(prompt: "cancel", reasoningEnabled: false)) }
    await gate.waitUntilPending()

    await loop.cancel()
    #expect(await gate.cancellationCount == 1)
    await gate.releaseDeniedIfNeeded()
    let result = try await run.value
    #expect(result.completion == .cancelled)
    #expect(result.activities.last == .terminal(.cancelled))
    #expect(try await notes.list().isEmpty)
  }

  @Test func cancelInterruptsGenerationAndToolExecution() async throws {
    let generationEngine = SuspendingGenerationEngine()
    let notes = try NotesStore(root: temporaryDirectory())
    let generationLoop = AgentLoop(
      engine: generationEngine, registry: try .live(notes: notes))
    let generationRun = Task {
      try await generationLoop.run(
        try GenerationRequest(prompt: "wait", reasoningEnabled: false))
    }
    await generationEngine.waitUntilGenerating()
    await generationLoop.cancel()
    let generationResult = try await generationRun.value
    #expect(generationResult.completion == .cancelled)
    #expect(await generationEngine.cancellationCount == 1)

    let tool = SuspendingTool()
    let call = ToolInvocation(id: "slow", name: "slow_tool", argumentsJSON: "{}")
    let toolEngine = ScriptedAgentEngine(
      initial: [.toolRequest(call), .completed(.toolRequest)], continuations: [])
    let toolLoop = AgentLoop(engine: toolEngine, registry: try ToolRegistry([tool]))
    let toolRun = Task {
      try await toolLoop.run(try GenerationRequest(prompt: "tool", reasoningEnabled: false))
    }
    await tool.waitUntilRunning()
    await toolLoop.cancel()
    #expect(try await toolRun.value.completion == .cancelled)
    #expect(await tool.cancellationCount == 1)
  }

  @Test func oversizedNotesListBecomesSmallModelVisibleFailure() async throws {
    let notes = try NotesStore(root: temporaryDirectory())
    for index in 0...ToolJSON.maximumContainerCount {
      _ = try await notes.create(title: "note-\(index)", body: "body")
    }
    let call = ToolInvocation(
      id: "list", name: "local_notes", argumentsJSON: "{\"action\":\"list\"}")
    let engine = ScriptedAgentEngine(
      initial: [.toolRequest(call), .completed(.toolRequest)],
      continuations: [[.answer("bounded"), .completed(.stop)]])
    let result = try await AgentLoop(engine: engine, registry: try .live(notes: notes))
      .run(try GenerationRequest(prompt: "list", reasoningEnabled: false))
    #expect(result.toolResults.first?.status == .failed)
    #expect((result.toolResults.first?.contentJSON.utf8.count ?? .max) < 1_024)
    #expect(result.activities.contains { activity in
      if case .result(let value) = activity { return value.status == .failed }
      return false
    })
  }

  private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "AgentLoopTests-\(UUID())")
  }
}

private actor RecordingGate: ToolApprovalGate {
  let decision: ToolApprovalDecision
  private(set) var effects: [String] = []
  init(decision: ToolApprovalDecision) { self.decision = decision }
  func requestAllowOnce(_ request: ToolApprovalRequest) async throws -> ToolApprovalDecision {
    effects.append(request.effect)
    return decision
  }
}

private actor SuspendingApprovalGate: ToolApprovalGate {
  private var continuation: CheckedContinuation<ToolApprovalDecision, any Error>?
  private var waiters: [CheckedContinuation<Void, Never>] = []
  private(set) var cancellationCount = 0

  func requestAllowOnce(_ request: ToolApprovalRequest) async throws -> ToolApprovalDecision {
    waiters.forEach { $0.resume() }
    waiters.removeAll()
    return try await withCheckedThrowingContinuation { continuation = $0 }
  }

  func waitUntilPending() async {
    if continuation != nil { return }
    await withCheckedContinuation { waiters.append($0) }
  }

  func cancelPending() {
    cancellationCount += 1
    continuation?.resume(throwing: CancellationError())
    continuation = nil
  }

  func releaseDeniedIfNeeded() {
    continuation?.resume(returning: .deny)
    continuation = nil
  }
}

private actor SuspendingTool: OfflineTool {
  nonisolated let schema = OfflineToolSchema(
    name: "slow_tool", description: "Wait until cancelled.",
    parametersJSON: "{\"additionalProperties\":false,\"properties\":{},\"type\":\"object\"}")
  private var continuation: CheckedContinuation<ToolJSON, any Error>?
  private var waiters: [CheckedContinuation<Void, Never>] = []
  private(set) var cancellationCount = 0

  nonisolated func validate(arguments: ToolJSON) throws {
    guard try arguments.object().isEmpty else { throw ToolBoundaryError.invalid("arguments") }
  }
  func execute(arguments: ToolJSON) async throws -> ToolJSON {
    waiters.forEach { $0.resume() }
    waiters.removeAll()
    return try await withCheckedThrowingContinuation { continuation = $0 }
  }
  func waitUntilRunning() async {
    if continuation != nil { return }
    await withCheckedContinuation { waiters.append($0) }
  }
  func cancel() {
    cancellationCount += 1
    continuation?.resume(throwing: CancellationError())
    continuation = nil
  }
}

private actor SuspendingGenerationEngine: AgentInferenceStreaming {
  private var continuation: AsyncThrowingStream<GenerationEvent, any Error>.Continuation?
  private var waiters: [CheckedContinuation<Void, Never>] = []
  private(set) var cancellationCount = 0
  func generate(_ request: GenerationRequest) async throws -> AsyncThrowingStream<GenerationEvent, any Error> {
    let pair = AsyncThrowingStream<GenerationEvent, any Error>.makeStream()
    continuation = pair.continuation
    waiters.forEach { $0.resume() }
    waiters.removeAll()
    return pair.stream
  }
  func continueAfterTools(
    _ exchange: AgentToolExchange
  ) async throws -> AsyncThrowingStream<GenerationEvent, any Error> {
    throw CancellationError()
  }
  func waitUntilGenerating() async {
    if continuation != nil { return }
    await withCheckedContinuation { waiters.append($0) }
  }
  func cancel() {
    cancellationCount += 1
    continuation?.yield(.completed(.cancelled))
    continuation?.finish()
    continuation = nil
  }
}

private actor ScriptedAgentEngine: AgentInferenceStreaming {
  private let initial: [GenerationEvent]
  private var continuations: [[GenerationEvent]]
  private(set) var continuationCount = 0
  private(set) var exchanges: [AgentToolExchange] = []
  init(initial: [GenerationEvent], continuations: [[GenerationEvent]]) {
    self.initial = initial
    self.continuations = continuations
  }
  func generate(_ request: GenerationRequest) async throws -> AsyncThrowingStream<
    GenerationEvent, any Error
  > {
    Self.stream(initial)
  }
  func continueAfterTools(_ exchange: AgentToolExchange) async throws -> AsyncThrowingStream<
    GenerationEvent, any Error
  > {
    continuationCount += 1
    exchanges.append(exchange)
    return Self.stream(continuations.removeFirst())
  }
  func cancel() async {}
  private static func stream(_ events: [GenerationEvent]) -> AsyncThrowingStream<
    GenerationEvent, any Error
  > {
    let (stream, continuation) = AsyncThrowingStream<GenerationEvent, any Error>.makeStream()
    events.forEach { continuation.yield($0) }
    continuation.finish()
    return stream
  }
}
