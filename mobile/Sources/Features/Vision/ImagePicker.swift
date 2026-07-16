import CoreTransferable
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

private struct PickedPhotoFile: Transferable {
  let url: URL

  static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(importedContentType: .image) { received in
      .init(url: received.file)
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
        do {
          guard let file = try await selection.loadTransferable(type: PickedPhotoFile.self) else {
            onFailure("The selected photo could not be loaded. Choose another photo and retry.")
            return
          }
          let values = try file.url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
          guard values.isRegularFile == true,
                let size = values.fileSize, size > 0,
                Int64(size) <= ManagedAttachmentStore.maximumSourceBytes else {
            onFailure("The selected photo is too large. Choose an image under 50 MB.")
            return
          }
          await onPicked(file.url)
        } catch {
          onFailure("The selected photo could not be loaded: \(error.localizedDescription). Retry.")
        }
      }
    }
  }
}
