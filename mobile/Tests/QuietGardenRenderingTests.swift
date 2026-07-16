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

    try render(
      RootView(composition: .fixture(.streamingReasoning, platform: .mac))
        .environment(\.colorScheme, .light),
      size: .init(width: 1_180, height: 760),
      to: directory.appending(path: "regular-light.png")
    )
    try render(
      RootView(composition: .fixture(.pendingNoteWrite, platform: .iPhone))
        .environment(\.colorScheme, .dark)
        .environment(\.dynamicTypeSize, .accessibility3),
      size: .init(width: 430, height: 900),
      to: directory.appending(path: "compact-dark-accessibility.png")
    )
    try render(
      RootView(composition: .fixture(
        .readyChat,
        platform: .iPhone,
        showsLibrary: true
      ))
      .environment(\.colorScheme, .dark)
      .environment(\.dynamicTypeSize, .accessibility3),
      size: .init(width: 430, height: 900),
      to: directory.appending(path: "compact-library-sheet-accessibility.png"),
      captureAttachedSheet: true
    )
    let library = RootComposition.fixture(.readyChat)
    try render(
      NavigationStack {
        ModelLibraryView(viewModel: library.libraryViewModel)
      }
      .environment(\.colorScheme, .dark)
      .environment(\.dynamicTypeSize, .accessibility5),
      size: .init(width: 320, height: 900),
      to: directory.appending(path: "model-library-accessibility.png")
    )
  }

  private func render<V: View>(
    _ content: V,
    size: CGSize,
    to destination: URL,
    captureAttachedSheet: Bool = false
  ) throws {
    let hosting = NSHostingView(rootView: content.frame(width: size.width, height: size.height))
    hosting.frame = NSRect(origin: .zero, size: size)
    let window = NSWindow(
      contentRect: hosting.frame,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false)
    window.contentView = hosting
    window.orderFront(nil)
    // NavigationSplitView and attached sheets settle asynchronously on macOS.
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    let captureView = if captureAttachedSheet {
      try XCTUnwrap(window.attachedSheet?.contentView)
    } else {
      hosting
    }
    if captureAttachedSheet {
      window.attachedSheet?.setContentSize(size)
      captureView.frame = NSRect(origin: .zero, size: size)
    }
    captureView.layoutSubtreeIfNeeded()
    captureView.displayIfNeeded()
    let bitmap = try XCTUnwrap(captureView.bitmapImageRepForCachingDisplay(in: captureView.bounds))
    captureView.cacheDisplay(in: captureView.bounds, to: bitmap)
    let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    try png.write(to: destination, options: .atomic)
    window.orderOut(nil)
  }
}
#endif
