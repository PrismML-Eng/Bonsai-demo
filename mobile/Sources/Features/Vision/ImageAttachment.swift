import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers
// Descriptor confinement intentionally keeps the complete storage transaction auditable.
// swiftlint:disable file_length type_body_length

enum ImageDetailPolicy: String, Codable, CaseIterable, Sendable {
  case fast1024
  case fullDetail

  var title: String { self == .fast1024 ? "Fast ~1,024" : "Full detail" }
}

enum ImageAttachmentLifecycle: String, Codable, Sendable {
  case managedDraft
  case persisted
}

struct PixelSize: Codable, Equatable, Sendable {
  let width: Int
  let height: Int
  var pixelCount: Int? {
    let result = width.multipliedReportingOverflow(by: height)
    return result.overflow ? nil : result.partialValue
  }
}

struct ImageAttachmentReference: Codable, Equatable, Identifiable, Sendable {
  static let maximumBytes = ManagedAttachmentStore.maximumSourceBytes
  static let maximumPixels = ManagedAttachmentStore.maximumSourcePixels
  let id: UUID
  let managedRelativePath: String
  let pixelSize: PixelSize
  let byteCount: Int64
  let contentType: String
  let detailPolicy: ImageDetailPolicy
  let accessibleLabel: String
  let lifecycle: ImageAttachmentLifecycle

  init(
    id: UUID, managedRelativePath: String, pixelSize: PixelSize, byteCount: Int64,
    contentType: String, detailPolicy: ImageDetailPolicy, accessibleLabel: String,
    lifecycle: ImageAttachmentLifecycle = .persisted
  ) throws {
    guard Self.isSafeBasename(managedRelativePath), byteCount > 0,
          byteCount <= Self.maximumBytes, pixelSize.width > 0, pixelSize.height > 0,
          let count = pixelSize.pixelCount, count <= Self.maximumPixels,
          Self.validatedImageType(for: contentType) != nil,
          !accessibleLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          accessibleLabel.count <= 512 else { throw AttachmentStoreError.invalidReference }
    self.id = id
    self.managedRelativePath = managedRelativePath
    self.pixelSize = pixelSize
    self.byteCount = byteCount
    self.contentType = contentType
    self.detailPolicy = detailPolicy
    self.accessibleLabel = accessibleLabel
    self.lifecycle = lifecycle
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      id: values.decode(UUID.self, forKey: .id),
      managedRelativePath: values.decode(String.self, forKey: .managedRelativePath),
      pixelSize: values.decode(PixelSize.self, forKey: .pixelSize),
      byteCount: values.decode(Int64.self, forKey: .byteCount),
      contentType: values.decode(String.self, forKey: .contentType),
      detailPolicy: values.decode(ImageDetailPolicy.self, forKey: .detailPolicy),
      accessibleLabel: values.decode(String.self, forKey: .accessibleLabel),
      lifecycle: values.decode(ImageAttachmentLifecycle.self, forKey: .lifecycle))
  }

  private static func validatedImageType(for contentType: String) -> UTType? {
    if let type = UTType(mimeType: contentType), type.conforms(to: .image) { return type }
    if let type = UTType(contentType), type.conforms(to: .image) { return type }
    return nil
  }

  private static func isSafeBasename(_ path: String) -> Bool {
    !path.isEmpty && path.count <= 255
      && path == URL(fileURLWithPath: path).lastPathComponent
      && !path.contains("/") && !path.contains("\\") && path != "." && path != ".."
  }
}

struct ImageAttachment: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  let originalFilename: String
  let managedRelativePath: String
  let pixelSize: PixelSize
  let byteCount: Int64
  let contentType: String
  var detailPolicy: ImageDetailPolicy
  var lifecycle: ImageAttachmentLifecycle
  let accessibleLabel: String

  func persistedReference() throws -> ImageAttachmentReference {
    try .init(id: id, managedRelativePath: managedRelativePath, pixelSize: pixelSize,
              byteCount: byteCount, contentType: contentType, detailPolicy: detailPolicy,
              accessibleLabel: accessibleLabel, lifecycle: .persisted)
  }
}

enum AttachmentStoreError: Error, Equatable, Sendable {
  case unsafePath
  case unsupportedImage
  case sourceTooLarge
  case invalidDimensions
  case copyFailed
  case invalidReference
  case clearInProgress
}

actor ManagedAttachmentStore {
  struct ClearTransaction: Sendable {
    fileprivate let stagingName: String
    fileprivate let leafNames: [String]
  }
  static let maximumSourceBytes: Int64 = 50 * 1_024 * 1_024
  static let maximumSourcePixels = 50_000_000

  private let root: URL
  private let rootDescriptor: Int32
  private var activeClear: ClearTransaction?

  init(root: URL) throws {
    self.root = root.standardizedFileURL
    var status = stat()
    if lstat(self.root.path, &status) == 0 {
      guard status.st_mode & S_IFMT == S_IFDIR else { throw AttachmentStoreError.unsafePath }
    } else {
      guard errno == ENOENT else { throw AttachmentStoreError.unsafePath }
      try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
    }
    let descriptor = Darwin.open(
      self.root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard descriptor >= 0 else { throw AttachmentStoreError.unsafePath }
    guard fstat(descriptor, &status) == 0, status.st_mode & S_IFMT == S_IFDIR else {
      Darwin.close(descriptor)
      throw AttachmentStoreError.unsafePath
    }
    rootDescriptor = descriptor
  }

  deinit { Darwin.close(rootDescriptor) }

  func importImage(
    from source: URL,
    detailPolicy: ImageDetailPolicy,
    accessibleLabel: String
  ) throws -> ImageAttachment {
    guard activeClear == nil else { throw AttachmentStoreError.clearInProgress }
    let scoped = source.startAccessingSecurityScopedResource()
    defer { if scoped { source.stopAccessingSecurityScopedResource() } }
    let sourceDescriptor = Darwin.open(source.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    guard sourceDescriptor >= 0 else { throw AttachmentStoreError.unsupportedImage }
    defer { Darwin.close(sourceDescriptor) }
    var status = stat()
    guard fstat(sourceDescriptor, &status) == 0,
          status.st_mode & S_IFMT == S_IFREG else { throw AttachmentStoreError.unsupportedImage }
    let byteCount = Int64(status.st_size)
    guard byteCount > 0, byteCount <= Self.maximumSourceBytes else {
      throw AttachmentStoreError.sourceTooLarge
    }
    let sourceData = try Self.readAll(sourceDescriptor)
    guard let imageSource = CGImageSourceCreateWithData(sourceData as CFData, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil)
            as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int,
          width > 0, height > 0,
          let pixels = PixelSize(width: width, height: height).pixelCount,
          pixels <= Self.maximumSourcePixels else {
      throw AttachmentStoreError.invalidDimensions
    }
    let orientation = CGImagePropertyOrientation(
      rawValue: UInt32(properties[kCGImagePropertyOrientation] as? Int ?? 1)) ?? .up
    let normalized = orientation.rotatesDimensions
      ? PixelSize(width: height, height: width) : PixelSize(width: width, height: height)
    let id = UUID()
    let sourceType = CGImageSourceGetType(imageSource) as String?
    guard let type = sourceType.flatMap(UTType.init), type.conforms(to: .image) else {
      throw AttachmentStoreError.unsupportedImage
    }
    let extensionName = type.preferredFilenameExtension ?? "image"
    let relativePath = "\(id.uuidString.lowercased()).\(extensionName.lowercased())"
    try writeManaged(sourceData, destination: relativePath)
    return ImageAttachment(
      id: id, originalFilename: source.lastPathComponent, managedRelativePath: relativePath,
      pixelSize: normalized, byteCount: byteCount, contentType: type.identifier,
      detailPolicy: detailPolicy, lifecycle: .managedDraft,
      accessibleLabel: accessibleLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? "Attached image" : accessibleLabel)
  }

  func importImage(
    data: Data,
    suggestedFilename: String,
    detailPolicy: ImageDetailPolicy,
    accessibleLabel: String
  ) throws -> ImageAttachment {
    guard activeClear == nil else { throw AttachmentStoreError.clearInProgress }
    guard !data.isEmpty, data.count <= Self.maximumSourceBytes else {
      throw AttachmentStoreError.sourceTooLarge
    }
    guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil)
            as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int,
          let sourceType = CGImageSourceGetType(imageSource) as String?,
          let type = UTType(sourceType), type.conforms(to: .image),
          let pixels = PixelSize(width: width, height: height).pixelCount,
          pixels <= Self.maximumSourcePixels else { throw AttachmentStoreError.invalidDimensions }
    let orientation = CGImagePropertyOrientation(
      rawValue: UInt32(properties[kCGImagePropertyOrientation] as? Int ?? 1)) ?? .up
    let normalized = orientation.rotatesDimensions
      ? PixelSize(width: height, height: width) : PixelSize(width: width, height: height)
    let id = UUID()
    let relativePath = "\(id.uuidString.lowercased()).\(type.preferredFilenameExtension ?? "image")"
    try writeManaged(data, destination: relativePath)
    let imported = ImageAttachment(
      id: id, originalFilename: URL(fileURLWithPath: suggestedFilename).lastPathComponent,
      managedRelativePath: relativePath, pixelSize: normalized, byteCount: Int64(data.count),
      contentType: type.identifier, detailPolicy: detailPolicy, lifecycle: .managedDraft,
      accessibleLabel: accessibleLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? "Attached image" : accessibleLabel)
    return ImageAttachment(
      id: imported.id, originalFilename: URL(fileURLWithPath: suggestedFilename).lastPathComponent,
      managedRelativePath: imported.managedRelativePath, pixelSize: imported.pixelSize,
      byteCount: imported.byteCount, contentType: imported.contentType,
      detailPolicy: imported.detailPolicy, lifecycle: imported.lifecycle,
      accessibleLabel: imported.accessibleLabel)
  }

  func url(for attachment: ImageAttachment) throws -> URL {
    try confinedURL(relativePath: attachment.managedRelativePath)
  }

  func url(for reference: ImageAttachmentReference) throws -> URL {
    try confinedURL(relativePath: reference.managedRelativePath)
  }

  func data(for reference: ImageAttachmentReference) throws -> Data {
    guard activeClear == nil else { throw AttachmentStoreError.clearInProgress }
    let name = try confinedBasename(reference.managedRelativePath)
    let descriptor = name.withCString {
      openat(rootDescriptor, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    }
    guard descriptor >= 0 else { throw AttachmentStoreError.unsafePath }
    defer { Darwin.close(descriptor) }
    var status = stat()
    guard fstat(descriptor, &status) == 0,
          status.st_mode & S_IFMT == S_IFREG,
          status.st_size == reference.byteCount else { throw AttachmentStoreError.invalidReference }
    return try Self.readAll(descriptor)
  }

  func delete(_ attachment: ImageAttachment) throws {
    guard activeClear == nil else { throw AttachmentStoreError.clearInProgress }
    let name = try confinedBasename(attachment.managedRelativePath)
    try rejectNonRegularLeaf(name)
    let result = name.withCString { unlinkat(rootDescriptor, $0, 0) }
    guard result == 0 || errno == ENOENT else { throw AttachmentStoreError.copyFailed }
    _ = fsync(rootDescriptor)
  }

  func clearAll() throws {
    let transaction = try prepareClear()
    try commitClear(transaction)
  }

  func prepareClear() throws -> ClearTransaction {
    guard activeClear == nil else { throw AttachmentStoreError.clearInProgress }
    let names = try managedLeafNames()
    let stagingName = ".clear-\(UUID().uuidString.lowercased())"
    guard stagingName.withCString({ mkdirat(rootDescriptor, $0, mode_t(0o700)) }) == 0 else {
      throw AttachmentStoreError.copyFailed
    }
    let staging = stagingName.withCString {
      openat(rootDescriptor, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    }
    guard staging >= 0 else {
      stagingName.withCString { _ = unlinkat(rootDescriptor, $0, AT_REMOVEDIR) }
      throw AttachmentStoreError.copyFailed
    }
    defer { Darwin.close(staging) }
    var moved: [String] = []
    do {
      for name in names {
        guard name.withCString({ sourceName in
          name.withCString { destinationName in
            renameat(rootDescriptor, sourceName, staging, destinationName)
          }
        }) == 0 else { throw AttachmentStoreError.copyFailed }
        moved.append(name)
      }
      guard fsync(rootDescriptor) == 0, fsync(staging) == 0 else {
        throw AttachmentStoreError.copyFailed
      }
      let transaction = ClearTransaction(stagingName: stagingName, leafNames: names)
      activeClear = transaction
      return transaction
    } catch {
      for name in moved.reversed() {
        name.withCString { sourceName in
          name.withCString { destinationName in
            _ = renameat(staging, sourceName, rootDescriptor, destinationName)
          }
        }
      }
      stagingName.withCString { _ = unlinkat(rootDescriptor, $0, AT_REMOVEDIR) }
      throw error
    }
  }

  func rollbackClear(_ transaction: ClearTransaction) throws {
    guard activeClear?.stagingName == transaction.stagingName else {
      throw AttachmentStoreError.clearInProgress
    }
    let staging = transaction.stagingName.withCString {
      openat(rootDescriptor, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    }
    guard staging >= 0 else { return }
    defer { Darwin.close(staging) }
    for name in transaction.leafNames {
      let result = name.withCString { sourceName in
        name.withCString { destinationName in
          renameat(staging, sourceName, rootDescriptor, destinationName)
        }
      }
      guard result == 0 || errno == ENOENT else { throw AttachmentStoreError.copyFailed }
    }
    guard transaction.stagingName.withCString({
      unlinkat(rootDescriptor, $0, AT_REMOVEDIR)
    }) == 0 else { throw AttachmentStoreError.copyFailed }
    _ = fsync(rootDescriptor)
    activeClear = nil
  }

  func commitClear(_ transaction: ClearTransaction) throws {
    guard activeClear?.stagingName == transaction.stagingName else {
      throw AttachmentStoreError.clearInProgress
    }
    defer { activeClear = nil }
    let staging = transaction.stagingName.withCString {
      openat(rootDescriptor, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    }
    guard staging >= 0 else { return }
    defer { Darwin.close(staging) }
    for name in transaction.leafNames { name.withCString { _ = unlinkat(staging, $0, 0) } }
    transaction.stagingName.withCString { _ = unlinkat(rootDescriptor, $0, AT_REMOVEDIR) }
    _ = fsync(rootDescriptor)
  }

  private func managedLeafNames() throws -> [String] {
    var names: [String] = []
    guard let directory = fdopendir(dup(rootDescriptor)) else { throw AttachmentStoreError.copyFailed }
    defer { closedir(directory) }
    while let entry = readdir(directory) {
      let name = withUnsafePointer(to: entry.pointee.d_name) {
        $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
      }
      guard name != ".", name != ".." else { continue }
      var status = stat()
      let result = name.withCString { fstatat(rootDescriptor, $0, &status, AT_SYMLINK_NOFOLLOW) }
      guard result == 0 else { throw AttachmentStoreError.copyFailed }
      if status.st_mode & S_IFMT == S_IFREG {
        names.append(name)
      } else if name == ".processed", status.st_mode & S_IFMT == S_IFDIR {
        try clearLegacyProcessedDirectory()
      } else if name.hasPrefix(".clear-"), status.st_mode & S_IFMT == S_IFDIR {
        continue
      } else if status.st_mode & S_IFMT == S_IFLNK {
        throw AttachmentStoreError.unsafePath
      } else {
        throw AttachmentStoreError.unsafePath
      }
    }
    return names
  }

  private func confinedURL(relativePath: String) throws -> URL {
    let name = try confinedBasename(relativePath)
    try ensurePathStillReferencesRoot()
    try rejectNonRegularLeaf(name)
    let candidate = root.appending(path: relativePath).standardizedFileURL
    guard candidate.deletingLastPathComponent().path == root.path else {
      throw AttachmentStoreError.unsafePath
    }
    return candidate
  }

  private func confinedBasename(_ path: String) throws -> String {
    guard !path.isEmpty, path.count <= 255,
          path == URL(fileURLWithPath: path).lastPathComponent,
          !path.contains("/"), !path.contains("\\"), path != ".", path != ".." else {
      throw AttachmentStoreError.unsafePath
    }
    return path
  }

  private func ensurePathStillReferencesRoot() throws {
    var retained = stat()
    var current = stat()
    guard fstat(rootDescriptor, &retained) == 0,
          lstat(root.path, &current) == 0,
          current.st_mode & S_IFMT == S_IFDIR,
          retained.st_dev == current.st_dev,
          retained.st_ino == current.st_ino else { throw AttachmentStoreError.unsafePath }
  }

  private func rejectNonRegularLeaf(_ name: String) throws {
    var status = stat()
    let result = name.withCString { fstatat(rootDescriptor, $0, &status, AT_SYMLINK_NOFOLLOW) }
    if result != 0 {
      if errno == ENOENT { return }
      throw AttachmentStoreError.copyFailed
    }
    guard status.st_mode & S_IFMT == S_IFREG else { throw AttachmentStoreError.unsafePath }
  }

  private func writeManaged(_ data: Data, destination: String) throws {
    let name = try confinedBasename(destination)
    try ensurePathStillReferencesRoot()
    try rejectNonRegularLeaf(name)
    let temporary = ".import-\(UUID().uuidString.lowercased())"
    let descriptor = temporary.withCString {
      openat(rootDescriptor, $0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
             mode_t(0o600))
    }
    guard descriptor >= 0 else { throw AttachmentStoreError.copyFailed }
    var promoted = false
    defer {
      Darwin.close(descriptor)
      if !promoted { temporary.withCString { _ = unlinkat(rootDescriptor, $0, 0) } }
    }
    try Self.writeAll(data, descriptor: descriptor)
    guard fsync(descriptor) == 0 else { throw AttachmentStoreError.copyFailed }
    try Task.checkCancellation()
    let result = temporary.withCString { temporaryName in
      name.withCString { destinationName in
        renameat(rootDescriptor, temporaryName, rootDescriptor, destinationName)
      }
    }
    guard result == 0 else { throw AttachmentStoreError.copyFailed }
    promoted = true
    guard fsync(rootDescriptor) == 0 else { throw AttachmentStoreError.copyFailed }
  }

  private func clearLegacyProcessedDirectory() throws {
    let descriptor = ".processed".withCString {
      openat(rootDescriptor, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    }
    guard descriptor >= 0, let directory = fdopendir(descriptor) else {
      if descriptor >= 0 { Darwin.close(descriptor) }
      throw AttachmentStoreError.unsafePath
    }
    defer { closedir(directory) }
    while let entry = readdir(directory) {
      let name = withUnsafePointer(to: entry.pointee.d_name) {
        $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
      }
      guard name != ".", name != ".." else { continue }
      var status = stat()
      guard name.withCString({ fstatat(descriptor, $0, &status, AT_SYMLINK_NOFOLLOW) }) == 0,
            status.st_mode & S_IFMT == S_IFREG,
            name.withCString({ unlinkat(descriptor, $0, 0) }) == 0 else {
        throw AttachmentStoreError.unsafePath
      }
    }
    guard ".processed".withCString({ unlinkat(rootDescriptor, $0, AT_REMOVEDIR) }) == 0 else {
      throw AttachmentStoreError.copyFailed
    }
  }

  private static func readAll(_ descriptor: Int32) throws -> Data {
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
    while true {
      try Task.checkCancellation()
      let count = Darwin.read(descriptor, &buffer, buffer.count)
      if count == 0 { return data }
      guard count > 0 else {
        if errno == EINTR { continue }
        throw AttachmentStoreError.copyFailed
      }
      guard Int64(data.count) + Int64(count) <= maximumSourceBytes else {
        throw AttachmentStoreError.sourceTooLarge
      }
      data.append(buffer, count: count)
    }
  }

  private static func writeAll(_ data: Data, descriptor: Int32) throws {
    try data.withUnsafeBytes { bytes in
      var offset = 0
      while offset < bytes.count {
        try Task.checkCancellation()
        let count = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
        guard count > 0 else {
          if errno == EINTR { continue }
          throw AttachmentStoreError.copyFailed
        }
        offset += count
      }
    }
  }
}

protocol AttachmentServing: Sendable {
  func importImage(
    from source: URL, policy: ImageDetailPolicy, accessibleLabel: String
  ) async throws -> ImageAttachment
  func importImage(
    data: Data, filename: String, policy: ImageDetailPolicy, accessibleLabel: String
  ) async throws -> ImageAttachment
  func delete(_ attachment: ImageAttachment) async throws
}

struct LiveAttachmentService: AttachmentServing, Sendable {
  let store: ManagedAttachmentStore

  func importImage(
    from source: URL, policy: ImageDetailPolicy, accessibleLabel: String
  ) async throws -> ImageAttachment {
    try await store.importImage(
      from: source, detailPolicy: policy, accessibleLabel: accessibleLabel)
  }

  func importImage(
    data: Data, filename: String, policy: ImageDetailPolicy, accessibleLabel: String
  ) async throws -> ImageAttachment {
    try await store.importImage(
      data: data, suggestedFilename: filename, detailPolicy: policy,
      accessibleLabel: accessibleLabel)
  }

  func delete(_ attachment: ImageAttachment) async throws {
    try await store.delete(attachment)
  }
}

private extension CGImagePropertyOrientation {
  var rotatesDimensions: Bool {
    switch self {
    case .left, .leftMirrored, .right, .rightMirrored: true
    default: false
    }
  }
}
// swiftlint:enable file_length type_body_length
