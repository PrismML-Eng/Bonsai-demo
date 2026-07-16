import SwiftUI

struct AgentActivityView: View {
  let activities: [AgentActivityPresentation]
  let respond: (ActivityAction) async -> Void

  var body: some View {
    if !activities.isEmpty {
      VStack(alignment: .leading, spacing: QuietGardenTheme.spacingS) {
        Text("Agent activity").font(.headline).accessibilityAddTraits(.isHeader)
        ForEach(activities) { activity in
          HStack(alignment: .top, spacing: QuietGardenTheme.spacingS) {
            Image(systemName: icon(activity.kind)).foregroundStyle(color(activity.kind))
              .frame(width: 20)
            VStack(alignment: .leading, spacing: QuietGardenTheme.spacingXS) {
              Text(activity.title).font(.subheadline.weight(.medium))
              if let detail = activity.detail {
                Text(detail).font(.footnote).foregroundStyle(.secondary)
                  .fixedSize(horizontal: false, vertical: true)
              }
              if !activity.actions.isEmpty {
                ViewThatFits(in: .horizontal) {
                  HStack {
                    ForEach(Array(activity.actions.enumerated()), id: \.offset) { _, action in
                      styledButton(action)
                    }
                  }
                  VStack(alignment: .leading) {
                  ForEach(Array(activity.actions.enumerated()), id: \.offset) { _, action in
                    styledButton(action)
                  }
                  }
                }
              }
            }
          }
          .accessibilityElement(children: .contain)
          if activity.id != activities.last?.id { Divider() }
        }
      }
      .padding(QuietGardenTheme.spacingM)
      .background(QuietGardenTheme.raised, in: RoundedRectangle(cornerRadius: QuietGardenTheme.rowRadius))
      .accessibilityIdentifier(UIAccessibility.activity)
    }
  }

  private func activityButton(_ action: ActivityActionPresentation) -> some View {
    Button(action.label) { Task { await respond(action.action) } }
      .frame(minHeight: QuietGardenTheme.minimumTarget)
      .accessibilityIdentifier(action.label == "Allow once"
        ? UIAccessibility.approvalAllow : UIAccessibility.approvalDeny)
  }

  @ViewBuilder private func styledButton(_ action: ActivityActionPresentation) -> some View {
    if action.label == "Allow once" {
      activityButton(action).buttonStyle(.borderedProminent).tint(QuietGardenTheme.accent)
    } else { activityButton(action).buttonStyle(.bordered) }
  }

  private func icon(_ kind: AgentActivityKind) -> String {
    switch kind {
    case .requested: "arrow.turn.down.right"
    case .pendingApproval: "hand.raised.fill"
    case .running: "gearshape.2"
    case .result: "checkmark.circle.fill"
    case .denied: "nosign"
    case .failed: "exclamationmark.triangle.fill"
    case .terminal: "flag.checkered"
    }
  }
  private func color(_ kind: AgentActivityKind) -> Color {
    switch kind {
    case .result: QuietGardenTheme.success
    case .failed, .denied: QuietGardenTheme.danger
    case .pendingApproval: QuietGardenTheme.warning
    default: QuietGardenTheme.accent
    }
  }
}
