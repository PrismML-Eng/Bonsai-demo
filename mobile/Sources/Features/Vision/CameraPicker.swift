import SwiftUI

#if os(iOS)
@preconcurrency import AVFoundation
@preconcurrency import UIKit

private final class CameraImagePayload: @unchecked Sendable {
  let image: UIImage
  init(_ image: UIImage) { self.image = image }
}

private final class CameraCallbacks: @unchecked Sendable {
  let onPicked: @MainActor (URL) async -> Void
  let onCancel: @MainActor () -> Void

  init(
    onPicked: @escaping @MainActor (URL) async -> Void,
    onCancel: @escaping @MainActor () -> Void
  ) {
    self.onPicked = onPicked
    self.onCancel = onCancel
  }
}

struct CameraPicker: UIViewControllerRepresentable {
  let onPicked: @MainActor (URL) async -> Void
  let onCancel: @MainActor () -> Void

  @MainActor static var isAvailable: Bool {
    UIImagePickerController.isSourceTypeAvailable(.camera)
  }

  @MainActor static func requestAccess() async -> Bool {
    guard isAvailable else { return false }
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized: return true
    case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
    case .denied, .restricted: return false
    @unknown default: return false
    }
  }

  func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

  func makeUIViewController(context: Context) -> UIImagePickerController {
    let picker = UIImagePickerController()
    picker.sourceType = .camera
    picker.delegate = context.coordinator
    return picker
  }

  func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

  @MainActor final class Coordinator: NSObject, UIImagePickerControllerDelegate,
    UINavigationControllerDelegate {
    let parent: CameraPicker
    init(parent: CameraPicker) { self.parent = parent }

    func imagePickerController(
      _ picker: UIImagePickerController,
      didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
      if let url = info[.imageURL] as? URL {
        Task { await parent.onPicked(url) }
        return
      }
      guard let image = info[.originalImage] as? UIImage,
            image.size.width > 0, image.size.height > 0,
            image.size.width * image.scale * image.size.height * image.scale
              <= CGFloat(ManagedAttachmentStore.maximumSourcePixels) else {
        parent.onCancel()
        return
      }
      let callbacks = CameraCallbacks(onPicked: parent.onPicked, onCancel: parent.onCancel)
      let payload = CameraImagePayload(image)
      Task.detached(priority: .userInitiated) {
        guard let data = payload.image.jpegData(compressionQuality: 0.9),
              data.count <= ManagedAttachmentStore.maximumSourceBytes else {
          await callbacks.onCancel()
          return
        }
        let url = FileManager.default.temporaryDirectory
          .appending(path: "camera-\(UUID().uuidString.lowercased()).jpg")
        do {
          try data.write(to: url, options: [.atomic, .completeFileProtection])
          await callbacks.onPicked(url)
          try? FileManager.default.removeItem(at: url)
        } catch { await callbacks.onCancel() }
      }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.onCancel() }
  }
}
#else
enum CameraPicker {
  static let isAvailable = false
}
#endif
