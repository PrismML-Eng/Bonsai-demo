import XCTest

@MainActor
final class CoreFlowUITests: XCTestCase {
  func testReadyChatShowsLocalOrientationAndComposer() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-fixture", "ready-chat"]
    app.launch()

    XCTAssertTrue(app.otherElements["root.workspace"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.textFields["chat.composer"].exists)
    XCTAssertTrue(app.staticTexts["Local only"].exists)
  }

  func testPendingNoteWriteRequiresOneShotDecision() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-fixture", "pending-note-write"]
    app.launch()

    XCTAssertTrue(app.buttons["approval.allowOnce"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["approval.deny"].exists)
    XCTAssertTrue(app.staticTexts["Create note titled ‘Packing list’ with body ‘Passport, charger’"].exists)
  }

  func testUnsupportedTernaryExplainsDeviceBoundary() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-fixture", "unsupported-ternary"]
    app.launch()

    app.buttons["Model Library"].tap()
    XCTAssertTrue(app.staticTexts["Ternary requires a verified high-memory iPad or Mac."].waitForExistence(timeout: 5))
  }
}
