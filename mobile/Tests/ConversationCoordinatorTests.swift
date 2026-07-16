import XCTest
@testable import BonsaiMobile

final class ConversationCoordinatorTests: XCTestCase {
  func testCreateListSelectAndSelectionPersistAcrossCoordinatorRelaunch() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let store = try ConversationStore(root: root)
    let installation = Self.installation(.oneBit27B, revisionDigit: "a")
    let first = try ConversationCoordinator(root: root, store: store)
    try await first.bind(installation)
    let initialSnapshot = await Self.snapshot(first)
    let initial = try XCTUnwrap(initialSnapshot)
    let originalID = try XCTUnwrap(initial.selectedID)

    try await first.createConversation()
    let createdSnapshot = await Self.snapshot(first)
    let afterCreate = try XCTUnwrap(createdSnapshot)
    XCTAssertEqual(afterCreate.conversations.count, 2)
    XCTAssertNotEqual(afterCreate.selectedID, originalID)
    try await first.selectConversation(originalID)

    let relaunched = try ConversationCoordinator(root: root, store: store)
    try await relaunched.bind(installation)
    let restoredSnapshot = await Self.snapshot(relaunched)
    let restored = try XCTUnwrap(restoredSnapshot)
    XCTAssertEqual(restored.conversations.count, 2)
    XCTAssertEqual(restored.selectedID, originalID)
  }

  func testModelRevisionChangeCreatesIsolatedSelectionAndRebindRestoresPriorSelection() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let store = try ConversationStore(root: root)
    let coordinator = try ConversationCoordinator(root: root, store: store)
    let firstRevision = Self.installation(.oneBit27B, revisionDigit: "b")
    let secondRevision = Self.installation(.oneBit27B, revisionDigit: "c")

    try await coordinator.bind(firstRevision)
    let firstID = try await coordinator.activeSelection().conversationID
    try await coordinator.bind(secondRevision)
    let secondID = try await coordinator.activeSelection().conversationID
    XCTAssertNotEqual(firstID, secondID)
    let secondSnapshot = await Self.snapshot(coordinator)
    XCTAssertEqual(try XCTUnwrap(secondSnapshot).conversations.count, 1)

    try await coordinator.bind(firstRevision)
    let restoredSelection = try await coordinator.activeSelection()
    XCTAssertEqual(restoredSelection.conversationID, firstID)
  }

  func testFailedCreateDoesNotChangeActiveSelectionOrPublishedIndex() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let coordinator = try ConversationCoordinator(root: root, store: ConversationStore(root: root))
    try await coordinator.bind(Self.installation(.oneBit27B, revisionDigit: "d"))
    let before = try XCTUnwrap(await Self.snapshot(coordinator))
    let navigationRoot = root.appending(path: "ConversationNavigation")
    defer { try? Self.setWritable(true, directory: navigationRoot) }
    try Self.setWritable(false, directory: navigationRoot)

    do {
      try await coordinator.createConversation()
      XCTFail("read-only navigation storage must reject creation")
    } catch {}

    let afterFailure = try XCTUnwrap(await Self.snapshot(coordinator))
    XCTAssertEqual(afterFailure, before)
    XCTAssertEqual(try await coordinator.activeSelection().conversationID, before.selectedID)
    try Self.setWritable(true, directory: navigationRoot)
    try await coordinator.createConversation()
    XCTAssertEqual(try XCTUnwrap(await Self.snapshot(coordinator)).conversations.count, 2)
  }

  func testFailedSelectDoesNotChangeHiddenActiveSelection() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let coordinator = try ConversationCoordinator(root: root, store: ConversationStore(root: root))
    try await coordinator.bind(Self.installation(.oneBit27B, revisionDigit: "e"))
    let originalID = try await coordinator.activeSelection().conversationID
    try await coordinator.createConversation()
    let secondID = try await coordinator.activeSelection().conversationID
    try await coordinator.selectConversation(originalID)
    let navigationRoot = root.appending(path: "ConversationNavigation")
    defer { try? Self.setWritable(true, directory: navigationRoot) }
    try Self.setWritable(false, directory: navigationRoot)

    do {
      try await coordinator.selectConversation(secondID)
      XCTFail("read-only navigation storage must reject selection")
    } catch {}

    XCTAssertEqual(try await coordinator.activeSelection().conversationID, originalID)
    XCTAssertEqual(try XCTUnwrap(await Self.snapshot(coordinator)).selectedID, originalID)
    try Self.setWritable(true, directory: navigationRoot)
    try await coordinator.selectConversation(secondID)
    XCTAssertEqual(try await coordinator.activeSelection().conversationID, secondID)
  }

  func testFailedRenameLeavesTitleEligibleForRetry() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let coordinator = try ConversationCoordinator(root: root, store: ConversationStore(root: root))
    try await coordinator.bind(Self.installation(.oneBit27B, revisionDigit: "f"))
    let navigationRoot = root.appending(path: "ConversationNavigation")
    defer { try? Self.setWritable(true, directory: navigationRoot) }
    try Self.setWritable(false, directory: navigationRoot)

    do {
      try await coordinator.renameSelected(using: "Durable title")
      XCTFail("read-only navigation storage must reject rename")
    } catch {}

    XCTAssertEqual(try XCTUnwrap(await Self.snapshot(coordinator)).conversations.single?.title,
                   "New chat")
    try Self.setWritable(true, directory: navigationRoot)
    try await coordinator.renameSelected(using: "Durable title")
    XCTAssertEqual(try XCTUnwrap(await Self.snapshot(coordinator)).conversations.single?.title,
                   "Durable title")
  }

  func testFailedInitialBindDoesNotExposeUncommittedSelection() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let coordinator = try ConversationCoordinator(root: root, store: ConversationStore(root: root))
    let navigationRoot = root.appending(path: "ConversationNavigation")
    defer { try? Self.setWritable(true, directory: navigationRoot) }
    try Self.setWritable(false, directory: navigationRoot)

    do {
      try await coordinator.bind(Self.installation(.oneBit27B, revisionDigit: "1"))
      XCTFail("read-only navigation storage must reject initial binding")
    } catch {}
    do {
      _ = try await coordinator.activeSelection()
      XCTFail("a failed bind must not expose an uncommitted selection")
    } catch let error as ConversationCoordinatorError {
      XCTAssertEqual(error, .noLoadedModel)
    }

    try Self.setWritable(true, directory: navigationRoot)
    try await coordinator.bind(Self.installation(.oneBit27B, revisionDigit: "1"))
    _ = try await coordinator.activeSelection().conversationID
  }

  private static func snapshot(
    _ coordinator: ConversationCoordinator
  ) async -> ConversationNavigationSnapshot? {
    let stream = await coordinator.snapshots()
    var iterator = stream.makeAsyncIterator()
    return await iterator.next()
  }

  private static func installation(_ modelID: ModelID, revisionDigit: Character) -> ModelInstallation {
    ModelInstallation(
      modelID: modelID,
      directory: URL(fileURLWithPath: "/tmp/\(modelID.rawValue)-\(revisionDigit)"),
      revision: String(repeating: revisionDigit, count: 40))
  }

  private static func setWritable(_ writable: Bool, directory: URL) throws {
    try FileManager.default.setAttributes(
      [.posixPermissions: writable ? 0o700 : 0o500],
      ofItemAtPath: directory.path)
  }
}

private extension Array {
  var single: Element? { count == 1 ? first : nil }
}

@MainActor
final class ConversationNavigationViewModelTests: XCTestCase {
  func testStartSubscribesAndCompactCreateListSelectPublishesState() async throws {
    let first = try ConversationID("first")
    let second = try ConversationID("second")
    let service = PublishingConversationService()
    let viewModel = ConversationNavigationViewModel(service: service)
    viewModel.start()
    await service.waitUntilSubscribed()
    await service.publish(items: [.init(id: first, modelID: .oneBit27B,
                                        modelRevision: String(repeating: "a", count: 40),
                                        title: "First")], selected: first)
    await Self.waitUntil { viewModel.selectedID == first }
    XCTAssertEqual(viewModel.conversations.map(\.title), ["First"])

    await service.publish(items: [
      .init(id: first, modelID: .oneBit27B, modelRevision: String(repeating: "a", count: 40),
            title: "First"),
      .init(id: second, modelID: .oneBit27B, modelRevision: String(repeating: "a", count: 40),
            title: "Second")
    ], selected: second)
    await Self.waitUntil { viewModel.selectedID == second }
    XCTAssertEqual(viewModel.conversations.map(\.title), ["First", "Second"])
  }

  private static func waitUntil(_ predicate: @escaping () -> Bool) async {
    for _ in 0..<100 where !predicate() { await Task.yield() }
  }
}

private actor PublishingConversationService: ConversationNavigationServing {
  private var continuation: AsyncStream<ConversationNavigationSnapshot>.Continuation?
  func snapshots() -> AsyncStream<ConversationNavigationSnapshot> {
    let pair = AsyncStream<ConversationNavigationSnapshot>.makeStream()
    continuation = pair.continuation
    return pair.stream
  }
  func createConversation() async throws {}
  func selectConversation(_ id: ConversationID) async throws {}
  func waitUntilSubscribed() async { while continuation == nil { await Task.yield() } }
  func publish(items: [ConversationListItem], selected: ConversationID?) {
    continuation?.yield(.init(installation: nil, conversations: items, selectedID: selected))
  }
}
