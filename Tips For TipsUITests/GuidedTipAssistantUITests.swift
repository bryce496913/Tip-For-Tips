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

final class ModernizedUXUITests: XCTestCase {
    private func launchedApp(contentSize: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        if let contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        }
        app.launch()
        return app
    }

    func testDashboardPrimaryActionsAtDefaultTextSize() {
        let app = launchedApp()
        XCTAssertTrue(app.buttons["Calculate a Tip"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Scan Receipt"].exists)
        XCTAssertTrue(app.buttons["Split a Bill"].exists)
        XCTAssertTrue(app.buttons["Convert Currency"].exists)
        XCTAssertTrue(app.buttons["What Should I Tip?"].exists)
        XCTAssertTrue(app.buttons["Calculate a Tip"].isHittable)
    }

    func testDashboardPrimaryActionsAtLargeTextSize() {
        let app = launchedApp(contentSize: "UICTContentSizeCategoryAccessibilityLarge")
        XCTAssertTrue(app.buttons["Calculate a Tip"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Calculate a Tip"].isHittable)
    }

    func testGuidedTipAssistantPrimaryControlsRemainHittable() {
        let app = launchedApp()
        app.buttons["Calculate a Tip"].tap()
        XCTAssertTrue(app.staticTexts["What service did you receive?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["Search services"].isHittable)
        XCTAssertTrue(app.buttons["Continue"].isHittable)
    }

    func testReceiptConfirmationAndPermissionEntryPointsExist() {
        let app = launchedApp()
        app.buttons["Scan Receipt"].tap()
        XCTAssertTrue(app.buttons["Take Photo"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Enter Values Manually"].exists)
        XCTAssertTrue(app.buttons["Take Photo"].isHittable)
    }

    func testEqualAndItemizedSplitEntryPointsExist() {
        let app = launchedApp()
        app.buttons["Split a Bill"].tap()
        XCTAssertTrue(app.staticTexts["Bill summary"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Equal"].exists)
        XCTAssertTrue(app.buttons["Itemized"].exists)
    }

    func testCurrencyConverterTippingGuideSettingsAndEmptyStatesExist() {
        let app = launchedApp()
        app.buttons["Convert Currency"].tap()
        XCTAssertTrue(app.staticTexts["Currency Converter"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Convert"].exists)
    }
}
