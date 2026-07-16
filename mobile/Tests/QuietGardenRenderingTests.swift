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
    switch destination.lastPathComponent {
    case "regular-light.png":
      assertInk(in: bitmap, rect: NSRect(x: 12, y: 20, width: 330, height: 720),
                brighterThan: nil, minimum: 300,
                message: "regular RootView must visibly render model and conversation navigation")
    case "compact-dark-accessibility.png":
      assertInk(in: bitmap, rect: NSRect(x: 12, y: 790, width: 406, height: 100),
                brighterThan: 0.55, minimum: 150,
                message: "compact RootView must visibly render its model/library/conversation header")
    default: break
    }
    let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    try png.write(to: destination, options: .atomic)
    window.orderOut(nil)
  }

  private func assertInk(
    in bitmap: NSBitmapImageRep, rect: NSRect, brighterThan: CGFloat?, minimum: Int, message: String
  ) {
    var contrastingPixels = 0
    for row in Int(rect.minY)..<Int(rect.maxY) {
      for column in Int(rect.minX)..<Int(rect.maxX) {
        guard let color = bitmap.colorAt(x: column, y: row)?.usingColorSpace(.deviceRGB) else { continue }
        let luminance = 0.2126 * color.redComponent
          + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
        let isInk = if let brighterThan { luminance > brighterThan } else { luminance < 0.55 }
        if isInk { contrastingPixels += 1 }
      }
    }
    XCTAssertGreaterThan(contrastingPixels, minimum, message)
  }

}
#endif
