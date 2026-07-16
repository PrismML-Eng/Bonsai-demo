#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import BonsaiMobile

@MainActor
final class QuietGardenRenderingTests: XCTestCase {
  private struct RenderCase {
    let fixture: UIFixture
    let size: CGSize
    let scheme: ColorScheme
    let filename: String
  }

  func testDeterministicFixturesRenderAtRegularAndCompactSizes() throws {
    let directory = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appending(path: ".superpowers/artifacts/task-07", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let cases = [
      RenderCase(fixture: .streamingReasoning, size: .init(width: 1_180, height: 760),
                 scheme: .light, filename: "regular-light.png"),
      RenderCase(fixture: .pendingNoteWrite, size: .init(width: 430, height: 760),
                 scheme: .dark, filename: "compact-dark.png")
    ]

    for renderCase in cases {
      let content = QuietGardenFixtureCanvas(fixture: renderCase.fixture,
                                             compact: renderCase.size.width < 700)
        .frame(width: renderCase.size.width, height: renderCase.size.height)
        .environment(\.colorScheme, renderCase.scheme)
      let renderer = ImageRenderer(content: content)
      renderer.scale = 1
      let image = try XCTUnwrap(renderer.nsImage)
      XCTAssertEqual(image.size, renderCase.size)
      let representation = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
      let png = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
      try png.write(to: directory.appending(path: renderCase.filename), options: .atomic)
    }
  }
}

private struct QuietGardenFixtureCanvas: View {
  let fixture: UIFixture
  let compact: Bool

  var body: some View {
    let state = fixture.makeState()
    HStack(spacing: 0) {
      if !compact { library(state).frame(width: 310) }
      chat(state)
    }
    .background(QuietGardenTheme.paper)
  }

  private func library(_ state: UIFixtureState) -> some View {
    let rows = ModelLibraryViewModel.rows(snapshot: state.library, loadedModelID: .oneBit27B,
                                          platform: state.platform)
    return VStack(alignment: .leading, spacing: QuietGardenTheme.spacingL) {
      Text("Bonsai").font(.system(.title, design: .serif, weight: .semibold))
      Text("MODELS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
      ForEach(rows) { row in
        VStack(alignment: .leading, spacing: QuietGardenTheme.spacingXS) {
          Text(row.name).font(.headline)
          Text(row.footprint).font(.caption).foregroundStyle(.secondary)
          Text(row.status).font(.subheadline)
          if let detail = row.detail { Text(detail).font(.footnote).foregroundStyle(.secondary) }
        }
        Divider()
      }
      Spacer()
      Text("🔒  Model files and conversations stay on this device.")
        .font(.footnote).foregroundStyle(.secondary)
    }
    .padding(QuietGardenTheme.spacingL)
    .background(QuietGardenTheme.raised)
  }

  // A snapshot-only composition intentionally keeps every visual region in one fixed canvas.
  // swiftlint:disable:next function_body_length
  private func chat(_ state: UIFixtureState) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("On-device chat").font(.title2.bold())
          Text("Bonsai 27B loaded · Local only").font(.caption).foregroundStyle(QuietGardenTheme.success)
        }
        Spacer()
      }
      .padding(QuietGardenTheme.spacingL)
      Divider()
      VStack(alignment: .leading, spacing: QuietGardenTheme.spacingL) {
          ForEach(state.messages) { message in
            VStack(alignment: .leading, spacing: QuietGardenTheme.spacingXS) {
              Text(message.role == .user ? "You" : "Bonsai")
                .font(.caption.bold()).foregroundStyle(message.role == .assistant
                  ? QuietGardenTheme.accent : .secondary)
              Text(message.text).font(.body)
            }
            .padding(message.role == .user ? QuietGardenTheme.spacingM : 0)
            .background(message.role == .user ? QuietGardenTheme.subtle : .clear,
                        in: RoundedRectangle(cornerRadius: QuietGardenTheme.rowRadius))
          }
          if !state.reasoning.text.isEmpty {
            VStack(alignment: .leading, spacing: QuietGardenTheme.spacingXS) {
              Text("⌄  \(state.reasoning.status)").font(.subheadline.bold())
              Text(state.reasoning.text).font(.footnote).foregroundStyle(.secondary)
              if let metrics = state.metrics {
                Text("\(metrics.promptTokenCount) prompt · \(metrics.generatedTokenCount) generated · "
                     + String(format: "%.1f tok/s", metrics.tokensPerSecond))
                  .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
              }
            }
          }
          ForEach(state.activities) { activity in
            VStack(alignment: .leading, spacing: QuietGardenTheme.spacingS) {
              Text(activity.title).font(.headline)
              if let detail = activity.detail { Text(detail).font(.footnote).foregroundStyle(.secondary) }
              HStack {
                ForEach(Array(activity.actions.enumerated()), id: \.offset) { _, action in
                  Text(action.label).font(.subheadline.bold()).padding(.horizontal, 14).frame(height: 38)
                    .background(action.label == "Allow once" ? QuietGardenTheme.accent : .clear,
                                in: RoundedRectangle(cornerRadius: QuietGardenTheme.controlRadius))
                    .overlay(RoundedRectangle(cornerRadius: QuietGardenTheme.controlRadius)
                      .stroke(.secondary.opacity(0.35)))
                    .foregroundStyle(action.label == "Allow once" ? .white : .primary)
                }
              }
            }
            .padding(QuietGardenTheme.spacingM)
            .background(QuietGardenTheme.raised,
                        in: RoundedRectangle(cornerRadius: QuietGardenTheme.rowRadius))
          }
      }
      .frame(maxWidth: 720, maxHeight: .infinity, alignment: .topLeading)
      .padding(QuietGardenTheme.spacingL)
      Divider()
      HStack {
        Text("Message Bonsai").foregroundStyle(.secondary)
        Spacer()
        Text("Reasoning: Medium").font(.caption)
        Text("↑").font(.headline).foregroundStyle(.white).frame(width: 44, height: 44)
          .background(QuietGardenTheme.accent,
                      in: RoundedRectangle(cornerRadius: QuietGardenTheme.controlRadius))
      }
      .padding(QuietGardenTheme.spacingM).background(QuietGardenTheme.raised)
    }
  }
}
#endif
