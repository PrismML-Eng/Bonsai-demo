// Camera wiring keeps capture delegate signatures and bounded encoded-data checks together.
// swiftlint:disable line_length private_over_fileprivate
import Foundation
import SwiftUI

protocol CameraSessionRunning: Sendable {
  func start()
  func stop()
}

protocol CameraImagePersisting: Sendable {
  func persist(_ data: Data) async throws -> OwnedImageFileLease
}

/// Serializes capture admission and invalidates asynchronous delivery on dismissal.
@MainActor final class CameraCaptureLifecycle {
  private let session: any CameraSessionRunning
  private let persister: any CameraImagePersisting
  private let onPicked: @MainActor (URL) async -> Void
  private let onFailure: @MainActor (any Error) -> Void
  private let onCaptureStateChange: @MainActor (Bool) -> Void
  private var generation: UUID?
  private var persistenceTask: Task<Void, Never>?
  private var persistenceID: UUID?
  private(set) var isCaptureInFlight = false

  init(
    session: any CameraSessionRunning,
    persister: any CameraImagePersisting,
    onPicked: @escaping @MainActor (URL) async -> Void,
    onFailure: @escaping @MainActor (any Error) -> Void,
    onCaptureStateChange: @escaping @MainActor (Bool) -> Void = { _ in }
  ) {
    self.session = session
    self.persister = persister
    self.onPicked = onPicked
    self.onFailure = onFailure
    self.onCaptureStateChange = onCaptureStateChange
  }

  func start() {
    guard generation == nil else { return }
    generation = UUID()
    session.start()
  }

  func stop() {
    guard generation != nil else { return }
    generation = nil
    persistenceTask?.cancel()
    setCaptureInFlight(false)
    session.stop()
  }

  func beginCapture() -> Bool {
    guard generation != nil, !isCaptureInFlight else { return false }
    setCaptureInFlight(true)
    return true
  }

  func completeCapture(data: Data) {
    guard let generation, isCaptureInFlight else { return }
    let operationID = UUID()
    persistenceID = operationID
    let persister = self.persister
    persistenceTask = Task { [weak self] in
      do {
        let lease = try await persister.persist(data)
        guard !Task.isCancelled,
              self?.generation == generation,
              self?.persistenceID == operationID else {
          try? await Self.removeOffMain(lease)
          self?.settle(operationID)
          return
        }
        await self?.onPicked(lease.url)
        do {
          try await Self.removeOffMain(lease)
        } catch {
          self?.onFailure(error)
        }
      } catch is CancellationError {
        // A stopped generation has no UI callback.
      } catch {
        if self?.generation == generation { self?.onFailure(error) }
      }
      self?.settle(operationID)
    }
  }

  func failCapture(_ error: any Error) {
    guard generation != nil, isCaptureInFlight else { return }
    setCaptureInFlight(false)
    onFailure(error)
  }

  func waitUntilIdle() async {
    await persistenceTask?.value
  }

  private func settle(_ operationID: UUID) {
    guard persistenceID == operationID else { return }
    persistenceID = nil
    persistenceTask = nil
    setCaptureInFlight(false)
  }

  private func setCaptureInFlight(_ value: Bool) {
    isCaptureInFlight = value
    onCaptureStateChange(value)
  }

  private nonisolated static func removeOffMain(_ lease: OwnedImageFileLease) async throws {
    try await Task.detached(priority: .utility) {
      try OwnedImageFileCleanupRegistry.shared.removeOrRetain(lease)
    }.value
  }
}

#if os(iOS)
@preconcurrency import AVFoundation
import ImageIO
@preconcurrency import UIKit

enum CameraCaptureError: Error, Equatable, LocalizedError, Sendable {
  case oversized, invalidEncodedImage, writeFailed, captureFailed(String)

  var errorDescription: String? {
    switch self {
    case .oversized: "The camera image is too large."
    case .invalidEncodedImage: "The camera returned an invalid image."
    case .writeFailed: "The private camera copy could not be saved."
    case .captureFailed(let reason): "Camera capture failed: \(reason)"
    }
  }
}
enum CameraEncodedFile {
  static func persist(_ data: Data, maximumBytes: Int64 = ManagedAttachmentStore.maximumSourceBytes) throws -> OwnedImageFileLease {
    if let failure = OwnedImageFileCleanupRegistry.shared.retryRetained().first {
      throw failure
    }
    guard !data.isEmpty, Int64(data.count) <= maximumBytes else { throw CameraCaptureError.oversized }
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int,
          let pixels = PixelSize(width: width, height: height).pixelCount,
          width > 0, height > 0, pixels <= ManagedAttachmentStore.maximumSourcePixels else { throw CameraCaptureError.invalidEncodedImage }
    let url = FileManager.default.temporaryDirectory.appending(path: "camera-\(UUID().uuidString).jpg")
    do { try data.write(to: url, options: [.atomic, .completeFileProtection]) } catch { throw CameraCaptureError.writeFailed }
    return OwnedImageFileLease(url: url)
  }
}
struct CameraEncodedFilePersister: CameraImagePersisting {
  func persist(_ data: Data) async throws -> OwnedImageFileLease {
    try await Task.detached(priority: .userInitiated) {
      try CameraEncodedFile.persist(data)
    }.value
  }
}
fileprivate final class CameraCallbacks: @unchecked Sendable {
  let picked: @MainActor (URL) async -> Void
  let cancel: @MainActor () -> Void
  let failure: @MainActor (String) -> Void
  init(
    _ picked: @escaping @MainActor (URL) async -> Void,
    _ cancel: @escaping @MainActor () -> Void,
    _ failure: @escaping @MainActor (String) -> Void
  ) { self.picked = picked; self.cancel = cancel; self.failure = failure }
}
private final class CaptureSessionRunner: CameraSessionRunning, @unchecked Sendable {
  let session = AVCaptureSession()
  private let queue = DispatchQueue(label: "com.prismml.bonsai.camera.capture")
  func start() { queue.async { [session] in if !session.isRunning { session.startRunning() } } }
  func stop() { queue.async { [session] in if session.isRunning { session.stopRunning() } } }
}
struct CameraPicker: UIViewControllerRepresentable {
  let onPicked: @MainActor (URL) async -> Void
  let onCancel: @MainActor () -> Void
  let onFailure: @MainActor (String) -> Void
  @MainActor static var isAvailable: Bool { AVCaptureDevice.default(for: .video) != nil }
  @MainActor static func requestAccess() async -> Bool {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized: true
    case .notDetermined: await AVCaptureDevice.requestAccess(for: .video)
    default: false
    }
  }
  func makeUIViewController(context: Context) -> CameraCaptureController {
    CameraCaptureController(callbacks: .init(onPicked, onCancel, onFailure))
  }
  func updateUIViewController(_ controller: CameraCaptureController, context: Context) {}
  static func dismantleUIViewController(_ controller: CameraCaptureController, coordinator: Void) {
    controller.stopCapture()
  }
}
@MainActor final class CameraCaptureController: UIViewController, AVCapturePhotoCaptureDelegate {
  private let callbacks: CameraCallbacks
  private let runner = CaptureSessionRunner()
  private let output = AVCapturePhotoOutput()
  private let captureButton = UIButton(type: .system)
  private lazy var lifecycle = CameraCaptureLifecycle(
    session: runner,
    persister: CameraEncodedFilePersister(),
    onPicked: callbacks.picked,
    onFailure: { [callbacks] error in callbacks.failure(error.localizedDescription) },
    onCaptureStateChange: { [weak self] in self?.captureButton.isEnabled = !$0 })
  fileprivate init(callbacks: CameraCallbacks) { self.callbacks = callbacks; super.init(nibName: nil, bundle: nil) }
  @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() {
    super.viewDidLoad()
    let session = runner.session
    guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input), session.canAddOutput(output) else { callbacks.cancel(); return }
    session.addInput(input); session.addOutput(output)
    let preview = AVCaptureVideoPreviewLayer(session: session); preview.frame = view.bounds; preview.videoGravity = .resizeAspectFill; view.layer.addSublayer(preview)
    captureButton.setTitle("Capture", for: .normal); captureButton.accessibilityLabel = "Take photo"; captureButton.addTarget(self, action: #selector(capture), for: .touchUpInside); captureButton.frame = CGRect(x: 20, y: 40, width: 100, height: 60); view.addSubview(captureButton)
    lifecycle.start()
  }
  override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); stopCapture() }
  func stopCapture() { lifecycle.stop() }
  @objc private func capture() {
    guard lifecycle.beginCapture() else { return }
    output.capturePhoto(with: AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg]), delegate: self)
  }
  nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: (any Error)?) {
    guard error == nil, let data = photo.fileDataRepresentation() else {
      let failure = error.map { CameraCaptureError.captureFailed($0.localizedDescription) }
        ?? CameraCaptureError.invalidEncodedImage
      Task { @MainActor in lifecycle.failCapture(failure) }
      return
    }
    Task { @MainActor in lifecycle.completeCapture(data: data) }
  }
}
#else
enum CameraPicker { static let isAvailable = false }
#endif
// swiftlint:enable line_length private_over_fileprivate
