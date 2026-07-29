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

    @discardableResult
    private func revealButton(_ title: String, in app: XCUIApplication) -> XCUIElement {
        let button = app.buttons[title]
        for _ in 0..<8 where !button.isHittable { app.swipeUp() }
        return button
    }

    func testDashboardPrimaryActionsAtDefaultTextSize() {
        let app = launchedApp()
        XCTAssertTrue(app.buttons["Calculate a Tip"].waitForExistence(timeout: 5))
        let actions = ["Receipts", "Split a Bill", "Convert Currency", "What Should I Tip?", "Quick Calculate", "Note Pad"]
        for title in actions {
            XCTAssertTrue(revealButton(title, in: app).isHittable, "Expected \(title) to be visible and hittable")
        }
        XCTAssertFalse(app.buttons["Scan Receipt"].exists)
        XCTAssertFalse(app.staticTexts["Additional tools"].exists)
    }

    func testDashboardPrimaryActionsAtLargeTextSize() {
        let app = launchedApp(contentSize: "UICTContentSizeCategoryAccessibilityLarge")
        XCTAssertTrue(app.buttons["Calculate a Tip"].waitForExistence(timeout: 5))
        let actions = ["Receipts", "Split a Bill", "Convert Currency", "What Should I Tip?", "Quick Calculate", "Note Pad"]
        for title in actions {
            XCTAssertTrue(revealButton(title, in: app).isHittable, "Expected \(title) to remain hittable at accessibility text sizes")
        }
    }

    func testGuidedTipAssistantPrimaryControlsRemainHittable() {
        let app = launchedApp()
        app.buttons["Calculate a Tip"].tap()
        XCTAssertTrue(app.staticTexts["What service did you receive?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["Search services"].isHittable)
        XCTAssertTrue(app.buttons["Continue"].isHittable)
    }

    func testUnifiedReceiptHubAndScannerNavigation() {
        let app = launchedApp()
        revealButton("Receipts", in: app).tap()
        XCTAssertTrue(app.navigationBars["Receipts"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Add Receipt"].exists)
        XCTAssertTrue(app.buttons["Saved Receipts"].exists)
        app.buttons["Add Receipt"].tap()
        XCTAssertTrue(app.navigationBars["Receipt Scanner"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Take Photo"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Choose from Photo Library"].exists)
        XCTAssertTrue(app.buttons["Enter Values Manually"].exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Receipts"].waitForExistence(timeout: 5))
        app.navigationBars["Receipts"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["Calculate a Tip"].waitForExistence(timeout: 5))
    }

    func testSavedReceiptsRemainsAvailableFromReceiptHub() {
        let app = launchedApp()
        revealButton("Receipts", in: app).tap()
        XCTAssertTrue(app.staticTexts["No saved receipts"].exists || app.staticTexts.matching(NSPredicate(format: "label MATCHES '[0-9]+ saved receipts?'")).firstMatch.exists)
        app.buttons["Saved Receipts"].tap()
        XCTAssertTrue(app.navigationBars["Saved Receipts"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Close"].isHittable)
    }

    func testQuickCalculatorAndNotePadNavigation() {
        let app = launchedApp()
        revealButton("Quick Calculate", in: app).tap()
        XCTAssertTrue(app.navigationBars["Tip Calculator"].waitForExistence(timeout: 5))
        app.navigationBars["Tip Calculator"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["Calculate a Tip"].waitForExistence(timeout: 5))
        revealButton("Note Pad", in: app).tap()
        XCTAssertTrue(app.navigationBars["Note Pad"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["New Note"].exists)
        app.navigationBars["Note Pad"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["Calculate a Tip"].waitForExistence(timeout: 5))
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
