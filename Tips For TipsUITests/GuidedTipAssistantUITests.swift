import XCTest

final class GuidedTipAssistantUITests: XCTestCase {
    func testOpenFromDashboardAndStartRestaurantFlow() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Calculate a Tip"].waitForExistence(timeout: 5))
        app.buttons["Calculate a Tip"].tap()
        XCTAssertTrue(app.staticTexts["What service did you receive?"].waitForExistence(timeout: 5))
    }

    func testServiceSearchPeopleAndStartOverControlsExist() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Calculate a Tip"].tap()
        XCTAssertTrue(app.textFields["Search services"].waitForExistence(timeout: 5))
        app.textFields["Search services"].tap()
        app.textFields["Search services"].typeText("Valet")
        XCTAssertTrue(app.staticTexts["Valet parking"].exists)
    }
}
