import Foundation
import Observation

enum ModelLibraryIntent: Equatable, Sendable {
  case download, retryDownload, verify, importModel, load, unload, delete
}

struct ModelActionPresentation: Equatable, Sendable {
  let label: String
  let intent: ModelLibraryIntent
}

struct ModelActionFailurePresentation: Equatable, Sendable {
  let message: String
  let modelID: ModelID
  let recovery: ModelActionPresentation
}

struct LoadedModelQualification: Equatable, Sendable {
  let modelID: ModelID
  let capabilities: Set<ModelCapability>
}

struct ModelRowPresentation: Identifiable, Equatable, Sendable {
  let id: ModelID
  let name: String
  let footprint: String
  let status: String
  let detail: String?
  let progress: Double?
  let primaryAction: ModelActionPresentation?
  let secondaryActions: [ModelActionPresentation]
  let recovery: ModelActionPresentation?
  let isLoaded: Bool
}

protocol ModelLibraryServing: Sendable {
  func snapshots() async -> AsyncStream<ModelLibrarySnapshot>
  func perform(_ intent: ModelLibraryIntent, for modelID: ModelID) async throws
  func importModel(_ modelID: ModelID, from source: URL) async throws
  func currentLoadedModelID() async -> ModelID?
  func currentLoadedCapabilities() async -> Set<ModelCapability>
  func currentLoadedQualification() async -> LoadedModelQualification?
}

extension ModelLibraryServing {
  func importModel(_ modelID: ModelID, from source: URL) async throws {
    throw LiveUIServiceError.importRequiresPicker
  }
  func currentLoadedModelID() async -> ModelID? { nil }
  func currentLoadedCapabilities() async -> Set<ModelCapability> { [] }
  func currentLoadedQualification() async -> LoadedModelQualification? {
    guard let modelID = await currentLoadedModelID() else { return nil }
    return .init(modelID: modelID, capabilities: await currentLoadedCapabilities())
  }
}

@MainActor @Observable
final class ModelLibraryViewModel {
  private let service: any ModelLibraryServing
  private let platform: Platform
  private(set) var rows: [ModelRowPresentation]
  private(set) var errorMessage: String?
  private(set) var actionFailure: ModelActionFailurePresentation?
  private(set) var loadedQualification: LoadedModelQualification?
  var loadedModelID: ModelID? { loadedQualification?.modelID }
  var loadedCapabilities: Set<ModelCapability> { loadedQualification?.capabilities ?? [] }
  private(set) var inFlightModelIDs: Set<ModelID> = []
  private(set) var inFlightIntents: [ModelID: ModelLibraryIntent] = [:]
  var pendingImportModelID: ModelID?
  private var latestSnapshot: ModelLibrarySnapshot
  private var observationTask: Task<Void, Never>?

  init(service: any ModelLibraryServing, platform: Platform, initial: ModelLibrarySnapshot) {
    self.service = service
    self.platform = platform
    latestSnapshot = initial
    rows = Self.rows(snapshot: initial, loadedModelID: nil, platform: platform)
  }

  func start() {
    guard observationTask == nil else { return }
    observationTask = Task { [weak self, service] in
      for await snapshot in await service.snapshots() {
        guard !Task.isCancelled, let self else { return }
        self.latestSnapshot = snapshot
        self.refreshRows()
      }
    }
  }

  func present(error: String) {
    actionFailure = nil
    errorMessage = error
  }

  func perform(_ action: ModelActionPresentation, modelID: ModelID) async {
    if action.intent == .importModel {
      actionFailure = nil
      errorMessage = nil
      pendingImportModelID = modelID
      return
    }
    guard inFlightModelIDs.insert(modelID).inserted else { return }
    inFlightIntents[modelID] = action.intent
    let replacesPublishedModel = action.intent == .load
      || action.intent == .unload
      || (action.intent == .delete && loadedModelID == modelID)
    if replacesPublishedModel {
      loadedQualification = nil
    }
    refreshRows()
    defer {
      inFlightModelIDs.remove(modelID)
      inFlightIntents.removeValue(forKey: modelID)
      refreshRows()
    }
    do {
      try await service.perform(action.intent, for: modelID)
      switch action.intent {
      case .load:
        loadedQualification = await service.currentLoadedQualification()
          ?? .init(modelID: modelID, capabilities: [])
      case .unload:
        loadedQualification = nil
      case .delete:
        if loadedModelID == modelID {
          loadedQualification = nil
        }
      default: break
      }
      actionFailure = nil
      errorMessage = nil
    } catch {
      if replacesPublishedModel {
        loadedQualification = await service.currentLoadedQualification()
      }
      actionFailure = Self.failure(for: action.intent, modelID: modelID, error: error)
      errorMessage = nil
    }
  }

  func importPending(from source: URL) async {
    guard let modelID = pendingImportModelID,
          inFlightModelIDs.insert(modelID).inserted else { return }
    pendingImportModelID = nil
    inFlightIntents[modelID] = .importModel
    defer {
      inFlightModelIDs.remove(modelID)
      inFlightIntents.removeValue(forKey: modelID)
    }
    do {
      try await service.importModel(modelID, from: source)
      actionFailure = nil
      errorMessage = nil
    } catch {
      actionFailure = Self.failure(for: .importModel, modelID: modelID, error: error)
      errorMessage = nil
    }
  }

  static func rows(
    snapshot: ModelLibrarySnapshot,
    loadedModelID: ModelID?,
    platform: Platform,
    inFlightIntents: [ModelID: ModelLibraryIntent] = [:]
  ) -> [ModelRowPresentation] {
    ModelID.allCases.map { id in
      let state = presentationState(
        snapshot.states[id] ?? .notInstalled,
        for: inFlightIntents[id])
      return row(id: id, state: state,
          loadedModelID: loadedModelID, platform: platform)
    }
  }

  private func refreshRows() {
    rows = Self.rows(
      snapshot: latestSnapshot,
      loadedModelID: loadedModelID,
      platform: platform,
      inFlightIntents: inFlightIntents)
  }

  private static func presentationState(
    _ state: ModelLibraryState,
    for intent: ModelLibraryIntent?
  ) -> ModelLibraryState {
    switch intent {
    case .load: .loading
    case .verify: .verifying(completedBytes: 0, totalBytes: 0)
    default: state
    }
  }

  private static func failure(
    for intent: ModelLibraryIntent,
    modelID: ModelID,
    error: any Error
  ) -> ModelActionFailurePresentation {
    let action: String
    switch intent {
    case .download, .retryDownload: action = "download"
    case .verify: action = "verification"
    case .importModel: action = "import"
    case .load: action = "load"
    case .unload: action = "unload"
    case .delete: action = "delete"
    }
    let description = (error as? any LocalizedError)?.errorDescription ?? error.localizedDescription
    return .init(
      message: "Model \(action) failed. \(description)",
      modelID: modelID,
      recovery: .init(label: "Retry \(action)", intent: intent))
  }

  // Exhaustively maps every domain state to its complete row action model.
  // swiftlint:disable:next function_body_length
  private static func row(
    id: ModelID, state: ModelLibraryState, loadedModelID: ModelID?, platform: Platform
  ) -> ModelRowPresentation {
    let unsupported = id == .ternary27B && platform == .iPhone
    let name = id == .oneBit27B ? "Bonsai 27B · 1-bit" : "Ternary Bonsai 27B"
    let footprint = id == .oneBit27B ? "4.8 GB · smallest" : "7.9 GB · higher quality"
    if unsupported {
      return .init(id: id, name: name, footprint: footprint, status: "Unavailable on iPhone",
                   detail: "Ternary requires a verified high-memory iPad or Mac.", progress: nil,
                   primaryAction: nil, secondaryActions: [], recovery: nil, isLoaded: false)
    }
    switch state {
    case .notInstalled:
      return .init(id: id, name: name, footprint: footprint, status: "Not installed", detail: nil,
                   progress: nil, primaryAction: .init(label: "Download", intent: .download),
                   secondaryActions: [.init(label: "Import", intent: .importModel)], recovery: nil,
                   isLoaded: false)
    case .installing(let completed, let total):
      let progress = total > 0 ? Double(completed) / Double(total) : 0
      return .init(id: id, name: name, footprint: footprint,
                   status: "Downloading \(completed) of \(total) files", detail: nil,
                   progress: progress, primaryAction: nil, secondaryActions: [], recovery: nil,
                   isLoaded: false)
    case .transferring(let completed, let total):
      let progress = total > 0 ? Double(completed) / Double(total) : 0
      let completedText = ByteCountFormatter.string(
        fromByteCount: Int64(completed), countStyle: .file)
      let totalText = ByteCountFormatter.string(
        fromByteCount: Int64(total), countStyle: .file)
      return .init(id: id, name: name, footprint: footprint,
                   status: "Downloading \(completedText) of \(totalText)",
                   detail: nil, progress: progress, primaryAction: nil, secondaryActions: [],
                   recovery: nil, isLoaded: false)
    case .verifying(let completed, let total):
      return .init(id: id, name: name, footprint: footprint, status: "Verifying model files",
                   detail: nil, progress: total > 0 ? Double(completed) / Double(total) : 0,
                   primaryAction: nil, secondaryActions: [], recovery: nil, isLoaded: false)
    case .loading:
      return .init(id: id, name: name, footprint: footprint, status: "Loading into memory",
                   detail: nil, progress: nil, primaryAction: nil, secondaryActions: [],
                   recovery: nil, isLoaded: false)
    case .ready:
      let loaded = loadedModelID == id
      return .init(id: id, name: name, footprint: footprint,
                   status: loaded ? "Loaded · ready to chat" : "Verified on this device", detail: nil,
                   progress: nil,
                   primaryAction: .init(label: loaded ? "Unload" : "Load",
                                        intent: loaded ? .unload : .load),
                   secondaryActions: [.init(label: "Verify again", intent: .verify),
                                      .init(label: "Delete", intent: .delete)],
                   recovery: nil, isLoaded: loaded)
    case .cancelled:
      return .init(id: id, name: name, footprint: footprint, status: "Download stopped", detail: nil,
                   progress: nil, primaryAction: nil, secondaryActions: [],
                   recovery: .init(label: "Resume download", intent: .retryDownload), isLoaded: false)
    case .failed(let message):
      return .init(id: id, name: name, footprint: footprint, status: "Download failed",
                   detail: message, progress: nil, primaryAction: nil, secondaryActions: [],
                   recovery: .init(label: "Retry download", intent: .retryDownload), isLoaded: false)
    }
  }
}

enum ModelLibraryFixture: Sendable { case empty, downloading, ready, recoverableFailure }

extension ModelLibrarySnapshot {
  static func fixture(_ fixture: ModelLibraryFixture) -> ModelLibrarySnapshot {
    let states: [ModelID: ModelLibraryState]
    switch fixture {
    case .empty:
      states = [.oneBit27B: .notInstalled, .ternary27B: .notInstalled]
    case .downloading:
      states = [.oneBit27B: .installing(completedFiles: 2, totalFiles: 5), .ternary27B: .notInstalled]
    case .ready:
      states = [.oneBit27B: .ready(.fixture(.oneBit27B)), .ternary27B: .ready(.fixture(.ternary27B))]
    case .recoverableFailure:
      states = [.oneBit27B: .failed("The connection ended before verification."), .ternary27B: .notInstalled]
    }
    return ModelLibrarySnapshot(states: states)
  }
}

extension ModelInstallation {
  static func fixture(_ id: ModelID) -> ModelInstallation {
    ModelInstallation(modelID: id, directory: URL(fileURLWithPath: "/fixture/\(id.rawValue)"),
                      revision: String(repeating: id == .oneBit27B ? "a" : "b", count: 40))
  }
}
