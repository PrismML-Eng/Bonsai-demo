import CoreGraphics
import Darwin
import Foundation
import ImageIO

enum ImagePreprocessorError: Error, Equatable, Sendable {
  case invalidConfiguration
  case invalidDimensions
  case sourceOutsideManagedContainer
  case sourceTooLarge
  case corruptOrUnsupported
  case outputFailure
}

/// Immutable Core Graphics storage. Identity is used only to reject duplicate request bindings.
final class ProcessedImageBuffer: @unchecked Sendable, Equatable {
  let id: UUID
  let image: CGImage

  init(id: UUID = UUID(), image: CGImage) {
    self.id = id
    self.image = image
  }

  static func == (lhs: ProcessedImageBuffer, rhs: ProcessedImageBuffer) -> Bool { lhs.id == rhs.id }
}

struct ProcessedImage: Equatable, Sendable {
  let buffer: ProcessedImageBuffer
  let pixelSize: PixelSize
  let preprocessingDuration: Duration
}

protocol ImagePreprocessingHook: Sendable {
  func didProduceOutput(_ image: ProcessedImage) async throws
}

struct NoopImagePreprocessingHook: ImagePreprocessingHook {
  func didProduceOutput(_ image: ProcessedImage) async throws {}
}

struct ImagePreprocessor: Sendable {
  static let maximumSourceBytes: Int64 = 50 * 1_024 * 1_024
  static let maximumSourcePixels = 50_000_000
  static let maximumTokenBudget = 1_048_576
  static let maximumPatchSize = 4_096

  let tokenBudget: Int
  let patchSize: Int
  let hook: any ImagePreprocessingHook

  init(
    tokenBudget: Int = 1_024,
    patchSize: Int = 32,
    hook: any ImagePreprocessingHook = NoopImagePreprocessingHook()
  ) {
    self.tokenBudget = tokenBudget
    self.patchSize = patchSize
    self.hook = hook
  }

  /// Projects the source aspect ratio onto a deterministic bounded patch grid.
  func targetSize(for source: PixelSize) throws -> PixelSize {
    guard (1...Self.maximumTokenBudget).contains(tokenBudget),
          (1...Self.maximumPatchSize).contains(patchSize) else {
      throw ImagePreprocessorError.invalidConfiguration
    }
    guard source.width > 0, source.height > 0,
          source.width <= 100_000, source.height <= 100_000,
          source.pixelCount != nil else { throw ImagePreprocessorError.invalidDimensions }
    let sourcePatches = try patchArea(source)
    guard sourcePatches > tokenBudget else { return source }
    let ratio = Double(source.width) / Double(source.height)
    guard ratio.isFinite, ratio > 0 else { throw ImagePreprocessorError.invalidDimensions }
    var columns = ratio >= 1
      ? Int(ceil(sqrt(Double(tokenBudget) * ratio)))
      : Int(floor(sqrt(Double(tokenBudget) * ratio)))
    var rows = ratio >= 1
      ? Int(floor(sqrt(Double(tokenBudget) / ratio)))
      : Int(ceil(sqrt(Double(tokenBudget) / ratio)))
    columns = max(1, columns)
    rows = max(1, rows)
    while true {
      let area = columns.multipliedReportingOverflow(by: rows)
      guard !area.overflow else { throw ImagePreprocessorError.invalidConfiguration }
      if area.partialValue <= tokenBudget { break }
      if columns >= rows { columns -= 1 } else { rows -= 1 }
    }
    let width = columns.multipliedReportingOverflow(by: patchSize)
    let height = rows.multipliedReportingOverflow(by: patchSize)
    guard !width.overflow, !height.overflow else { throw ImagePreprocessorError.invalidDimensions }
    return .init(width: min(source.width, width.partialValue),
                 height: min(source.height, height.partialValue))
  }

  func normalizedSize(
    pixels: PixelSize, orientation: CGImagePropertyOrientation
  ) throws -> PixelSize {
    _ = try targetSize(for: pixels)
    switch orientation {
    case .left, .leftMirrored, .right, .rightMirrored:
      return .init(width: pixels.height, height: pixels.width)
    default: return pixels
    }
  }

  /// Decoding and drawing run away from the caller actor. Cancellation is forwarded to
  /// the worker and checked between every ImageIO/CoreGraphics stage. The result remains
  /// in immutable memory, so inference never reopens an attacker-replaceable output path.
  func process(
    managedURL: URL, policy: ImageDetailPolicy, managedRoot: URL
  ) async throws -> ProcessedImage {
    try Task.checkCancellation()
    let worker = Task.detached(priority: .userInitiated) {
      try Task.checkCancellation()
      return try self.performProcess(
        managedURL: managedURL, policy: policy, managedRoot: managedRoot)
    }
    let result = try await withTaskCancellationHandler {
      try await worker.value
    } onCancel: {
      worker.cancel()
    }
    try await hook.didProduceOutput(result)
    try Task.checkCancellation()
    return result
  }

  func process(data: Data, policy: ImageDetailPolicy) async throws -> ProcessedImage {
    guard !data.isEmpty, Int64(data.count) <= Self.maximumSourceBytes else {
      throw ImagePreprocessorError.sourceTooLarge
    }
    try Task.checkCancellation()
    let worker = Task.detached(priority: .userInitiated) {
      try Task.checkCancellation()
      return try self.render(data: data, policy: policy)
    }
    let result = try await withTaskCancellationHandler {
      try await worker.value
    } onCancel: {
      worker.cancel()
    }
    try await hook.didProduceOutput(result)
    try Task.checkCancellation()
    return result
  }

  /// Kept as a compatibility cleanup seam. Processed images are memory-owned and create no leaf.
  func removeProcessed(_ image: ProcessedImage, managedRoot: URL) throws {}

  private func performProcess(
    managedURL: URL, policy: ImageDetailPolicy, managedRoot: URL
  ) throws -> ProcessedImage {
    let start = ContinuousClock.now
    let root = managedRoot.standardizedFileURL
    let source = managedURL.standardizedFileURL
    guard source.deletingLastPathComponent() == root,
          Self.safeBasename(source.lastPathComponent) else {
      throw ImagePreprocessorError.sourceOutsideManagedContainer
    }
    let rootDescriptor = Darwin.open(
      root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard rootDescriptor >= 0 else {
      throw ImagePreprocessorError.sourceOutsideManagedContainer
    }
    defer { Darwin.close(rootDescriptor) }
    let sourceDescriptor = source.lastPathComponent.withCString {
      openat(rootDescriptor, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    }
    guard sourceDescriptor >= 0 else { throw ImagePreprocessorError.corruptOrUnsupported }
    defer { Darwin.close(sourceDescriptor) }
    var status = stat()
    guard fstat(sourceDescriptor, &status) == 0,
          status.st_mode & S_IFMT == S_IFREG else {
      throw ImagePreprocessorError.corruptOrUnsupported
    }
    guard status.st_size > 0, status.st_size <= Self.maximumSourceBytes else {
      throw ImagePreprocessorError.sourceTooLarge
    }
    let data = try Self.readAll(sourceDescriptor)
    return try render(data: data, policy: policy, startedAt: start)
  }

  // swiftlint:disable:next function_body_length
  private func render(
    data: Data, policy: ImageDetailPolicy, startedAt: ContinuousClock.Instant? = nil
  ) throws -> ProcessedImage {
    let start = startedAt ?? ContinuousClock().now
    try Task.checkCancellation()
    guard let sourceImage = CGImageSourceCreateWithData(data as CFData, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(sourceImage, 0, nil)
            as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int else {
      throw ImagePreprocessorError.corruptOrUnsupported
    }
    let orientation = CGImagePropertyOrientation(
      rawValue: UInt32(properties[kCGImagePropertyOrientation] as? Int ?? 1)) ?? .up
    let normalized = try normalizedSize(
      pixels: .init(width: width, height: height), orientation: orientation)
    guard let pixels = normalized.pixelCount, pixels <= Self.maximumSourcePixels else {
      throw ImagePreprocessorError.sourceTooLarge
    }
    let target = policy == .fast1024 ? try targetSize(for: normalized) : normalized
    try Task.checkCancellation()
    guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(sourceImage, 0, [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: max(target.width, target.height),
      kCGImageSourceShouldCacheImmediately: true
    ] as CFDictionary) else { throw ImagePreprocessorError.corruptOrUnsupported }
    try Task.checkCancellation()
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
            data: nil, width: target.width, height: target.height, bitsPerComponent: 8,
            bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
      throw ImagePreprocessorError.outputFailure
    }
    context.setFillColor(CGColor(gray: 0.5, alpha: 1))
    context.fill(CGRect(origin: .zero, size: CGSize(width: target.width, height: target.height)))
    let scale = min(
      CGFloat(target.width) / CGFloat(thumbnail.width),
      CGFloat(target.height) / CGFloat(thumbnail.height))
    let drawWidth = CGFloat(thumbnail.width) * scale
    let drawHeight = CGFloat(thumbnail.height) * scale
    context.interpolationQuality = .high
    context.draw(thumbnail, in: .init(
      x: (CGFloat(target.width) - drawWidth) / 2,
      y: (CGFloat(target.height) - drawHeight) / 2,
      width: drawWidth, height: drawHeight))
    try Task.checkCancellation()
    guard let image = context.makeImage() else { throw ImagePreprocessorError.outputFailure }
    try Task.checkCancellation()
    return .init(
      buffer: .init(image: image),
      pixelSize: .init(width: image.width, height: image.height),
      preprocessingDuration: start.duration(to: ContinuousClock().now))
  }

  private static func safeBasename(_ name: String) -> Bool {
    !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\\")
  }

  private static func readAll(_ descriptor: Int32) throws -> Data {
    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
    while true {
      try Task.checkCancellation()
      let count = Darwin.read(descriptor, &buffer, buffer.count)
      if count == 0 { return result }
      guard count > 0 else {
        if errno == EINTR { continue }
        throw ImagePreprocessorError.corruptOrUnsupported
      }
      guard Int64(result.count) + Int64(count) <= maximumSourceBytes else {
        throw ImagePreprocessorError.sourceTooLarge
      }
      result.append(buffer, count: count)
    }
  }

  private func patchArea(_ source: PixelSize) throws -> Int {
    guard (1...Self.maximumTokenBudget).contains(tokenBudget),
          (1...Self.maximumPatchSize).contains(patchSize) else {
      throw ImagePreprocessorError.invalidConfiguration
    }
    let columns = source.width / patchSize + (source.width % patchSize == 0 ? 0 : 1)
    let rows = source.height / patchSize + (source.height % patchSize == 0 ? 0 : 1)
    let area = columns.multipliedReportingOverflow(by: rows)
    guard !area.overflow else { throw ImagePreprocessorError.invalidDimensions }
    return area.partialValue
  }
}
