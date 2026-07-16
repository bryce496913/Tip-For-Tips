import XCTest
@testable import Tips_For_Tips

actor InMemoryPreferencesRepository: UserPreferencesRepository {
    var stored: UserPreferences?
    func loadPreferences() async throws -> UserPreferences { stored ?? .defaults }
    func savePreferences(_ preferences: UserPreferences) async throws { stored = preferences }
}

final class UXRepairTests: XCTestCase {
    func testBillSummaryParsingEmptyAndDecimals() {
        XCTAssertNil(BillSummaryParser.parseRequired(""))
        XCTAssertEqual(BillSummaryParser.parseOptional(""), 0)
        XCTAssertEqual(BillSummaryParser.parseRequired("12.34"), Decimal(string: "12.34"))
        XCTAssertEqual(BillSummaryParser.parseOptional("1.23"), Decimal(string: "1.23"))
        XCTAssertEqual(BillSummaryParser.parseOptional("2.50"), Decimal(string: "2.50"))
    }

    func testBillSummaryParsingRejectsNegatives() {
        XCTAssertNil(BillSummaryParser.parseRequired("-1"))
        XCTAssertNil(BillSummaryParser.parseOptional("-0.01"))
    }

    func testBillSummaryParsingLocalizedDecimalSeparator() {
        let locale = Locale(identifier: "fr_FR")
        XCTAssertEqual(BillSummaryParser.parseRequired("12,34", locale: locale), Decimal(string: "12.34"))
    }

    @MainActor func testSplitActionStatesAndSaveConfirmationClearsAfterEditing() async {
        let model = SplitBillViewModel()
        XCTAssertTrue(model.canSave)
        XCTAssertTrue(model.canShare)
        XCTAssertTrue(model.canMarkAllPaid)
        XCTAssertFalse(model.canResetPaid)
        model.markAllPaid()
        XCTAssertFalse(model.canMarkAllPaid)
        XCTAssertTrue(model.canResetPaid)
        model.saveMessage = "Split saved."
        model.session.subtotal = 12
        model.recalculate()
        XCTAssertNil(model.saveMessage)
        XCTAssertTrue(model.hasUnsavedChanges)
        model.result = nil
        XCTAssertFalse(model.canSave)
        XCTAssertFalse(model.canShare)
    }

    @MainActor func testSettingsUpdatesPersist() async {
        let repository = InMemoryPreferencesRepository()
        let model = SettingsViewModel(preferences: .defaults, repository: repository)
        model.update { prefs in
            prefs.homeCurrencyCode = "EUR"
            prefs.defaultTipPercentage = 18
            prefs.tipCalculationBasis = .finalTotalAfterTax
            prefs.defaultPeopleCount = 4
            prefs.showTippingExplanations = false
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        let loaded = try? await repository.loadPreferences()
        XCTAssertEqual(loaded?.homeCurrencyCode, "EUR")
        XCTAssertEqual(loaded?.defaultTipPercentage, 18)
        XCTAssertEqual(loaded?.tipCalculationBasis, .finalTotalAfterTax)
        XCTAssertEqual(loaded?.defaultPeopleCount, 4)
        XCTAssertEqual(loaded?.showTippingExplanations, false)
    }

    func testInvalidStoredValueFallback() {
        let invalid = UserPreferences(homeCurrencyCode: "BAD", defaultTipPercentage: -1, tipCalculationBasis: .subtotalBeforeTax, defaultPeopleCount: 0, roundingPreference: .exactCents, showTippingExplanations: true, hapticsEnabled: true, soundsEnabled: true, appearancePreference: .dark, hasCompletedOnboarding: false)
        XCTAssertEqual(invalid.validated.homeCurrencyCode, UserPreferences.defaults.homeCurrencyCode)
        XCTAssertEqual(invalid.validated.defaultTipPercentage, UserPreferences.defaults.defaultTipPercentage)
        XCTAssertEqual(invalid.validated.defaultPeopleCount, UserPreferences.defaults.defaultPeopleCount)
    }
}
