import XCTest
@testable import BonsaiMobile

@MainActor
final class ModelLibraryViewModelTests: XCTestCase {
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

  func testFailedLoadPresentsTypedRetryThatRepeatsTheLoadIntent() async throws {
    let snapshot = ModelLibrarySnapshot.fixture(.ready)
    let service = FailingLibraryService(
      snapshot: snapshot,
      error: LiveUIServiceError.modelNotInstalled)
    let viewModel = ModelLibraryViewModel(service: service, platform: .mac, initial: snapshot)
    let load = try XCTUnwrap(viewModel.rows.first { $0.id == .oneBit27B }?.primaryAction)

    await viewModel.perform(load, modelID: .oneBit27B)

    let failure = try XCTUnwrap(viewModel.actionFailure)
    XCTAssertEqual(failure.modelID, .oneBit27B)
    XCTAssertEqual(failure.recovery, .init(label: "Retry load", intent: .load))
    XCTAssertTrue(failure.message.contains("Install and verify"))

    await viewModel.perform(failure.recovery, modelID: failure.modelID)
    let intents = await service.intents
    XCTAssertEqual(intents, [.load, .load])
  }

  func testFailedImportPresentsRetryThatReopensTheFileImporter() async throws {
    let snapshot = ModelLibrarySnapshot.fixture(.empty)
    let service = FailingLibraryService(
      snapshot: snapshot,
      error: LiveUIServiceError.importRequiresPicker)
    let viewModel = ModelLibraryViewModel(service: service, platform: .mac, initial: snapshot)
    let importAction = try XCTUnwrap(viewModel.rows.first { $0.id == .oneBit27B }?
      .secondaryActions.first { $0.intent == .importModel })
    await viewModel.perform(importAction, modelID: .oneBit27B)
    await viewModel.importPending(from: URL(fileURLWithPath: "/tmp/Bonsai.zip"))

    let failure = try XCTUnwrap(viewModel.actionFailure)
    XCTAssertEqual(failure.recovery, .init(label: "Retry import", intent: .importModel))
    await viewModel.perform(failure.recovery, modelID: failure.modelID)

    XCTAssertEqual(viewModel.pendingImportModelID, .oneBit27B)
  }

  func testLoadAndVerifyPublishOperationStateWhileServiceAwaits() async throws {
    for (intent, expectedStatus) in [
      (ModelLibraryIntent.load, "Loading into memory"),
      (.verify, "Verifying model files")
    ] {
      let snapshot = ModelLibrarySnapshot.fixture(.ready)
      let service = SuspendingLibraryService(snapshot: snapshot)
      let viewModel = ModelLibraryViewModel(service: service, platform: .mac, initial: snapshot)
      let row = try XCTUnwrap(viewModel.rows.first { $0.id == .oneBit27B })
      let action = intent == .load
        ? try XCTUnwrap(row.primaryAction)
        : try XCTUnwrap(row.secondaryActions.first { $0.intent == .verify })

      let operation = Task { await viewModel.perform(action, modelID: .oneBit27B) }
      await service.waitUntilStarted()

      XCTAssertEqual(viewModel.rows.first { $0.id == .oneBit27B }?.status, expectedStatus)
      XCTAssertTrue(viewModel.inFlightModelIDs.contains(.oneBit27B))

      await service.finish()
      await operation.value
    }
  }

  func testReplacementDisablesChatUntilPublishedAndRestoresPriorModelAfterFailure() async throws {
    let snapshot = ModelLibrarySnapshot.fixture(.ready)
    let service = ReplacementLibraryService(snapshot: snapshot)
    let viewModel = ModelLibraryViewModel(service: service, platform: .mac, initial: snapshot)
    let oneBitLoad = try XCTUnwrap(viewModel.rows.first { $0.id == .oneBit27B }?.primaryAction)
    await viewModel.perform(oneBitLoad, modelID: .oneBit27B)
    XCTAssertEqual(viewModel.loadedModelID, .oneBit27B)

    let ternaryLoad = try XCTUnwrap(viewModel.rows.first { $0.id == .ternary27B }?.primaryAction)
    await service.suspendNextLoadAndFail()
    let replacement = Task { await viewModel.perform(ternaryLoad, modelID: .ternary27B) }
    await service.waitUntilStarted()

    XCTAssertNil(viewModel.loadedModelID, "replacement must withdraw chat readiness while in flight")
    await service.finishReplacement()
    await replacement.value

    XCTAssertEqual(viewModel.loadedModelID, .oneBit27B)
    XCTAssertTrue(try XCTUnwrap(viewModel.rows.first { $0.id == .oneBit27B }).isLoaded)
  }
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

private actor FailingLibraryService: ModelLibraryServing {
  let snapshot: ModelLibrarySnapshot
  let error: LiveUIServiceError
  private(set) var intents: [ModelLibraryIntent] = []

  init(snapshot: ModelLibrarySnapshot, error: LiveUIServiceError) {
    self.snapshot = snapshot
    self.error = error
  }

  func snapshots() async -> AsyncStream<ModelLibrarySnapshot> {
    AsyncStream { continuation in continuation.yield(snapshot); continuation.finish() }
  }

  func perform(_ intent: ModelLibraryIntent, for modelID: ModelID) async throws {
    intents.append(intent)
    throw error
  }

  func importModel(_ modelID: ModelID, from source: URL) async throws { throw error }
}

private actor SuspendingLibraryService: ModelLibraryServing {
  let snapshot: ModelLibrarySnapshot
  private var started = false
  private var continuation: CheckedContinuation<Void, Never>?

  init(snapshot: ModelLibrarySnapshot) { self.snapshot = snapshot }

  func snapshots() async -> AsyncStream<ModelLibrarySnapshot> {
    AsyncStream { continuation in continuation.yield(snapshot); continuation.finish() }
  }

  func perform(_ intent: ModelLibraryIntent, for modelID: ModelID) async throws {
    started = true
    await withCheckedContinuation { continuation = $0 }
  }

  func waitUntilStarted() async {
    while !started { await Task.yield() }
  }

  func finish() { continuation?.resume(); continuation = nil }
}

private actor ReplacementLibraryService: ModelLibraryServing {
  let snapshot: ModelLibrarySnapshot
  private var loaded: ModelID?
  private var shouldSuspendAndFail = false
  private var started = false
  private var continuation: CheckedContinuation<Void, Never>?

  init(snapshot: ModelLibrarySnapshot) { self.snapshot = snapshot }
  func snapshots() async -> AsyncStream<ModelLibrarySnapshot> {
    AsyncStream { continuation in continuation.yield(snapshot); continuation.finish() }
  }
  func currentLoadedModelID() async -> ModelID? { loaded }
  func perform(_ intent: ModelLibraryIntent, for modelID: ModelID) async throws {
    guard intent == .load else { return }
    if shouldSuspendAndFail {
      started = true
      await withCheckedContinuation { continuation = $0 }
      shouldSuspendAndFail = false
      throw LiveUIServiceError.modelNotInstalled
    }
    loaded = modelID
  }
  func suspendNextLoadAndFail() { shouldSuspendAndFail = true }
  func waitUntilStarted() async { while !started { await Task.yield() } }
  func finishReplacement() { continuation?.resume(); continuation = nil }
}
