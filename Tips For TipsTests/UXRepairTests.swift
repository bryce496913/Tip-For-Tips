import XCTest
@testable import Tips_For_Tips

actor InMemoryPreferencesRepository: UserPreferencesRepository {
    var stored: UserPreferences?
    func loadPreferences() async throws -> UserPreferences { stored ?? .defaults }
    func savePreferences(_ preferences: UserPreferences) async throws { stored = preferences }
}

final class UXRepairTests: XCTestCase {
    @MainActor func testAppEnvironmentPublishesPreferenceOnlyAfterPersistence() async throws {
        let repository = InMemoryPreferencesRepository()
        let environment = AppEnvironment(preferencesRepository: repository)
        try await environment.updatePreferences { $0.defaultPeopleCount = 6 }
        XCTAssertEqual(environment.preferences.defaultPeopleCount, 6)
        let persisted = try await repository.loadPreferences()
        XCTAssertEqual(persisted.defaultPeopleCount, 6)
    }
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
        XCTAssertNil(model.result)
        XCTAssertFalse(model.canSave)
        XCTAssertFalse(model.canShare)
        XCTAssertFalse(model.canMarkAllPaid)
        XCTAssertFalse(model.canResetPaid)
        model.session.subtotal = 12
        model.recalculate()
        XCTAssertNotNil(model.result)
        XCTAssertTrue(model.canSave)
        XCTAssertTrue(model.canShare)
        XCTAssertTrue(model.canMarkAllPaid)
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
        let invalid = UserPreferences(homeCurrencyCode: "BAD", defaultTipPercentage: -1, tipCalculationBasis: .subtotalBeforeTax, defaultPeopleCount: 0, roundingPreference: .exactCents, showTippingExplanations: true, appearancePreference: .dark, hasCompletedOnboarding: false)
        XCTAssertEqual(invalid.validated.homeCurrencyCode, "BAD")
        XCTAssertEqual(invalid.validated.defaultTipPercentage, UserPreferences.defaults.defaultTipPercentage)
        XCTAssertEqual(invalid.validated.defaultPeopleCount, UserPreferences.defaults.defaultPeopleCount)
    }
}
