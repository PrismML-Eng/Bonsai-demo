import SwiftUI

enum SettingsIntent: Equatable, Sendable {
  case setDefaultImageDetail(ImageDetailPolicy)
  case clearConversationsNotesAndImages
}

protocol SettingsServing: Sendable {
  func clearConversationsNotesAndImages() async throws
}

actor LiveSettingsService: SettingsServing {
  let conversations: ConversationCoordinator
  let notes: NotesStore
  let attachments: ManagedAttachmentStore

  init(
    conversations: ConversationCoordinator,
    notes: NotesStore,
    attachments: ManagedAttachmentStore
  ) {
    self.conversations = conversations
    self.notes = notes
    self.attachments = attachments
  }

  func clearConversationsNotesAndImages() async throws {
    let noteSnapshot = try await notes.clearSnapshot()
    let attachmentTransaction = try await attachments.prepareClear()
    do {
      try await notes.clearAll()
      try await conversations.clearAllConversations()
    } catch {
      try? await notes.restoreClearSnapshot(noteSnapshot)
      try? await attachments.rollbackClear(attachmentTransaction)
      throw error
    }
    try await attachments.commitClear(attachmentTransaction)
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
  let onIntent: @MainActor (SettingsIntent) async -> Void
  @State private var confirmsClear = false

  init(
    detailSettings: PersistedImageDetailSettings,
    onIntent: @escaping @MainActor (SettingsIntent) async -> Void
  ) {
    self.detailSettings = detailSettings
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
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Downloaded models are kept. This cannot be undone.")
    }
  }
}
