#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import BonsaiMobile

@MainActor
final class QuietGardenRenderingTests: XCTestCase {
  func testSemanticRegionOracleRejectsAFlatPlaceholder() throws {
    let bitmap = try XCTUnwrap(NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 200,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: 200, height: 200).fill()

    XCTAssertThrowsError(try requireSemanticRegion(
      in: bitmap,
      rect: NSRect(x: 20, y: 20, width: 160, height: 160),
      meaning: "expected control"))
  }

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
      try requireSemanticRegion(in: bitmap, rect: NSRect(x: 12, y: 685, width: 330, height: 62),
                                meaning: "Bonsai title and loaded-model status")
      try requireSemanticRegion(in: bitmap, rect: NSRect(x: 12, y: 485, width: 330, height: 180),
                                meaning: "conversation navigation and new-conversation control")
      try requireSemanticRegion(in: bitmap, rect: NSRect(x: 390, y: 250, width: 750, height: 430),
                                meaning: "chat turns, reasoning disclosure, and generation metrics")
      try requireSemanticRegion(in: bitmap, rect: NSRect(x: 390, y: 8, width: 750, height: 110),
                                meaning: "chat composer and send control")
    case "compact-dark-accessibility.png":
      try requireSemanticRegion(in: bitmap, rect: NSRect(x: 12, y: 785, width: 406, height: 105),
                                meaning: "compact model-library and conversation controls")
      try requireSemanticRegion(in: bitmap, rect: NSRect(x: 12, y: 405, width: 406, height: 350),
                                meaning: "accessible chat messages")
      try requireSemanticRegion(in: bitmap, rect: NSRect(x: 12, y: 115, width: 406, height: 285),
                                meaning: "note-write approval effect, Allow once, and Deny controls")
      try requireSemanticRegion(in: bitmap, rect: NSRect(x: 12, y: 5, width: 406, height: 105),
                                meaning: "accessible compact composer")
    case "compact-library-sheet-accessibility.png":
      try requireSemanticRegion(in: bitmap, rect: NSRect(x: 12, y: 700, width: 406, height: 175),
                                meaning: "model-library title and first model row")
      try requireSemanticRegion(in: bitmap, rect: NSRect(x: 12, y: 355, width: 406, height: 335),
                                meaning: "both model status, footprint, and action controls")
      try requireSemanticRegion(in: bitmap, rect: NSRect(x: 12, y: 20, width: 406, height: 150),
                                meaning: "on-device privacy restriction copy")
    case "model-library-accessibility.png":
      try requireSemanticRegion(in: bitmap, rect: NSRect(x: 8, y: 610, width: 304, height: 260),
                                meaning: "accessibility-sized Bonsai 27B model row and controls")
      try requireSemanticRegion(in: bitmap, rect: NSRect(x: 8, y: 245, width: 304, height: 350),
                                meaning: "accessibility-sized ternary model row, restriction, and controls")
      try requireSemanticRegion(in: bitmap, rect: NSRect(x: 8, y: 20, width: 304, height: 170),
                                meaning: "local-only model library footer")
    default:
      XCTFail("Every render artifact must have a semantic region contract")
    }
    let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    try png.write(to: destination, options: .atomic)
    window.orderOut(nil)
  }

  private func requireSemanticRegion(
    in bitmap: NSBitmapImageRep, rect: NSRect, meaning: String
  ) throws {
    let bounds = NSRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
    guard bounds.contains(rect) else { throw RenderContractError.outOfBounds(meaning) }
    var minimumLuminance = CGFloat(1)
    var maximumLuminance = CGFloat(0)
    var horizontalTransitions = 0
    var verticalTransitions = 0
    var previousRow: [CGFloat]?
    for row in Int(rect.minY)..<Int(rect.maxY) {
      var currentRow: [CGFloat] = []
      var previous: CGFloat?
      for column in Int(rect.minX)..<Int(rect.maxX) {
        guard let color = bitmap.colorAt(x: column, y: row)?.usingColorSpace(.deviceRGB) else { continue }
        let luminance = 0.2126 * color.redComponent
          + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
        minimumLuminance = min(minimumLuminance, luminance)
        maximumLuminance = max(maximumLuminance, luminance)
        if let previous, abs(previous - luminance) > 0.10 { horizontalTransitions += 1 }
        previous = luminance
        currentRow.append(luminance)
      }
      if let previousRow {
        for (prior, current) in zip(previousRow, currentRow) where abs(prior - current) > 0.10 {
          verticalTransitions += 1
        }
      }
      previousRow = currentRow
    }
    guard maximumLuminance - minimumLuminance > 0.16,
          horizontalTransitions >= 12,
          verticalTransitions >= 12 else {
      throw RenderContractError.missingSemanticContent(
        meaning, contrast: maximumLuminance - minimumLuminance,
        horizontalEdges: horizontalTransitions, verticalEdges: verticalTransitions)
    }
  }

}

private enum RenderContractError: Error {
  case outOfBounds(String)
  case missingSemanticContent(String, contrast: CGFloat, horizontalEdges: Int, verticalEdges: Int)
}
#endif
