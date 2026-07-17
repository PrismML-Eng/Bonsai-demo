import SwiftUI

enum SettingsIntent: Equatable, Sendable {
  case setDefaultImageDetail(ImageDetailPolicy)
  case clearConversationsNotesAndImages
}

protocol SettingsServing: Sendable {
  func recoverPendingClear() async throws
  func clearConversationsNotesAndImages() async throws
}

actor LiveSettingsService: SettingsServing {
  private let clearCoordinator: ApplicationDataClearCoordinator

  init(
    root: URL,
    conversations: ConversationCoordinator,
    notes: NotesStore,
    attachments: ManagedAttachmentStore
  ) throws {
    clearCoordinator = try ApplicationDataClearCoordinator(
      root: root, conversations: conversations, notes: notes, attachments: attachments)
  }

  func recoverPendingClear() async throws {
    try await clearCoordinator.recoverIfNeeded()
  }

  func clearConversationsNotesAndImages() async throws {
    try await clearCoordinator.clearAll()
  }
}

final class PersistedImageDetailSettings: @unchecked Sendable {
  static let key = "defaultImageDetail"
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) { self.defaults = defaults }

  var value: ImageDetailPolicy {
    guard let raw = defaults.string(forKey: Self.key) else { return .fast1024 }
    return ImageDetailPolicy(rawValue: raw) ?? .fast1024
  }

  func set(_ value: ImageDetailPolicy) { defaults.set(value.rawValue, forKey: Self.key) }
}

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var detailPolicy: ImageDetailPolicy
  let detailSettings: PersistedImageDetailSettings
  let isClearInProgress: Bool
  let onIntent: @MainActor (SettingsIntent) async -> Void
  @State private var confirmsClear = false

  init(
    detailSettings: PersistedImageDetailSettings,
    isClearInProgress: Bool = false,
    onIntent: @escaping @MainActor (SettingsIntent) async -> Void
  ) {
    self.detailSettings = detailSettings
    self.isClearInProgress = isClearInProgress
    self.onIntent = onIntent
    _detailPolicy = State(initialValue: detailSettings.value)
  }

  var body: some View {
    Form {
      Section("Privacy") {
        Label("Inference stays on this device", systemImage: "lock.shield.fill")
        Text(
          "Images, prompts, notes, and diagnostics are stored locally. "
            + "Images are never uploaded or used for analytics."
        )
          .foregroundStyle(.secondary)
      }
      Section("Image detail") {
        Picker("Default image detail", selection: Binding(
          get: { detailPolicy },
          set: { policy in
            detailPolicy = policy
            detailSettings.set(policy)
            Task { await onIntent(.setDefaultImageDetail(policy)) }
          }
        )) {
          ForEach(ImageDetailPolicy.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        Text(
          "Fast is much snappier. Full detail is best for OCR, screenshots, "
            + "and small text, but uses more memory and time."
        )
          .font(.footnote).foregroundStyle(.secondary)
      }
      Section("Storage") {
        Text("Models are managed in Model Library. Conversation images are private copies in app storage.")
          .foregroundStyle(.secondary)
      }
      Section("Diagnostics") {
        Text(
          "Diagnostics contain timings, model revision, thermal state, and counts—"
            + "never prompt, image, note, or answer content."
        )
          .foregroundStyle(.secondary)
      }
      Section("Local data") {
        Button("Clear conversations, notes, and images", role: .destructive) {
          confirmsClear = true
        }
        .disabled(isClearInProgress)
        if isClearInProgress {
          Label("Finishing private-data clear…", systemImage: "hourglass")
            .foregroundStyle(.secondary)
            .accessibilityHint("Clear controls remain unavailable until recovery finishes")
        }
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Settings")
    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    .accessibilityIdentifier(UIAccessibility.settings)
    .confirmationDialog(
      "Clear private local data?", isPresented: $confirmsClear, titleVisibility: .visible
    ) {
      Button("Clear conversations, notes, and images", role: .destructive) {
        Task { await onIntent(.clearConversationsNotesAndImages) }
      }
      .disabled(isClearInProgress)
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Downloaded models are kept. This cannot be undone.")
    }
  }
}
