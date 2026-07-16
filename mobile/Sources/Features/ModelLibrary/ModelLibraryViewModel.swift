import Foundation
import Observation

enum ModelLibraryIntent: Equatable, Sendable {
  case download, retryDownload, verify, importModel, load, unload, delete
}

struct ModelActionPresentation: Equatable, Sendable {
  let label: String
  let intent: ModelLibraryIntent
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
}

@MainActor @Observable
final class ModelLibraryViewModel {
  private let service: any ModelLibraryServing
  private let platform: Platform
  private(set) var rows: [ModelRowPresentation]
  private(set) var errorMessage: String?
  private(set) var loadedModelID: ModelID?
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
        self.rows = Self.rows(snapshot: snapshot, loadedModelID: self.loadedModelID, platform: self.platform)
      }
    }
  }

  func perform(_ action: ModelActionPresentation, modelID: ModelID) async {
    do {
      try await service.perform(action.intent, for: modelID)
      switch action.intent {
      case .load: loadedModelID = modelID
      case .unload: loadedModelID = nil
      default: break
      }
      rows = Self.rows(snapshot: latestSnapshot, loadedModelID: loadedModelID, platform: platform)
      errorMessage = nil
    } catch {
      errorMessage = String(describing: error)
    }
  }

  static func rows(
    snapshot: ModelLibrarySnapshot,
    loadedModelID: ModelID?,
    platform: Platform
  ) -> [ModelRowPresentation] {
    ModelID.allCases.map { id in
      row(id: id, state: snapshot.states[id] ?? .notInstalled,
          loadedModelID: loadedModelID, platform: platform)
    }
  }

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
