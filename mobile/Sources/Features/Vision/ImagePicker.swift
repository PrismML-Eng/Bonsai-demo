// Descriptor-copy operations stay contiguous so cleanup is auditable on every exit.
// swiftlint:disable line_length
import CoreTransferable
import Darwin
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

protocol OwnedImageFileRemoving: Sendable {
  func remove(_ url: URL) throws
}

struct SystemOwnedImageFileRemover: OwnedImageFileRemoving {
  func remove(_ url: URL) throws {
    guard Darwin.unlink(url.path) == 0 || errno == ENOENT else {
      throw POSIXError(.init(rawValue: errno)!)
    }
  }
}

enum OwnedImageFileLeaseError: Error, LocalizedError, Sendable {
  case cleanupRetained(path: String, reason: String)

  var errorDescription: String? {
    switch self {
    case .cleanupRetained:
      "A temporary private image could not be deleted and is retained for retry."
    }
  }
}

final class OwnedImageFileLease: @unchecked Sendable {
  let url: URL
  private let lock = NSLock()
  private let remover: any OwnedImageFileRemoving
  private var removed = false

  init(url: URL, remover: any OwnedImageFileRemoving = SystemOwnedImageFileRemover()) {
    self.url = url
    self.remover = remover
    OwnedImageFileCleanupRegistry.shared.track(self)
  }

  var ownsFile: Bool {
    lock.lock(); defer { lock.unlock() }
    return !removed
  }

  func remove() throws {
    lock.lock(); defer { lock.unlock() }
    guard !removed else { return }
    try remover.remove(url)
    removed = true
  }
}

final class OwnedImageFileCleanupRegistry: @unchecked Sendable {
  static let shared = OwnedImageFileCleanupRegistry()
  private let lock = NSLock()
  private var owned: [URL: OwnedImageFileLease] = [:]
  private var retryable: Set<URL> = []

  func track(_ lease: OwnedImageFileLease) {
    lock.lock(); owned[lease.url] = lease; lock.unlock()
  }

  func removeOrRetain(_ lease: OwnedImageFileLease) throws {
    do {
      try lease.remove()
      lock.lock()
      owned[lease.url] = nil
      retryable.remove(lease.url)
      lock.unlock()
    } catch {
      lock.lock()
      owned[lease.url] = lease
      retryable.insert(lease.url)
      lock.unlock()
      throw OwnedImageFileLeaseError.cleanupRetained(
        path: lease.url.path, reason: String(describing: error))
    }
  }

  func retryRetained() -> [OwnedImageFileLeaseError] {
    lock.lock(); let leases = retryable.compactMap { owned[$0] }; lock.unlock()
    return leases.compactMap { lease in
      do {
        try removeOrRetain(lease)
        return nil
      } catch let error as OwnedImageFileLeaseError {
        return error
      } catch {
        return .cleanupRetained(path: lease.url.path, reason: String(describing: error))
      }
    }
  }
}
struct PickedPhotoFile: Transferable, Sendable {
  let lease: OwnedImageFileLease
  var url: URL { lease.url }

  static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(importedContentType: .image) { received in
      .init(lease: try copyProviderFile(received.file))
    }
  }
  // swiftlint:disable:next cyclomatic_complexity
  static func copyProviderFile(_ source: URL) throws -> OwnedImageFileLease {
    if let failure = OwnedImageFileCleanupRegistry.shared.retryRetained().first {
      throw failure
    }
    let input = Darwin.open(source.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    guard input >= 0 else { throw AttachmentStoreError.unsupportedImage }
    defer { Darwin.close(input) }
    var status = stat()
    guard fstat(input, &status) == 0, status.st_mode & S_IFMT == S_IFREG else { throw AttachmentStoreError.unsupportedImage }
    guard status.st_size > 0, status.st_size <= ManagedAttachmentStore.maximumSourceBytes else { throw AttachmentStoreError.sourceTooLarge }
    let destination = FileManager.default.temporaryDirectory.appending(path: "photo-transfer-\(UUID().uuidString).owned")
    let output = Darwin.open(destination.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
    guard output >= 0 else { throw AttachmentStoreError.copyFailed }
    let lease = OwnedImageFileLease(url: destination)
    defer { Darwin.close(output) }
    do {
      var copied: Int64 = 0; var buffer = [UInt8](repeating: 0, count: 65_536)
      while true {
        try Task.checkCancellation(); let count = Darwin.read(input, &buffer, buffer.count)
        if count == 0 { break }; guard count > 0 else { throw AttachmentStoreError.copyFailed }
        copied += Int64(count); guard copied <= ManagedAttachmentStore.maximumSourceBytes else { throw AttachmentStoreError.sourceTooLarge }
        var offset = 0
        while offset < count {
          let written = buffer.withUnsafeBytes { Darwin.write(output, $0.baseAddress!.advanced(by: offset), count - offset) }
          guard written > 0 else { throw AttachmentStoreError.copyFailed }; offset += written
        }
      }
      guard copied == Int64(status.st_size), fsync(output) == 0 else { throw AttachmentStoreError.copyFailed }
      return lease
    } catch {
      let primary = error
      try OwnedImageFileCleanupRegistry.shared.removeOrRetain(lease)
      throw primary
    }
  }
}

struct ImagePicker: View {
  let isDisabled: Bool
  let onPicked: @MainActor (URL) async -> Void
  let onFailure: @MainActor (String) -> Void
  @State private var selection: PhotosPickerItem?

  var body: some View {
    PhotosPicker(selection: $selection, matching: .images) {
      Image(systemName: "photo.on.rectangle")
        .frame(minWidth: QuietGardenTheme.minimumTarget,
               minHeight: QuietGardenTheme.minimumTarget)
    }
    .disabled(isDisabled)
    .accessibilityLabel("Choose photo")
    .accessibilityHint("Opens your photo library only when activated")
    .accessibilityIdentifier(UIAccessibility.photoPicker)
    .onChange(of: selection) {
      guard let selection else { return }
      Task {
        defer { self.selection = nil }
        var loadedFile: PickedPhotoFile?
        do {
          guard let file = try await selection.loadTransferable(type: PickedPhotoFile.self) else {
            onFailure("The selected photo could not be loaded. Choose another photo and retry.")
            return
          }
          loadedFile = file
          try Task.checkCancellation()
          await onPicked(file.url)
          do {
            try OwnedImageFileCleanupRegistry.shared.removeOrRetain(file.lease)
          } catch {
            onFailure(error.localizedDescription)
          }
        } catch {
          if let lease = loadedFile?.lease, lease.ownsFile {
            do {
              try OwnedImageFileCleanupRegistry.shared.removeOrRetain(lease)
            } catch {
              onFailure(error.localizedDescription)
              return
            }
          }
          onFailure("The selected photo could not be loaded: \(error.localizedDescription). Retry.")
        }
      }
    }
  }
}
// swiftlint:enable line_length
