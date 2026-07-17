import XCTest

/// Deterministic UI coverage for the installed/offline product state. This is not packet-capture
/// evidence; physical-device network inspection is a separate required run artifact.
@MainActor
final class OfflineScenarioUITests: XCTestCase {
  func testInstalledConversationRemainsOperableInOfflineProductState() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-fixture", "ready-chat"]
    app.launch()

    XCTAssertTrue(app.otherElements["chat.transcript"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["chat.send"].exists)
    XCTAssertTrue(app.staticTexts["Your prompt, model, and tool results stay on this device."].exists)
  }
}
