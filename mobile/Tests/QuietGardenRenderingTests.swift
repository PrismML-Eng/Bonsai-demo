#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import BonsaiMobile

@MainActor
final class QuietGardenRenderingTests: XCTestCase {
  func testActualProductViewsRenderRegularCompactAndAccessibilityType() throws {
    let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
      .appending(path: ".superpowers/artifacts/task-07", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let regular = RootComposition.fixture(.streamingReasoning)
    try render(
      HStack(spacing: 0) {
        ModelLibraryView(viewModel: regular.libraryViewModel).frame(width: 380)
        Divider()
        ChatView(viewModel: regular.chatViewModel)
      }
      .environment(\.colorScheme, .light),
      size: .init(width: 1_180, height: 760),
      to: directory.appending(path: "regular-light.png")
    )
    let compact = RootComposition.fixture(.pendingNoteWrite)
    try render(
      ChatView(viewModel: compact.chatViewModel)
        .environment(\.colorScheme, .dark)
        .environment(\.dynamicTypeSize, .accessibility3),
      size: .init(width: 430, height: 900),
      to: directory.appending(path: "compact-dark-accessibility.png")
    )
  }

  private func render<V: View>(_ content: V, size: CGSize, to destination: URL) throws {
    let hosting = NSHostingView(rootView: content.frame(width: size.width, height: size.height))
    hosting.frame = NSRect(origin: .zero, size: size)
    let window = NSWindow(
      contentRect: hosting.frame,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false)
    window.contentView = hosting
    window.orderFront(nil)
    hosting.layoutSubtreeIfNeeded()
    hosting.displayIfNeeded()
    let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
    let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    try png.write(to: destination, options: .atomic)
    window.orderOut(nil)
  }
}
#endif
