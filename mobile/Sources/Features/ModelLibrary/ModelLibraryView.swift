import SwiftUI
import UniformTypeIdentifiers

struct ModelLibraryView: View {
  @Bindable var viewModel: ModelLibraryViewModel

  var body: some View {
    List {
      Section {
        ForEach(viewModel.rows) { row in modelRow(row) }
      } header: {
        Text("Models").font(.headline).accessibilityAddTraits(.isHeader)
      } footer: {
        Label("Model files and conversations stay on this device.", systemImage: "lock.fill")
          .font(.footnote).foregroundStyle(.secondary)
      }
    }
    .listStyle(.sidebar)
    .navigationTitle("Bonsai")
    .accessibilityIdentifier(UIAccessibility.modelLibrary)
    .task { viewModel.start() }
    .fileImporter(isPresented: Binding(
      get: { viewModel.pendingImportModelID != nil },
      set: { if !$0 { viewModel.pendingImportModelID = nil } }
    ), allowedContentTypes: [.folder, .zip], allowsMultipleSelection: false) { result in
      guard case .success(let urls) = result, let source = urls.first else { return }
      Task {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        await viewModel.importPending(from: source)
      }
    }
    .safeAreaInset(edge: .bottom) {
      if let error = viewModel.errorMessage {
        HStack { Image(systemName: "exclamationmark.triangle.fill"); Text(error); Spacer() }
          .font(.footnote).padding().background(.regularMaterial)
          .accessibilityLabel("Model action failed. \(error). Try the action again.")
      }
    }
  }

  private func modelRow(_ row: ModelRowPresentation) -> some View {
    VStack(alignment: .leading, spacing: QuietGardenTheme.spacingS) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: QuietGardenTheme.spacingXS) {
          Text(row.name).font(.headline)
          Text(row.footprint).font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        if row.isLoaded {
          Label("Loaded", systemImage: "leaf.fill").font(.caption.bold())
            .foregroundStyle(QuietGardenTheme.success)
        }
      }
      Text(row.status).font(.subheadline).accessibilityLabel("Status: \(row.status)")
      if let detail = row.detail {
        Text(detail).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }
      if let progress = row.progress {
        ProgressView(value: progress).tint(QuietGardenTheme.accent)
          .accessibilityValue(Text("\(Int(progress * 100)) percent"))
      }
      HStack(spacing: QuietGardenTheme.spacingS) {
        if let action = row.primaryAction { actionButton(action, row: row, prominent: true) }
        if let recovery = row.recovery { actionButton(recovery, row: row, prominent: true) }
        ForEach(Array(row.secondaryActions.enumerated()), id: \.offset) { _, action in
          actionButton(action, row: row, prominent: false)
        }
      }
    }
    .padding(.vertical, QuietGardenTheme.spacingXS)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("model.\(row.id.rawValue)")
  }

  private func actionButton(
    _ action: ModelActionPresentation, row: ModelRowPresentation, prominent: Bool
  ) -> some View {
    Group {
      if prominent {
        actionControl(action, row: row).buttonStyle(.borderedProminent).tint(QuietGardenTheme.accent)
      } else {
        actionControl(action, row: row).buttonStyle(.bordered)
      }
    }
  }

  private func actionControl(_ action: ModelActionPresentation, row: ModelRowPresentation) -> some View {
    Button(action.label) { Task { await viewModel.perform(action, modelID: row.id) } }
      .disabled(viewModel.inFlightModelIDs.contains(row.id))
      .controlSize(.regular).frame(minHeight: QuietGardenTheme.minimumTarget)
      .accessibilityHint("\(action.label) \(row.name)")
  }
}
