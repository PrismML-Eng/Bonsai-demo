import SwiftUI

struct ReasoningDisclosure: View {
  let reasoning: ReasoningPresentation
  let metrics: GenerationMetrics?
  @State private var isExpanded = false

  var body: some View {
    DisclosureGroup(isExpanded: $isExpanded) {
      if reasoning.text.isEmpty {
        Text("No reasoning tokens yet.").foregroundStyle(.secondary)
      } else {
        Text(reasoning.text).textSelection(.enabled)
      }
      if let metrics {
        Divider()
        HStack {
          metric("Prompt", "\(metrics.promptTokenCount) tokens")
          metric("Generated", "\(metrics.generatedTokenCount) tokens")
          metric("Speed", String(format: "%.1f tok/s", metrics.tokensPerSecond))
        }
        .accessibilityIdentifier(UIAccessibility.metrics)
      }
    } label: {
      Label(reasoning.status, systemImage: "lightbulb.min")
        .font(.subheadline.weight(.medium))
    }
    .tint(QuietGardenTheme.accent)
    .accessibilityIdentifier(UIAccessibility.reasoning)
    .accessibilityHint(isExpanded ? "Collapse model reasoning" : "Expand model reasoning")
  }

  private func metric(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title).font(.caption2).foregroundStyle(.secondary)
      Text(value).font(.caption.monospacedDigit())
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
