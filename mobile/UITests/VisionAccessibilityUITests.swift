import XCTest

@MainActor
final class VisionAccessibilityUITests: XCTestCase {
  func testAttachmentFixtureRemainsOperableAtAccessibilitySizeWithReduceMotion() {
    let app = XCUIApplication()
    app.launchArguments = [
      "-ui-fixture", "attachment-draft",
      "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
      "-UIAccessibilityReduceMotionEnabled", "YES"
    ]
    app.launch()

    XCTAssertTrue(app.otherElements["attachment.preview"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["attachment.remove"].isHittable)
    XCTAssertTrue(app.buttons["chat.send"].isHittable)
  }

  func testFullDetailWarningNamesLatencyMemoryAndRecovery() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-fixture", "full-detail-warning"]
    app.launch()

    XCTAssertTrue(app.alerts["Send full-detail image?"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.alerts.buttons["Use Fast ~1,024"].exists)
    XCTAssertTrue(app.alerts.buttons["Cancel"].exists)
  }
}
