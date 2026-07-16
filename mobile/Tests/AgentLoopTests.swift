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

private actor ScriptedAgentEngine: AgentInferenceStreaming {
  private let initial: [GenerationEvent]
  private var continuations: [[GenerationEvent]]
  private(set) var continuationCount = 0
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
