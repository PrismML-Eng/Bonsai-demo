import SwiftUI

struct ComposerView: View {
  @Bindable var viewModel: ChatViewModel

  var body: some View {
    VStack(spacing: QuietGardenTheme.spacingS) {
      Divider()
      HStack(alignment: .bottom, spacing: QuietGardenTheme.spacingS) {
        Button { } label: { Image(systemName: "paperclip") }
          .buttonStyle(.plain).frame(width: 44, height: 44)
          .accessibilityLabel("Add attachment")
          .accessibilityHint("Image attachments arrive in the next demo milestone")
        TextField("Message Bonsai", text: $viewModel.draft, axis: .vertical)
          .lineLimit(1...6).textFieldStyle(.plain).padding(.vertical, 11)
          .accessibilityIdentifier(UIAccessibility.chatComposer)
          .onSubmit { if viewModel.canSend { Task { await viewModel.send() } } }
        if viewModel.isGenerating {
          Button { Task { await viewModel.stop() } } label: { Image(systemName: "stop.fill") }
            .buttonStyle(.borderedProminent).tint(QuietGardenTheme.danger)
            .frame(minWidth: 44, minHeight: 44).accessibilityLabel("Stop generation")
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
      HStack {
        Picker("Reasoning effort", selection: $viewModel.effort) {
          ForEach(ReasoningEffort.allCases) { effort in Text(effort.rawValue).tag(effort) }
        }
        .pickerStyle(.menu).fixedSize().frame(minHeight: QuietGardenTheme.minimumTarget)
        .accessibilityValue(viewModel.effort.rawValue)
        Spacer()
        Label("Local only", systemImage: "lock.fill").font(.caption).foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, QuietGardenTheme.spacingM)
    .padding(.bottom, QuietGardenTheme.spacingS)
    .background(.bar)
  }
}
