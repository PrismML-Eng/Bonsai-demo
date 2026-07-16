import Foundation

enum ToolApprovalDecision: Equatable, Sendable { case allowOnce, deny }

struct ToolApprovalRequest: Equatable, Sendable {
  let invocation: ToolInvocation
  let effect: String
}

protocol ToolApprovalGate: Sendable {
  func requestAllowOnce(_ request: ToolApprovalRequest) async throws -> ToolApprovalDecision
  func cancelPending() async
}

extension ToolApprovalGate {
  func cancelPending() async {}
}

struct AllowingApprovalGate: ToolApprovalGate {
  func requestAllowOnce(_ request: ToolApprovalRequest) async throws -> ToolApprovalDecision {
    .allowOnce
  }
}

enum AgentToolResultStatus: String, Equatable, Sendable { case succeeded, denied, failed }

struct AgentToolResult: Equatable, Sendable {
  let invocationID: String
  let status: AgentToolResultStatus
  let contentJSON: String
}

struct AgentToolExchange: Equatable, Sendable {
  let invocations: [ToolInvocation]
  let results: [AgentToolResult]
}

protocol AgentInferenceStreaming: Sendable {
  func generate(_ request: GenerationRequest) async throws
    -> AsyncThrowingStream<GenerationEvent, any Error>
  func continueAfterTools(_ exchange: AgentToolExchange) async throws
    -> AsyncThrowingStream<GenerationEvent, any Error>
  func cancel() async
}

enum AgentCompletion: Equatable, Sendable {
  case stop
  case length
  case cancelled
  case toolTurnLimit(Int)
  case duplicateInvocationID(String)
  case runtimeFailure(String)
}

private enum AgentStreamProtocolError: Error, CustomStringConvertible {
  case missingCompletion
  case duplicateCompletion

  var description: String {
    switch self {
    case .missingCompletion: "missing_generation_completion"
    case .duplicateCompletion: "duplicate_generation_completion"
    }
  }
}

enum AgentActivity: Equatable, Sendable {
  case generating
  case pendingApproval(ToolApprovalRequest)
  case running(ToolInvocation)
  case result(AgentToolResult)
  case terminal(AgentCompletion)
}

enum AgentLiveEvent: Equatable, Sendable {
  case reasoning(String)
  case answer(String)
  case metrics(GenerationMetrics)
  case toolRequest(ToolInvocation)
  case activity(AgentActivity)
  case completed(AgentCompletion)
}

struct AgentRunResult: Equatable, Sendable {
  let answer: String
  let reasoning: String
  let toolResults: [AgentToolResult]
  let activities: [AgentActivity]
  let completion: AgentCompletion
}

actor AgentLoop {
  static let maximumToolTurns = 6
  private let engine: any AgentInferenceStreaming
  private let registry: ToolRegistry
  private let approvals: any ToolApprovalGate
  private var currentActivities: [AgentActivity] = []
  private var activeRun: (id: UUID, task: Task<AgentRunResult, Never>)?
  private var activeTool: (any OfflineTool)?
  private var eventObservers: [UUID: AsyncStream<AgentLiveEvent>.Continuation] = [:]

  init(
    engine: any AgentInferenceStreaming,
    registry: ToolRegistry,
    approvals: any ToolApprovalGate = AllowingApprovalGate()
  ) {
    self.engine = engine
    self.registry = registry
    self.approvals = approvals
  }

  func activities() -> [AgentActivity] { currentActivities }
  func toolSpecifications() -> [GenerationToolSpecification] { registry.specifications }

  func events() -> AsyncStream<AgentLiveEvent> {
    let id = UUID()
    return AsyncStream { continuation in
      eventObservers[id] = continuation
      continuation.onTermination = { [weak self] _ in
        Task { await self?.removeEventObserver(id) }
      }
    }
  }

  func run(_ request: GenerationRequest) async throws -> AgentRunResult {
    guard activeRun == nil else {
      let completion = AgentCompletion.runtimeFailure("agent_run_already_active")
      return AgentRunResult(
        answer: "", reasoning: "", toolResults: [], activities: [.terminal(completion)], completion: completion
      )
    }
    let runID = UUID()
    let task = Task { [weak self] in
      guard let self else {
        return AgentRunResult(
          answer: "", reasoning: "", toolResults: [], activities: [.terminal(.cancelled)], completion: .cancelled)
      }
      return await self.performRun(request.replacingTools(self.registry.specifications))
    }
    activeRun = (runID, task)
    let result = await task.value
    if activeRun?.id == runID { activeRun = nil }
    activeTool = nil
    return result
  }

  private func performRun(_ request: GenerationRequest) async -> AgentRunResult {
    currentActivities = []
    appendActivity(.generating)
    var answer = ""
    var reasoning = ""
    var results: [AgentToolResult] = []
    var seenIDs: Set<String> = []
    var toolTurns = 0
    do {
      var stream = try await engine.generate(request)
      while true {
        let batch = try await consume(stream, answer: &answer, reasoning: &reasoning)
        switch batch.completion {
        case .stop:
          return finish(.stop, answer: answer, reasoning: reasoning, results: results)
        case .length:
          return finish(.length, answer: answer, reasoning: reasoning, results: results)
        case .cancelled:
          return finish(.cancelled, answer: answer, reasoning: reasoning, results: results)
        case .toolRequest:
          guard toolTurns < Self.maximumToolTurns else {
            return finish(
              .toolTurnLimit(Self.maximumToolTurns), answer: answer, reasoning: reasoning, results: results
            )
          }
          toolTurns += 1
          var exchangeResults: [AgentToolResult] = []
          for invocation in batch.invocations {
            try Task.checkCancellation()
            guard seenIDs.insert(invocation.id).inserted else {
              return finish(
                .duplicateInvocationID(invocation.id), answer: answer, reasoning: reasoning, results: results
              )
            }
            let result = try await execute(invocation)
            results.append(result)
            exchangeResults.append(result)
            appendActivity(.result(result))
          }
          stream = try await engine.continueAfterTools(
            AgentToolExchange(invocations: batch.invocations, results: exchangeResults)
          )
          appendActivity(.generating)
        }
      }
    } catch is CancellationError {
      return finish(.cancelled, answer: answer, reasoning: reasoning, results: results)
    } catch {
      return finish(.runtimeFailure(String(describing: error)), answer: answer,
                    reasoning: reasoning, results: results)
    }
  }

  func cancel() async {
    activeRun?.task.cancel()
    await approvals.cancelPending()
    await activeTool?.cancel()
    await engine.cancel()
  }

  private func execute(_ invocation: ToolInvocation) async throws -> AgentToolResult {
    do {
      let (tool, arguments) = try registry.resolve(invocation)
      activeTool = tool
      defer { activeTool = nil }
      if try tool.approval(for: arguments) == .requireAllowOnce {
        let request = ToolApprovalRequest(
          invocation: invocation, effect: try tool.effect(for: arguments)
        )
        appendActivity(.pendingApproval(request))
        guard try await approvals.requestAllowOnce(request) == .allowOnce else {
          return AgentToolResult(
            invocationID: invocation.id,
            status: .denied,
            contentJSON: "{\"error\":\"user_denied\"}"
          )
        }
      }
      try Task.checkCancellation()
      appendActivity(.running(invocation))
            let value = try await tool.execute(arguments: arguments)
            try Task.checkCancellation()
            return AgentToolResult(
                invocationID: invocation.id,
                status: .succeeded,
                contentJSON: try value.boundedJSONString()
            )
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      return AgentToolResult(
        invocationID: invocation.id,
        status: .failed,
        contentJSON: Self.errorJSON(error)
      )
    }
  }

  private func consume(
    _ stream: AsyncThrowingStream<GenerationEvent, any Error>,
    answer: inout String,
    reasoning: inout String
  ) async throws -> (invocations: [ToolInvocation], completion: CompletionReason) {
    var invocations: [ToolInvocation] = []
    var completion: CompletionReason?
    for try await event in stream {
      try Task.checkCancellation()
      switch event {
      case .answer(let text):
        answer += text
        publish(.answer(text))
      case .toolRequest(let invocation):
        invocations.append(invocation)
        publish(.toolRequest(invocation))
      case .completed(let reason):
        guard completion == nil else { throw AgentStreamProtocolError.duplicateCompletion }
        completion = reason
      case .reasoning(let text): reasoning += text; publish(.reasoning(text))
      case .metrics(let metrics): publish(.metrics(metrics))
      }
    }
    try Task.checkCancellation()
    guard let completion else { throw AgentStreamProtocolError.missingCompletion }
    return (invocations, completion)
  }

  private func finish(
    _ completion: AgentCompletion,
    answer: String,
    reasoning: String,
    results: [AgentToolResult]
  ) -> AgentRunResult {
    appendActivity(.terminal(completion))
    publish(.completed(completion))
    return AgentRunResult(
      answer: answer,
      reasoning: reasoning,
      toolResults: results,
      activities: currentActivities,
      completion: completion
    )
  }

  private func appendActivity(_ activity: AgentActivity) {
    currentActivities.append(activity)
    publish(.activity(activity))
  }

  private func publish(_ event: AgentLiveEvent) {
    eventObservers.values.forEach { $0.yield(event) }
  }

  private func removeEventObserver(_ id: UUID) { eventObservers.removeValue(forKey: id) }

  private static func errorJSON(_ error: any Error) -> String {
    let message: String
    switch error {
    case let error as ToolBoundaryError: message = String(describing: error)
    case let error as CalculatorError: message = String(describing: error)
    case let error as NotesStoreError: message = String(describing: error)
    default: message = "tool_execution_failed"
    }
    let data = try? JSONEncoder().encode(["error": message])
    return String(data: data ?? Data(), encoding: .utf8)
      ?? "{\"error\":\"tool_execution_failed\"}"
  }
}
