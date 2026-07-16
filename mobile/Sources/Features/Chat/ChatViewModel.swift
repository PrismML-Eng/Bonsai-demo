import Foundation
import Observation

enum ReasoningEffort: String, CaseIterable, Identifiable, Sendable {
  case off = "Off", low = "Low", medium = "Medium", high = "High", max = "Max"
  var id: String { rawValue }
  var tokenBudget: Int {
    switch self {
    case .off: 0
    case .low: 512
    case .medium: 2_048
    case .high: 8_192
    case .max: -1
    }
  }
}

enum ChatMessageRole: Equatable, Sendable { case user, assistant }

struct ChatMessagePresentation: Identifiable, Equatable, Sendable {
  let id: UUID
  let role: ChatMessageRole
  var text: String
}

struct ReasoningPresentation: Equatable, Sendable {
  var text = ""
  var status = "Not used"
}

struct RecoveryPresentation: Equatable, Sendable { let label: String }

struct ChatSendRequest: Equatable, Sendable {
  let prompt: String
  let effort: ReasoningEffort
}

enum ActivityAction: Equatable, Sendable { case allowOnce(String), deny(String) }
struct ActivityActionPresentation: Equatable, Sendable { let label: String; let action: ActivityAction }

enum AgentActivityKind: Equatable, Sendable {
  case requested, pendingApproval, running, result, denied, failed, terminal
}

struct AgentActivityPresentation: Identifiable, Equatable, Sendable {
  let id: String
  let kind: AgentActivityKind
  let title: String
  let detail: String?
  let actions: [ActivityActionPresentation]

  static func pendingApproval(
    id: String, toolName: String, effect: String, invocation: ToolInvocation
  ) -> Self {
    .init(id: id, kind: .pendingApproval, title: "\(toolName) needs approval", detail: effect,
          actions: [.init(label: "Allow once", action: .allowOnce(invocation.id)),
                    .init(label: "Deny", action: .deny(invocation.id))])
  }
}

enum ChatSessionEvent: Equatable, Sendable {
  case assistantStarted(id: UUID)
  case reasoning(String)
  case answer(String)
  case metrics(GenerationMetrics)
  case activity(AgentActivityPresentation)
  case completed(AgentCompletion)
  case failed(String)
  case contextTrimmed(ContextTrimNotice)
}

protocol ChatSessionServing: Sendable {
  func stream(_ request: ChatSendRequest) async throws
    -> AsyncThrowingStream<ChatSessionEvent, any Error>
  func cancel() async
  func respond(to action: ActivityAction) async
  func history() async throws -> [ChatMessagePresentation]
}

extension ChatSessionServing {
  func respond(to action: ActivityAction) async {}
  func history() async throws -> [ChatMessagePresentation] { [] }
}

@MainActor @Observable
final class ChatViewModel {
  private let service: any ChatSessionServing
  var draft = ""
  var effort: ReasoningEffort = .medium
  private(set) var messages: [ChatMessagePresentation] = []
  private(set) var reasoning = ReasoningPresentation()
  private(set) var metrics: GenerationMetrics?
  private(set) var activities: [AgentActivityPresentation] = []
  private(set) var isGenerating = false
  private(set) var failedPrompt: String?
  private(set) var recovery: RecoveryPresentation?
  private(set) var terminalStatus: String?
  private(set) var contextTrimNotice: String?
  var isModelReady: Bool
  var loadedModelName: String?
  private var generationTask: Task<Void, Never>?
  private var generationID: UUID?

  init(service: any ChatSessionServing, isModelReady: Bool) {
    self.service = service
    self.isModelReady = isModelReady
    loadedModelName = isModelReady ? "Bonsai 27B · 1-bit" : nil
  }

  var canSend: Bool { isModelReady && !isGenerating && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

  func send() async {
    guard canSend else { return }
    let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    draft = ""
    messages.append(.init(id: UUID(), role: .user, text: prompt))
    resetRunState()
    isGenerating = true
    let service = self.service
    let request = ChatSendRequest(prompt: prompt, effort: effort)
    let runID = UUID()
    generationID = runID
    let task = Task { [weak self] in
      do {
        let stream = try await service.stream(request)
        for try await event in stream {
          try Task.checkCancellation()
          self?.consume(event)
        }
      } catch is CancellationError {
        self?.markStopped()
      } catch {
        self?.markFailure(String(describing: error), prompt: prompt)
      }
    }
    generationTask = task
    await task.value
    if generationID == runID {
      generationTask = nil
      generationID = nil
    }
    isGenerating = false
    if terminalStatus == nil { terminalStatus = "Complete" }
  }

  func start() async {
    guard messages.isEmpty else { return }
    if let history = try? await service.history() { messages = history }
  }

  func reloadHistory() async {
    generationTask?.cancel()
    await service.cancel()
    messages = (try? await service.history()) ?? []
    reasoning = .init()
    metrics = nil
    activities = []
    terminalStatus = nil
    contextTrimNotice = nil
  }

  func retry() async {
    guard let failedPrompt else { return }
    draft = failedPrompt
    await send()
  }

  func stop() async {
    generationTask?.cancel()
    await service.cancel()
    markStopped()
    isGenerating = false
  }

  func respond(to action: ActivityAction) async { await service.respond(to: action) }

  func applyFixture(_ state: UIFixtureState) {
    messages = state.messages
    reasoning = state.reasoning
    metrics = state.metrics
    activities = state.activities
    terminalStatus = state.terminalStatus
    contextTrimNotice = state.contextTrimNotice
  }

  private func resetRunState() {
    reasoning = .init(status: effort == .off ? "Off" : "Thinking · \(effort.rawValue)")
    metrics = nil
    activities = []
    failedPrompt = nil
    recovery = nil
    terminalStatus = nil
    contextTrimNotice = nil
  }

  // All stream event variants converge here so presentation updates stay atomic.
  // swiftlint:disable:next cyclomatic_complexity
  private func consume(_ event: ChatSessionEvent) {
    switch event {
    case .assistantStarted(let id):
      if !messages.contains(where: { $0.id == id }) {
        messages.append(.init(id: id, role: .assistant, text: ""))
      }
    case .reasoning(let text): reasoning.text += text
    case .answer(let text):
      if let index = messages.lastIndex(where: { $0.role == .assistant }) {
        messages[index].text += text
      } else {
        messages.append(.init(id: UUID(), role: .assistant, text: text))
      }
    case .metrics(let value): metrics = value
    case .activity(let activity):
      if let index = activities.firstIndex(where: { $0.id == activity.id }) {
        activities[index] = activity
      } else { activities.append(activity) }
    case .completed(let completion):
      terminalStatus = Self.label(completion)
    case .failed(let message): markFailure(message, prompt: messages.last(where: { $0.role == .user })?.text ?? "")
    case .contextTrimmed(let notice):
      contextTrimNotice = "Removed \(notice.removedTurnCount) older turn(s) to fit context."
    }
  }

  private func markStopped() { terminalStatus = "Stopped" }
  private func markFailure(_ message: String, prompt: String) {
    failedPrompt = prompt
    terminalStatus = message
    recovery = .init(label: "Retry send")
  }

  private static func label(_ completion: AgentCompletion) -> String {
    switch completion {
    case .stop: "Complete"
    case .length: "Token limit reached"
    case .cancelled: "Stopped"
    case .toolTurnLimit: "Tool turn limit reached"
    case .duplicateInvocationID: "Tool request rejected"
    case .runtimeFailure(let message): message
    }
  }
}
