// swiftlint:disable file_length
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import BonsaiMobile

// Clear crash-boundary and image-memory tests share the same real image fixtures.
// swiftlint:disable type_body_length
final class ImagePreprocessorTests: XCTestCase {
  func testFastDetailUsesDeterministicPatchGridAndNeverUpscales() throws {
    let processor = ImagePreprocessor(tokenBudget: 1_024, patchSize: 32)

    XCTAssertEqual(
      try processor.targetSize(for: .init(width: 4_000, height: 3_000)),
      .init(width: 1_184, height: 864))
    XCTAssertEqual(
      try processor.targetSize(for: .init(width: 640, height: 480)),
      .init(width: 640, height: 480))
    XCTAssertLessThanOrEqual((1_184 / 32) * (864 / 32), 1_024)
  }

  func testFastProcessingEncodesExactBoundedLandscapePortraitAndTieDimensions() async throws {
    for (sourceSize, expected) in [
      (PixelSize(width: 4_000, height: 3_000), PixelSize(width: 1_184, height: 864)),
      (PixelSize(width: 3_000, height: 4_000), PixelSize(width: 864, height: 1_184)),
      (PixelSize(width: 2_048, height: 2_048), PixelSize(width: 1_024, height: 1_024))
    ] {
      let root = temporaryDirectory()
      defer { try? FileManager.default.removeItem(at: root) }
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      let source = root.appending(path: "source.png")
      try makeImage(width: sourceSize.width, height: sourceSize.height).write(to: source)

      let result = try await ImagePreprocessor().process(
        managedURL: source, policy: .fast1024, managedRoot: root)
      XCTAssertEqual(result.pixelSize, expected)
      XCTAssertEqual(result.buffer.image.width, expected.width)
      XCTAssertEqual(result.buffer.image.height, expected.height)
      XCTAssertLessThanOrEqual(
        ((expected.width + 31) / 32) * ((expected.height + 31) / 32), 1_024)
    }
  }

  func testExtremeConfigurationReturnsTypedErrorWithoutOverflowing() throws {
    for processor in [
      ImagePreprocessor(tokenBudget: .max, patchSize: 32),
      ImagePreprocessor(tokenBudget: 1_024, patchSize: .max),
      ImagePreprocessor(tokenBudget: 0, patchSize: 32)
    ] {
      XCTAssertThrowsError(try processor.targetSize(for: .init(width: 4_000, height: 3_000))) {
        XCTAssertEqual($0 as? ImagePreprocessorError, .invalidConfiguration)
      }
    }
  }

  func testOrientationSwapsDimensionsAndRejectsUnsafeGeometry() throws {
    let processor = ImagePreprocessor(tokenBudget: 1_024, patchSize: 32)
    XCTAssertEqual(
      try processor.normalizedSize(
        pixels: .init(width: 4_000, height: 3_000), orientation: .right),
      .init(width: 3_000, height: 4_000))

    XCTAssertThrowsError(try processor.targetSize(for: .init(width: 0, height: 10)))
    XCTAssertThrowsError(try processor.targetSize(for: .init(width: .max, height: .max)))
  }

  func testManagedImportStripsMetadataAndConfinesPaths() async throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let source = root.appending(path: "source.jpg")
    try makeJPEGWithLocationMetadata(width: 80, height: 60).write(to: source)
    XCTAssertNotNil(locationMetadata(in: source))
    let store = try ManagedAttachmentStore(root: root.appending(path: "managed"))

    let attachment = try await store.importImage(
      from: source, detailPolicy: .fast1024, accessibleLabel: "A test image")
    XCTAssertEqual(attachment.pixelSize, .init(width: 80, height: 60))
    XCTAssertEqual(attachment.lifecycle, .managedDraft)
    XCTAssertFalse(attachment.managedRelativePath.contains("/"))
    let managedURL = try await store.url(for: attachment)
    XCTAssertTrue(FileManager.default.fileExists(atPath: managedURL.path))

    let processed = try await ImagePreprocessor().process(
      managedURL: managedURL, policy: .fast1024, managedRoot: root.appending(path: "managed"))
    XCTAssertNil(locationMetadata(for: processed.buffer.image))

    let outside = ImageAttachment(
      id: UUID(), originalFilename: "escape.jpg", managedRelativePath: "../escape.jpg",
      pixelSize: .init(width: 1, height: 1), byteCount: 1, contentType: "image/jpeg",
      detailPolicy: .fast1024, lifecycle: .managedDraft, accessibleLabel: "Escape")
    await XCTAssertThrowsErrorAsync { _ = try await store.url(for: outside) }
  }

  func testPreprocessingRejectsCorruptAndOversizedSourcesAndCleansTemporaryOutput() async throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let managed = root.appending(path: "managed", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: managed, withIntermediateDirectories: true)
    let corrupt = managed.appending(path: "corrupt.jpg")
    try Data("not-an-image".utf8).write(to: corrupt)
    let processor = ImagePreprocessor(tokenBudget: 1_024, patchSize: 32)

    await XCTAssertThrowsErrorAsync {
      _ = try await processor.process(
        managedURL: corrupt, policy: .fast1024, managedRoot: managed)
    }
    XCTAssertTrue((try FileManager.default.contentsOfDirectory(atPath: managed.path)) == ["corrupt.jpg"])
  }

  func testFastProcessingPreservesColoredSourceEdgesWithAspectFitPadding() async throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let source = root.appending(path: "edges.png")
    try makeEdgeMarkerImage(width: 4_000, height: 3_000).write(to: source)

    let result = try await ImagePreprocessor().process(
      managedURL: source, policy: .fast1024, managedRoot: root)
    let image = result.buffer.image
    XCTAssertTrue(try containsDominantColor(image, red: true))
    XCTAssertTrue(try containsDominantColor(image, red: false))
  }

  func testSymlinkedSourceAndProcessedDirectoryNeverTouchExternalSentinel() async throws {
    let root = temporaryDirectory()
    let outside = temporaryDirectory()
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: outside)
    }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    let sentinel = outside.appending(path: "sentinel.png")
    let sentinelData = try makeImage(width: 16, height: 16)
    try sentinelData.write(to: sentinel)
    try FileManager.default.createSymbolicLink(
      at: root.appending(path: "source.png"), withDestinationURL: sentinel)

    await XCTAssertThrowsErrorAsync(expected: ImagePreprocessorError.corruptOrUnsupported) {
      _ = try await ImagePreprocessor().process(
        managedURL: root.appending(path: "source.png"), policy: .fast1024, managedRoot: root)
    }
    try FileManager.default.removeItem(at: root.appending(path: "source.png"))
    try makeImage(width: 16, height: 16).write(to: root.appending(path: "source.png"))
    try FileManager.default.createSymbolicLink(
      at: root.appending(path: ".processed"), withDestinationURL: outside)
    _ = try await ImagePreprocessor().process(
      managedURL: root.appending(path: "source.png"), policy: .fast1024, managedRoot: root)
    XCTAssertEqual(try Data(contentsOf: sentinel), sentinelData)
  }

  func testAttachmentStoreRejectsSymlinkRootLeafAndRootReplacement() async throws {
    let base = temporaryDirectory()
    let outside = temporaryDirectory()
    defer {
      try? FileManager.default.removeItem(at: base)
      try? FileManager.default.removeItem(at: outside)
    }
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    let sentinel = outside.appending(path: "sentinel.jpg")
    try makeImage(width: 16, height: 16).write(to: sentinel)
    let symlinkRoot = base.appending(path: "linked")
    try FileManager.default.createSymbolicLink(at: symlinkRoot, withDestinationURL: outside)
    XCTAssertThrowsError(try ManagedAttachmentStore(root: symlinkRoot))

    let root = base.appending(path: "managed")
    let store = try ManagedAttachmentStore(root: root)
    let source = base.appending(path: "source.png")
    try makeImage(width: 16, height: 16).write(to: source)
    let attachment = try await store.importImage(
      from: source, detailPolicy: .fast1024, accessibleLabel: "test")
    let leaf = root.appending(path: attachment.managedRelativePath)
    try FileManager.default.removeItem(at: leaf)
    try FileManager.default.createSymbolicLink(at: leaf, withDestinationURL: sentinel)
    await XCTAssertThrowsErrorAsync { _ = try await store.data(for: attachment.persistedReference()) }

    try FileManager.default.removeItem(at: root)
    try FileManager.default.createSymbolicLink(at: root, withDestinationURL: outside)
    await XCTAssertThrowsErrorAsync { _ = try await store.url(for: attachment) }
    XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))
  }

  func testCancellationAfterOutputDropsInMemoryResultAndCreatesNoProcessedLeaf() async throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let source = root.appending(path: "source.png")
    let data = try makeImage(width: 2_048, height: 2_048)
    try data.write(to: source)
    let hook = SuspendingPreprocessingHook()
    let task = Task {
      try await ImagePreprocessor(hook: hook).process(
        managedURL: source, policy: .fast1024, managedRoot: root)
    }
    await hook.waitUntilOutputExists()
    task.cancel()
    await hook.resume()
    do {
      _ = try await task.value
      XCTFail("Expected cancellation")
    } catch is CancellationError {}
    XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: ".processed").path))
  }

  func testPreparedClearJournalRollsBackOnRelaunch() async throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let source = root.appending(path: "source.png")
    try makeImage(width: 32, height: 32).write(to: source)
    let managed = root.appending(path: "managed")
    let store = try ManagedAttachmentStore(root: managed)
    let attachment = try await store.importImage(
      from: source, detailPolicy: .fast1024, accessibleLabel: "private")
    _ = try await store.prepareClear()

    _ = try ManagedAttachmentStore(root: managed)

    XCTAssertTrue(FileManager.default.fileExists(
      atPath: managed.appending(path: attachment.managedRelativePath).path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: managed.appending(path: ".clear-journal").path))
    XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: managed.path)
      .contains(where: { $0.hasPrefix(".clear-") }))
  }

  func testCommittedClearJournalFinishesPurgeOnRelaunch() throws {
    let managed = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: managed) }
    try FileManager.default.createDirectory(at: managed, withIntermediateDirectories: true)
    let staging = managed.appending(path: ".clear-crash")
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
    try Data("private".utf8).write(to: staging.appending(path: "draft.jpg"))
    try Data(
      "{\"phase\":\"committed\",\"stagingName\":\".clear-crash\",\"leafNames\":[\"draft.jpg\"]}"
        .utf8
    ).write(to: managed.appending(path: ".clear-journal"))

    _ = try ManagedAttachmentStore(root: managed)

    XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: managed.path).isEmpty)
  }

  func testInjectedCommitPurgeFailureRetainsJournalAndRelaunchRetries() async throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let source = root.appending(path: "source.png")
    try makeImage(width: 16, height: 16).write(to: source)
    let managed = root.appending(path: "managed")
    let faults = AttachmentStoreFaultInjector([.purgeUnlink])
    let store = try ManagedAttachmentStore(root: managed, faultInjector: faults)
    _ = try await store.importImage(
      from: source, detailPolicy: .fast1024, accessibleLabel: "private")
    let transaction = try await store.prepareClear()

    await XCTAssertThrowsErrorAsync { try await store.commitClear(transaction) }
    XCTAssertTrue(FileManager.default.fileExists(atPath: managed.appending(path: ".clear-journal").path))

    _ = try ManagedAttachmentStore(root: managed)
    XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: managed.path).isEmpty)
  }

  func testPhotosTransferCopiesToOwnedBoundedFileAndCleansIt() throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let provider = root.appending(path: "provider.png")
    let expected = try makeImage(width: 16, height: 16)
    try expected.write(to: provider)

    let lease = try PickedPhotoFile.copyProviderFile(provider)
    XCTAssertNotEqual(lease.url, provider)
    XCTAssertEqual(try Data(contentsOf: lease.url), expected)
    try OwnedImageFileCleanupRegistry.shared.removeOrRetain(lease)
    XCTAssertFalse(FileManager.default.fileExists(atPath: lease.url.path))
  }

  func testOwnedLeaseRegistryRetainsFailedDeleteAndExplicitRetryRemovesFile() throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let privateCopy = root.appending(path: "private-copy.jpg")
    try Data("private".utf8).write(to: privateCopy)
    let remover = DeleteFailsOnceImageFileRemover()
    let lease = OwnedImageFileLease(url: privateCopy, remover: remover)

    XCTAssertThrowsError(try OwnedImageFileCleanupRegistry.shared.removeOrRetain(lease)) {
      XCTAssertNotNil($0 as? OwnedImageFileLeaseError)
    }
    XCTAssertTrue(lease.ownsFile)
    XCTAssertTrue(FileManager.default.fileExists(atPath: privateCopy.path))

    let retryFailures = OwnedImageFileCleanupRegistry.shared.retryRetained()

    XCTAssertTrue(retryFailures.isEmpty)
    XCTAssertFalse(lease.ownsFile)
    XCTAssertFalse(FileManager.default.fileExists(atPath: privateCopy.path))
    XCTAssertEqual(remover.attemptCount, 2)
  }

  @MainActor
  func testCameraCaptureIsSingleFlightAndDismissalInvalidatesDelayedDelivery() async throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let privateCopy = root.appending(path: "delayed-camera.jpg")
    try Data("private".utf8).write(to: privateCopy)
    let lease = OwnedImageFileLease(url: privateCopy)
    let session = RecordingCameraSessionRunner()
    let persister = SuspendingCameraImagePersister(lease: lease)
    var picked: [URL] = []
    var failures = 0
    let lifecycle = CameraCaptureLifecycle(
      session: session,
      persister: persister,
      onPicked: { picked.append($0) },
      onFailure: { _ in failures += 1 })

    lifecycle.start()
    XCTAssertTrue(lifecycle.beginCapture())
    XCTAssertFalse(lifecycle.beginCapture())
    lifecycle.completeCapture(data: Data([1]))
    await persister.waitUntilStarted()
    var mainActorAdvanced = false
    Task { @MainActor in mainActorAdvanced = true }
    await Task.yield()
    XCTAssertTrue(mainActorAdvanced)

    lifecycle.stop()
    await persister.resume()
    await lifecycle.waitUntilIdle()

    XCTAssertEqual(session.startCount, 1)
    XCTAssertEqual(session.stopCount, 1)
    XCTAssertTrue(picked.isEmpty)
    XCTAssertEqual(failures, 0)
    XCTAssertFalse(FileManager.default.fileExists(atPath: privateCopy.path))
    XCTAssertFalse(lifecycle.isCaptureInFlight)
  }

  func testPhotosTransferRejectsOversizedSparseProviderBeforeOwnedCopy() throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let provider = root.appending(path: "oversized.jpg")
    FileManager.default.createFile(atPath: provider.path, contents: Data([0]))
    let handle = try FileHandle(forWritingTo: provider)
    try handle.truncate(atOffset: UInt64(ManagedAttachmentStore.maximumSourceBytes + 1))
    try handle.close()

    XCTAssertThrowsError(try PickedPhotoFile.copyProviderFile(provider)) {
      XCTAssertEqual($0 as? AttachmentStoreError, .sourceTooLarge)
    }
  }

#if os(iOS)
  func testCameraEncodedPayloadRejectsOversizeBeforeCreatingOwnedFile() {
    XCTAssertThrowsError(try CameraEncodedFile.persist(Data([1, 2]), maximumBytes: 1)) {
      XCTAssertEqual($0 as? CameraCaptureError, .oversized)
    }
  }
#endif

  private func makeJPEGWithLocationMetadata(width: Int, height: Int) throws -> Data {
    let image = try XCTUnwrap(makeCGImage(width: width, height: height))
    let data = NSMutableData()
    let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
      data, UTType.jpeg.identifier as CFString, 1, nil))
    let metadata: [CFString: Any] = [
      kCGImagePropertyGPSDictionary: [
        kCGImagePropertyGPSLatitude: 37.3318,
        kCGImagePropertyGPSLatitudeRef: "N",
        kCGImagePropertyGPSLongitude: -122.0312,
        kCGImagePropertyGPSLongitudeRef: "W"
      ],
      kCGImagePropertyExifDictionary: [
        kCGImagePropertyExifUserComment: "fixture location"
      ]
    ]
    CGImageDestinationAddImage(destination, image, metadata as CFDictionary)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    return data as Data
  }

  private func makeCGImage(width: Int, height: Int) -> CGImage? {
    let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8,
      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    return context?.makeImage()
  }

  private func locationMetadata(in url: URL) -> [String: Any]? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
    else { return nil }
    return properties[kCGImagePropertyGPSDictionary as String] as? [String: Any]
  }

  private func locationMetadata(for image: CGImage) -> [String: Any]? {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
      data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination),
          let source = CGImageSourceCreateWithData(data as CFData, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
    else { return nil }
    return properties[kCGImagePropertyGPSDictionary as String] as? [String: Any]
  }

  private func makeImage(width: Int, height: Int) throws -> Data {

    let space = CGColorSpaceCreateDeviceRGB()
    let context = try XCTUnwrap(CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8,
      bytesPerRow: 0, space: space,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0.12, green: 0.64, blue: 0.27, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try XCTUnwrap(context.makeImage())
    let data = NSMutableData()
    let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
      data, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    return data as Data
  }

  private func makeEdgeMarkerImage(width: Int, height: Int) throws -> Data {
    let space = CGColorSpaceCreateDeviceRGB()
    let context = try XCTUnwrap(CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8,
      bytesPerRow: 0, space: space,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(gray: 0.5, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 120, height: height))
    context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
    context.fill(CGRect(x: width - 120, y: 0, width: 120, height: height))
    let image = try XCTUnwrap(context.makeImage())
    let data = NSMutableData()
    let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
      data, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    return data as Data
  }

  private func containsDominantColor(_ image: CGImage, red: Bool) throws -> Bool {
    guard let provider = image.dataProvider, let data = provider.data else { return false }
    let bytes = CFDataGetBytePtr(data)!
    let stride = max(1, image.width / 128)
    for row in Swift.stride(from: 0, to: image.height, by: max(1, image.height / 32)) {
      for column in Swift.stride(from: 0, to: image.width, by: stride) {
        let offset = row * image.bytesPerRow + column * 4
        let first = Int(bytes[offset])
        let third = Int(bytes[offset + 2])
        if red ? (first > third + 60) : (third > first + 60) { return true }
      }
    }
    return false
  }

  private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
  }
}
// swiftlint:enable type_body_length

private actor SuspendingPreprocessingHook: ImagePreprocessingHook {
  private var produced = false
  private var continuation: CheckedContinuation<Void, Never>?

  func didProduceOutput(_ image: ProcessedImage) async throws {
    produced = true
    await withCheckedContinuation { continuation = $0 }
  }

  func waitUntilOutputExists() async {
    while !produced { await Task.yield() }
  }

  func resume() { continuation?.resume(); continuation = nil }
}

private extension XCTestCase {
  func XCTAssertThrowsErrorAsync(
    expected: (any Error)? = nil,
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async {
    do {
      try await expression()
      XCTFail("Expected error", file: file, line: line)
    } catch {
      if let expected = expected as? ImagePreprocessorError {
        XCTAssertEqual(error as? ImagePreprocessorError, expected, file: file, line: line)
      }
    }
  }
}

private final class DeleteFailsOnceImageFileRemover: OwnedImageFileRemoving, @unchecked Sendable {
  private let lock = NSLock()
  private(set) var attemptCount = 0

  func remove(_ url: URL) throws {
    lock.lock()
    attemptCount += 1
    let shouldFail = attemptCount == 1
    lock.unlock()
    if shouldFail { throw POSIXError(.EIO) }
    try FileManager.default.removeItem(at: url)
  }
}

private final class RecordingCameraSessionRunner: CameraSessionRunning, @unchecked Sendable {
  private let lock = NSLock()
  private(set) var startCount = 0
  private(set) var stopCount = 0

  func start() { lock.lock(); startCount += 1; lock.unlock() }
  func stop() { lock.lock(); stopCount += 1; lock.unlock() }
}

private actor SuspendingCameraImagePersister: CameraImagePersisting {
  let lease: OwnedImageFileLease
  private var started = false
  private var continuation: CheckedContinuation<Void, Never>?

  init(lease: OwnedImageFileLease) { self.lease = lease }

  func persist(_ data: Data) async throws -> OwnedImageFileLease {
    started = true
    await withCheckedContinuation { continuation = $0 }
    return lease
  }

  func waitUntilStarted() async {
    while !started { await Task.yield() }
  }

  func resume() { continuation?.resume(); continuation = nil }
}
