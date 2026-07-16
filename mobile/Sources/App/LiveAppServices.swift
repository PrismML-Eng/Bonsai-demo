import Foundation
#if os(iOS)
import UIKit
#endif

enum LiveUIServiceError: Error, LocalizedError {
  case missingManifest(ModelID)
  case modelNotInstalled
  case importRequiresPicker

  var errorDescription: String? {
    switch self {
    case .missingManifest: "The bundled model manifest is unavailable."
    case .modelNotInstalled: "Install and verify this model before loading it."
    case .importRequiresPicker: "Choose Import from a platform file picker."
    }
  }
}

actor LiveModelLibraryService: ModelLibraryServing {
  private let library: ModelLibrary
  private let engine: MLXInferenceEngine
  private let manifests: [ModelID: ModelManifest]
  private var loadedModelID: ModelID?

  init(root: URL, engine: MLXInferenceEngine) throws {
    library = try ModelLibrary(root: root)
    self.engine = engine
    if let url = Bundle.main.url(forResource: "manifest", withExtension: "json", subdirectory: "Models"),
       let catalog = try? JSONDecoder().decode(ModelCatalog.self, from: Data(contentsOf: url)) {
      manifests = Dictionary(uniqueKeysWithValues: catalog.models.map { ($0.id, $0.manifest) })
    } else { manifests = [:] }
  }

  func snapshots() async -> AsyncStream<ModelLibrarySnapshot> { await library.snapshots() }

  func perform(_ intent: ModelLibraryIntent, for modelID: ModelID) async throws {
    guard let manifest = manifests[modelID] else { throw LiveUIServiceError.missingManifest(modelID) }
    switch intent {
    case .download, .retryDownload:
      let qualification = await qualification(for: modelID)
      try await library.install(manifest, qualification: qualification)
    case .verify:
      guard case .ready = await library.state(for: modelID) else {
        throw LiveUIServiceError.modelNotInstalled
      }
    case .importModel:
      throw LiveUIServiceError.importRequiresPicker
    case .load:
      guard case .ready(let installation) = await library.state(for: modelID) else {
        throw LiveUIServiceError.modelNotInstalled
      }
      try await engine.load(installation)
      loadedModelID = modelID
    case .unload:
      await engine.unload()
      loadedModelID = nil
    case .delete:
      if loadedModelID == modelID { await engine.unload(); loadedModelID = nil }
      try await library.delete(modelID)
    }
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

actor AgentLoopChatService: ChatSessionServing {
  private let loop: AgentLoop
  private let approvals: InteractiveApprovalGate

  init(loop: AgentLoop, approvals: InteractiveApprovalGate) {
    self.loop = loop
    self.approvals = approvals
  }

  func stream(_ request: ChatSendRequest) async throws -> AsyncThrowingStream<ChatSessionEvent, any Error> {
    let generation = try GenerationRequest(prompt: request.prompt,
                                           reasoningEnabled: request.effort != .off)
    let liveEvents = await loop.events()
    return AsyncThrowingStream { continuation in
      let task = Task { [loop] in
        let assistantID = UUID()
        continuation.yield(.assistantStarted(id: assistantID))
        let forwardingTask = Task {
          var index = 0
          for await event in liveEvents {
            switch event {
            case .reasoning(let text): continuation.yield(.reasoning(text))
            case .answer(let text): continuation.yield(.answer(text))
            case .metrics(let metrics): continuation.yield(.metrics(metrics))
            case .toolRequest(let invocation):
              continuation.yield(.activity(.init(
                id: "\(invocation.id)-requested",
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

  private static func presentation(_ activity: AgentActivity, index: Int) -> AgentActivityPresentation? {
    switch activity {
    case .generating:
      return .init(id: "generating-\(index)", kind: .requested, title: "Generating locally",
                   detail: nil, actions: [])
    case .pendingApproval(let request):
      return .pendingApproval(id: "\(request.invocation.id)-approval",
                              toolName: toolTitle(request.invocation.name),
                              effect: request.effect, invocation: request.invocation)
    case .running(let invocation):
      return .init(id: "\(invocation.id)-running", kind: .running,
                   title: "Running \(toolTitle(invocation.name))",
                   detail: "On this device", actions: [])
    case .result(let result):
      let kind: AgentActivityKind = switch result.status {
      case .succeeded: .result
      case .denied: .denied
      case .failed: .failed
      }
      return .init(id: "\(result.invocationID)-result", kind: kind,
                   title: result.status == .succeeded ? "Tool finished" : "Tool \(result.status.rawValue)",
                   detail: result.contentJSON, actions: [])
    case .terminal(let completion):
      return .init(id: "terminal", kind: .terminal, title: "Agent finished",
                   detail: String(describing: completion), actions: [])
    }
  }
}
