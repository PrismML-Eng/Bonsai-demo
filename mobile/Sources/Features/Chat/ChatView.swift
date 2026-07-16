import SwiftUI

struct ChatView: View {
  @Bindable var viewModel: ChatViewModel

  var body: some View {
    VStack(spacing: 0) {
      if viewModel.messages.isEmpty { emptyState } else { conversation }
      ComposerView(viewModel: viewModel)
    }
    .background(QuietGardenTheme.paper)
    .navigationTitle("On-device chat")
    .toolbar { ToolbarItem(placement: .primaryAction) { modelStatus } }
  }

  private var modelStatus: some View {
    Label(viewModel.isModelReady ? "Bonsai 27B loaded" : "No model loaded",
          systemImage: viewModel.isModelReady ? "leaf.fill" : "leaf")
      .font(.caption).foregroundStyle(viewModel.isModelReady ? QuietGardenTheme.success : .secondary)
      .accessibilityLabel(viewModel.isModelReady ? "Bonsai 27B is loaded locally" : "No model is loaded")
  }

  private var emptyState: some View {
    ContentUnavailableView {
      Label("A quiet place to think", systemImage: "leaf")
        .font(.system(.title2, design: .serif, weight: .semibold))
    } description: {
      Text(viewModel.isModelReady ? "Ask a question. Nothing leaves this device."
           : "Load Bonsai 27B from the Model Library to begin.")
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var conversation: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: QuietGardenTheme.spacingL) {
          ForEach(viewModel.messages) { message in
            messageView(message).id(message.id)
          }
          if !viewModel.reasoning.text.isEmpty || viewModel.metrics != nil {
            ReasoningDisclosure(reasoning: viewModel.reasoning, metrics: viewModel.metrics)
          }
          AgentActivityView(activities: viewModel.activities) { action in
            await viewModel.respond(to: action)
          }
          if let recovery = viewModel.recovery {
            HStack {
              Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(QuietGardenTheme.danger)
              Text(viewModel.terminalStatus ?? "Generation failed")
              Spacer()
              Button(recovery.label) { Task { await viewModel.retry() } }.buttonStyle(.bordered)
            }
            .accessibilityElement(children: .contain)
          }
        }
        .frame(maxWidth: 760, alignment: .leading)
        .padding(QuietGardenTheme.spacingL)
      }
      .accessibilityIdentifier(UIAccessibility.chatList)
      .onChange(of: viewModel.messages.last?.text) {
        if let id = viewModel.messages.last?.id { proxy.scrollTo(id, anchor: .bottom) }
      }
    }
  }

  private func messageView(_ message: ChatMessagePresentation) -> some View {
    VStack(alignment: .leading, spacing: QuietGardenTheme.spacingXS) {
      Text(message.role == .user ? "You" : "Bonsai")
        .font(.caption.weight(.semibold)).foregroundStyle(message.role == .assistant
          ? QuietGardenTheme.accent : .secondary)
      Text(message.text.isEmpty ? "Thinking…" : message.text)
        .font(.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(message.role == .user ? QuietGardenTheme.spacingM : 0)
    .background(message.role == .user ? QuietGardenTheme.subtle : .clear,
                in: RoundedRectangle(cornerRadius: QuietGardenTheme.rowRadius))
    .accessibilityElement(children: .combine)
    .accessibilityLabel(message.role == .user ? "You: \(message.text)" : "Bonsai: \(message.text)")
  }
}
