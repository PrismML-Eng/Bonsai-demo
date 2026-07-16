import Foundation
import Testing

@testable import BonsaiMobile

@Suite("Offline agent protocol boundaries")
struct AgentLoopProtocolTests {
  @Test func registrySpecificationsOverrideEveryCallerToolList() async throws {
    let notes = try NotesStore(root: temporaryDirectory())
    let registry = try ToolRegistry.live(notes: notes)
    let injected = GenerationToolSpecification(
      name: "shell", description: "Run arbitrary commands.", parametersJSON: "{}")
    let redefined = GenerationToolSpecification(
      name: "calculator", description: "Not the compiled calculator.", parametersJSON: "{}")
    let requests = [
      try GenerationRequest(prompt: "empty", reasoningEnabled: false),
      try GenerationRequest(
        messages: [.init(id: MessageID("extra"), role: .user, content: "extra")],
        tools: [injected], reasoningEnabled: false),
      try GenerationRequest(
        messages: [.init(id: MessageID("redefined"), role: .user, content: "redefined")],
        tools: [redefined], reasoningEnabled: false)
    ]

    for request in requests {
      let engine = ProtocolRecordingEngine(events: [.completed(.stop)])
      let result = try await AgentLoop(engine: engine, registry: registry).run(request)

      #expect(result.completion == .stop)
      let observed = await engine.requests.first
      #expect(observed?.tools == registry.specifications)
      #expect(observed?.prompt == request.prompt)
      #expect(observed?.messages == request.messages)
      #expect(observed?.reasoningEnabled == request.reasoningEnabled)
      #expect(observed?.maxTokens == request.maxTokens)
    }
  }

  @Test func rejectedOverlappingRunDoesNotMutateOrBorrowActiveRunActivities() async throws {
    let engine = OverlappingRunEngine()
    let notes = try NotesStore(root: temporaryDirectory())
    let loop = AgentLoop(engine: engine, registry: try .live(notes: notes))
    let first = Task {
      try await loop.run(try GenerationRequest(prompt: "first", reasoningEnabled: false))
    }
    await engine.waitUntilGenerating()

    let rejected = try await loop.run(
      try GenerationRequest(prompt: "second", reasoningEnabled: false))

    #expect(rejected.completion == .runtimeFailure("agent_run_already_active"))
    #expect(rejected.activities == [.terminal(.runtimeFailure("agent_run_already_active"))])
    #expect(await loop.activities() == [.generating])
    await engine.finishNormally()
    let completed = try await first.value
    #expect(completed.completion == .stop)
    #expect(completed.activities == [.generating, .terminal(.stop)])
  }

  @Test func emptyGenerationStreamIsRuntimeFailure() async throws {
    let engine = ProtocolRecordingEngine(events: [])
    let notes = try NotesStore(root: temporaryDirectory())

    let result = try await AgentLoop(engine: engine, registry: try .live(notes: notes))
      .run(try GenerationRequest(prompt: "empty", reasoningEnabled: false))

    #expect(result.completion == .runtimeFailure("missing_generation_completion"))
    #expect(result.activities.last == .terminal(.runtimeFailure("missing_generation_completion")))
  }

  @Test func answerWithoutCompletionIsRuntimeFailure() async throws {
    let engine = ProtocolRecordingEngine(events: [.answer("partial")])
    let notes = try NotesStore(root: temporaryDirectory())

    let result = try await AgentLoop(engine: engine, registry: try .live(notes: notes))
      .run(try GenerationRequest(prompt: "partial", reasoningEnabled: false))

    #expect(result.answer == "partial")
    #expect(result.completion == .runtimeFailure("missing_generation_completion"))
  }

  @Test func duplicateGenerationCompletionIsRuntimeFailure() async throws {
    let engine = ProtocolRecordingEngine(events: [.completed(.stop), .completed(.stop)])
    let notes = try NotesStore(root: temporaryDirectory())

    let result = try await AgentLoop(engine: engine, registry: try .live(notes: notes))
      .run(try GenerationRequest(prompt: "duplicate", reasoningEnabled: false))

    #expect(result.completion == .runtimeFailure("duplicate_generation_completion"))
  }

  private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "AgentProtocolTests-\(UUID())")
  }
}

private actor ProtocolRecordingEngine: AgentInferenceStreaming {
  let events: [GenerationEvent]
  private(set) var requests: [GenerationRequest] = []

  init(events: [GenerationEvent]) { self.events = events }

  func generate(_ request: GenerationRequest) -> AsyncThrowingStream<GenerationEvent, any Error> {
    requests.append(request)
    let (stream, continuation) = AsyncThrowingStream<GenerationEvent, any Error>.makeStream()
    events.forEach { continuation.yield($0) }
    continuation.finish()
    return stream
  }

  func continueAfterTools(
    _ exchange: AgentToolExchange
  ) async throws -> AsyncThrowingStream<GenerationEvent, any Error> {
    throw AgentProtocolTestError.unexpectedContinuation
  }

  func cancel() async {}
}

private actor OverlappingRunEngine: AgentInferenceStreaming {
  private var continuation: AsyncThrowingStream<GenerationEvent, any Error>.Continuation?
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func generate(_ request: GenerationRequest) -> AsyncThrowingStream<GenerationEvent, any Error> {
    let pair = AsyncThrowingStream<GenerationEvent, any Error>.makeStream()
    continuation = pair.continuation
    waiters.forEach { $0.resume() }
    waiters.removeAll()
    return pair.stream
  }

  func continueAfterTools(
    _ exchange: AgentToolExchange
  ) async throws -> AsyncThrowingStream<GenerationEvent, any Error> {
    throw AgentProtocolTestError.unexpectedContinuation
  }

  func waitUntilGenerating() async {
    if continuation != nil { return }
    await withCheckedContinuation { waiters.append($0) }
  }

  func finishNormally() {
    continuation?.yield(.completed(.stop))
    continuation?.finish()
    continuation = nil
  }

  func cancel() async {}
}

private enum AgentProtocolTestError: Error { case unexpectedContinuation }
