import XCTest

final class UXRepairUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testAdvancedSplitBillSummaryAndActionsAreVisible() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing"]
        app.launch()
        app.buttons["Split a Bill"].tap()
        XCTAssertTrue(app.staticTexts["Bill Summary"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["Subtotal"].exists)
        XCTAssertTrue(app.staticTexts["Tax"].exists)
        XCTAssertTrue(app.staticTexts["Tip"].exists)
        app.textFields["Subtotal"].tap()
        app.textFields["Subtotal"].typeText("12.34")
        XCTAssertTrue(app.staticTexts["Calculated final total"].exists)
        XCTAssertTrue(app.buttons["Save Split"].exists)
        XCTAssertTrue(app.buttons["Share Summary"].exists)
        XCTAssertTrue(app.buttons["Mark Everyone Paid"].exists)
        XCTAssertTrue(app.buttons["Reset Paid Status"].exists)
    }

    func testSettingsRowsAreInteractive() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing"]
        app.launch()
        app.buttons["Open Settings"].tap()
        XCTAssertTrue(app.buttons["Home currency"].waitForExistence(timeout: 5))
        app.buttons["Home currency"].tap()
        XCTAssertTrue(app.navigationBars["Home Currency"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        app.buttons["Default tip"].tap()
        XCTAssertTrue(app.navigationBars["Default Tip"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        app.buttons["Tip basis"].tap()
        XCTAssertTrue(app.navigationBars["Tip Basis"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        app.buttons["Default people"].tap()
        XCTAssertTrue(app.navigationBars["Default People"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.switches["Show explanations"].exists)
    }
}
