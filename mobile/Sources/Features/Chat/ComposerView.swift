import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

struct ComposerView: View {
  @Bindable var viewModel: ChatViewModel
  @FocusState private var composerFocused: Bool
  @State private var showsFileImporter = false
  #if os(iOS)
  @State private var showsCamera = false
  #endif

  var body: some View {
    VStack(alignment: .leading, spacing: QuietGardenTheme.spacingS) {
      Divider()
      if let attachment = viewModel.draftAttachment { attachmentPreview(attachment) }
      if let error = viewModel.attachmentError {
        HStack {
          Label(error, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote).foregroundStyle(QuietGardenTheme.danger)
            .accessibilityIdentifier(UIAccessibility.attachmentError)
          #if os(iOS)
          if error.localizedCaseInsensitiveContains("denied") {
            Button("Open Settings") {
              if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
              }
            }
            .accessibilityHint("Opens system settings so you can allow camera access")
          }
          #endif
        }
      }
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .bottom, spacing: QuietGardenTheme.spacingS) { composerContent }
        VStack(alignment: .leading, spacing: QuietGardenTheme.spacingS) { composerContent }
      }
      HStack {
        if viewModel.supportsReasoning {
          Picker("Reasoning effort", selection: $viewModel.effort) {
            ForEach(ReasoningEffort.allCases) { effort in Text(effort.rawValue).tag(effort) }
          }
          .pickerStyle(.menu).fixedSize().frame(minHeight: QuietGardenTheme.minimumTarget)
          .accessibilityValue(viewModel.effort.rawValue)
        }
        Spacer()
        Label("Local only", systemImage: "lock.fill").font(.caption).foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, QuietGardenTheme.spacingM)
    .padding(.bottom, QuietGardenTheme.spacingS)
    .background(.bar)
    .fileImporter(isPresented: $showsFileImporter, allowedContentTypes: [.image]) { result in
      Task {
        switch result {
        case .success(let url): await viewModel.importAttachment(from: url)
        case .failure(let error):
          viewModel.presentAttachmentError(
            "The selected image file could not be opened: \(error.localizedDescription). Retry.")
        }
        composerFocused = true
      }
    }
    #if os(iOS)
    .sheet(
      isPresented: $showsCamera,
      onDismiss: { composerFocused = true },
      content: {
        CameraPicker(
        onPicked: { url in
          await viewModel.importAttachment(from: url, label: "Camera photo")
          showsCamera = false
        },
        onCancel: { showsCamera = false },
        onFailure: { message in
          viewModel.presentAttachmentError("\(message) Retry.")
          showsCamera = false
        })
        .ignoresSafeArea()
      })
    #endif
    .alert("Send full-detail image?", isPresented: Binding(
      get: { viewModel.showsFullDetailWarning },
      set: { if !$0 { viewModel.dismissFullDetailWarning() } }
    )) {
      Button("Send Full detail") { Task { await viewModel.confirmFullDetailSend() } }
      Button("Use Fast ~1,024") {
        viewModel.setDetailPolicy(.fast1024)
        Task { await viewModel.send() }
      }
      Button("Cancel", role: .cancel) { composerFocused = true }
    } message: {
      Text("Full detail uses more memory and takes longer. Use it for OCR, screenshots, or small text.")
    }
  }

  @ViewBuilder private var composerContent: some View {
    attachmentControls
    TextField("Message Bonsai", text: $viewModel.draft, axis: .vertical)
      .lineLimit(1...6).textFieldStyle(.plain).padding(.vertical, 11)
      .focused($composerFocused)
      .accessibilityIdentifier(UIAccessibility.chatComposer)
      .onSubmit { if viewModel.canSend { Task { await viewModel.send() } } }
    sendOrStop
  }

  private var attachmentControls: some View {
    HStack(spacing: QuietGardenTheme.spacingXS) {
      ImagePicker(isDisabled: !viewModel.allowsPrivateDataWrites, onPicked: { url in
        await viewModel.importAttachment(from: url)
        composerFocused = true
      }, onFailure: { message in
        viewModel.presentAttachmentError(message)
        composerFocused = true
      })
      Button { showsFileImporter = true } label: {
        Image(systemName: "folder")
          .frame(minWidth: QuietGardenTheme.minimumTarget,
                 minHeight: QuietGardenTheme.minimumTarget)
      }
      .buttonStyle(.plain).disabled(!viewModel.allowsPrivateDataWrites)
      .accessibilityLabel("Choose image file")
      .accessibilityHint("Copies a selected image into private app storage")
      .accessibilityIdentifier(UIAccessibility.filePicker)
      #if os(iOS)
      Button {
        Task {
          if await CameraPicker.requestAccess() {
            showsCamera = true
          } else {
            viewModel.presentAttachmentError(
              "Camera access is denied. Open Settings to allow camera access.")
          }
        }
      } label: {
        Image(systemName: "camera")
          .frame(minWidth: QuietGardenTheme.minimumTarget,
                 minHeight: QuietGardenTheme.minimumTarget)
      }
      .buttonStyle(.plain).disabled(!viewModel.allowsPrivateDataWrites || !CameraPicker.isAvailable)
      .accessibilityLabel("Take photo")
      .accessibilityHint(CameraPicker.isAvailable
        ? "Requests camera access only when activated"
        : "Camera is unavailable on this device")
      .accessibilityIdentifier(UIAccessibility.cameraPicker)
      if !CameraPicker.isAvailable {
        Text("Camera unavailable")
          .font(.caption).foregroundStyle(.secondary)
          .accessibilityLabel("Camera is unavailable on this device. Choose a photo or image file instead.")
      }
      #endif
    }
  }

  @ViewBuilder private var sendOrStop: some View {
    if viewModel.isGenerating {
      Button { Task { await viewModel.stop() } } label: { Image(systemName: "stop.fill") }
        .buttonStyle(.borderedProminent).tint(QuietGardenTheme.danger)
        .frame(minWidth: 44, minHeight: 44).accessibilityLabel("Stop generation")
        .accessibilityHint("Stops local generation and keeps your draft image")
        .accessibilityIdentifier(UIAccessibility.stop)
        .keyboardShortcut(.cancelAction)
    } else {
      Button { Task { await viewModel.send() } } label: { Image(systemName: "arrow.up") }
        .buttonStyle(.borderedProminent).tint(QuietGardenTheme.accent)
        .frame(minWidth: 44, minHeight: 44).disabled(!viewModel.canSend)
        .accessibilityLabel("Send message").accessibilityIdentifier(UIAccessibility.send)
        .keyboardShortcut(.return, modifiers: [.command])
    }
  }

  private func attachmentPreview(_ attachment: ImageAttachment) -> some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: QuietGardenTheme.spacingS) { attachmentPreviewContent(attachment) }
      VStack(alignment: .leading, spacing: QuietGardenTheme.spacingS) {
        attachmentPreviewContent(attachment)
      }
    }
    .padding(QuietGardenTheme.spacingS)
    .background(QuietGardenTheme.subtle,
                in: RoundedRectangle(cornerRadius: QuietGardenTheme.controlRadius))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(UIAccessibility.attachmentPreview)
  }

  @ViewBuilder private func attachmentPreviewContent(_ attachment: ImageAttachment) -> some View {
    Label(attachment.accessibleLabel, systemImage: "photo.fill")
      .lineLimit(2)
      .accessibilityLabel("Image preview, \(attachment.accessibleLabel), "
        + "\(attachment.pixelSize.width) by \(attachment.pixelSize.height) pixels")
    Picker("Image detail", selection: Binding(
      get: { attachment.detailPolicy }, set: { viewModel.setDetailPolicy($0) }
    )) {
      ForEach(ImageDetailPolicy.allCases, id: \.self) { Text($0.title).tag($0) }
    }
    .pickerStyle(.menu).frame(minHeight: QuietGardenTheme.minimumTarget)
    .disabled(viewModel.isGenerating)
    .accessibilityValue(attachment.detailPolicy.title)
    .accessibilityIdentifier(UIAccessibility.detailPolicy)
    Spacer(minLength: 0)
    Button(role: .destructive) { Task { await viewModel.removeAttachment() } } label: {
      Image(systemName: "xmark")
        .frame(minWidth: QuietGardenTheme.minimumTarget,
               minHeight: QuietGardenTheme.minimumTarget)
    }
    .buttonStyle(.plain).accessibilityLabel("Remove image")
    .disabled(viewModel.isGenerating)
    .accessibilityHint("Removes this image from the draft and private app storage")
    .accessibilityIdentifier(UIAccessibility.removeAttachment)
  }
}
