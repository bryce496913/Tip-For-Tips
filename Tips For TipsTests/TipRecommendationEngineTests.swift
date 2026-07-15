import XCTest
@testable import Tips_For_Tips

final class TipRecommendationEngineTests: XCTestCase {
    private let engine = TipRecommendationEngine()
    private func input(service: String = "restaurant", subtotal: Decimal = 72, tax: Decimal = 6, total: Decimal = 78, quality: ServiceQuality = .standard, people: Int = 1) -> TipCalculationInput {
        var input = TipCalculationInput.defaults()
        input.serviceID = service; input.subtotal = subtotal; input.tax = tax; input.finalTotal = total; input.serviceQuality = quality; input.peopleCount = people
        return input
    }
    func testStandardRestaurantPreTaxRetainsTax() throws { let r = try engine.calculate(input: input()); XCTAssertEqual(r.recommendedTipAmount, 12.96); XCTAssertEqual(r.finalTotal, 90.96) }
    func testGoodRestaurantUsesStandardPercentage() throws { let r = try engine.calculate(input: input(quality: .good)); XCTAssertEqual(r.recommendedPercentage, 20); XCTAssertEqual(r.recommendedTipAmount, 14.40) }
    func testExceptionalRestaurantUsesUpperRange() throws { let r = try engine.calculate(input: input(quality: .exceptional)); XCTAssertEqual(r.recommendedPercentage, 22) }
    func testPoorRestaurantReducedRecommendation() throws { let r = try engine.calculate(input: input(quality: .poor)); XCTAssertEqual(r.recommendedPercentage, 15) }
    func testBuffet() throws { let r = try engine.calculate(input: input(service: "buffet")); XCTAssertEqual(r.recommendedPercentage, 10) }
    func testOptionalCoffeeShopStandardTipIsZero() throws { let r = try engine.calculate(input: input(service: "coffee-counter")); XCTAssertEqual(r.recommendedTipAmount, 0) }
    func testFoodDeliveryDifficultConditionsIncreaseTip() throws { var i = input(service: "food-delivery"); i.foodDeliveryDifficulty = [.badWeather, .largeOrder]; let r = try engine.calculate(input: i); XCTAssertEqual(r.recommendedPercentage, 17) }
    func testBartenderPercentageMode() throws { let r = try engine.calculate(input: input(service: "bar")); XCTAssertEqual(r.recommendedPercentage, 15) }
    func testBartenderPerDrinkMode() throws { var i = input(service: "bar"); i.bartenderTipMode = .perDrink; i.numberOfDrinks = 3; let r = try engine.calculate(input: i); XCTAssertEqual(r.recommendedTipAmount, 6) }
    func testTaxi() throws { let r = try engine.calculate(input: input(service: "taxi")); XCTAssertEqual(r.recommendedPercentage, 15) }
    func testValetFixedAmount() throws { let r = try engine.calculate(input: input(service: "valet")); XCTAssertEqual(r.recommendedTipAmount, 5) }
    func testBellhopOneBagAndMultipleBags() throws { var i = input(service: "bell-staff"); i.numberOfBags = 1; XCTAssertEqual(try engine.calculate(input: i).recommendedTipAmount, 2); i.numberOfBags = 4; XCTAssertEqual(try engine.calculate(input: i).recommendedTipAmount, 5) }
    func testHousekeepingDays() throws { var i = input(service: "housekeeping"); i.numberOfHousekeepingDays = 2; XCTAssertEqual(try engine.calculate(input: i).recommendedTipAmount, 10) }
    func testSalonPercentage() throws { let r = try engine.calculate(input: input(service: "hair")); XCTAssertEqual(r.recommendedPercentage, 15) }
    func testIncludedGratuityBelowWithinAboveAndNoDoubleCount() throws { var i = input(); i.gratuityStatus = .yes; i.includedGratuityEntryMode = .percentage; i.includedGratuityPercentage = 10; XCTAssertEqual(try engine.calculate(input: i).suggestedAdditionalTip, 5.76); i.includedGratuityPercentage = 18; XCTAssertEqual(try engine.calculate(input: i).suggestedAdditionalTip, 0); i.includedGratuityPercentage = 25; let r = try engine.calculate(input: i); XCTAssertEqual(r.suggestedAdditionalTip, 0); XCTAssertEqual(r.finalTotal, 78) }
    func testPostTaxBasis() throws { var i = input(); i.calculationBasis = .finalTotalAfterTax; XCTAssertEqual(try engine.calculate(input: i).recommendedTipAmount, 14.04) }
    func testMultiplePeople() throws { let r = try engine.calculate(input: input(people: 2)); XCTAssertEqual(r.amountPerPerson, 45.48) }
    func testInvalidPeopleAndNegativeBill() { XCTAssertThrowsError(try engine.calculate(input: input(people: 0))); var i = input(); i.subtotal = -1; XCTAssertThrowsError(try engine.calculate(input: i)) }
    func testLocalizedDecimalParsingAndAlternatives() { XCTAssertEqual(LocalizedDecimalParser.parse("12,50", locale: Locale(identifier: "fr_FR")), Decimal(string: "12.50")); XCTAssertNotNil(try engine.calculate(input: input()).lowerAlternative); XCTAssertNil(try engine.calculate(input: input(service: "valet")).recommendedPercentage) }
}

final class Phase5CoreTests: XCTestCase {
    private let engine = TipRecommendationEngine()
    private func tipRecord(date: Date = Date(timeIntervalSince1970: 100), merchant: String = "Joe's Pizza") throws -> SavedCalculationRecord {
        var input = TipCalculationInput.defaults(); input.subtotal = 100; input.tax = 8; input.finalTotal = 108; input.serviceID = "restaurant"
        let result = try engine.calculate(input: input)
        return SavedCalculationRecord(id: UUID(), recordType: .tipOnly, tipResult: result, splitResult: nil, receiptID: nil, merchantName: merchant, notes: "window table", currencyConversion: nil, shareSummary: nil, createdAt: date, updatedAt: date)
    }
    private func receipt(date: Date = Date(timeIntervalSince1970: 200), merchant: String = "Cafe Élan") -> ReceiptRecord {
        ReceiptRecord(id: UUID(), merchantName: merchant, receiptDate: date, currencyCode: "USD", subtotal: 40, tax: 4, total: 44, detectedCharges: [], imageFilename: "image.jpg", thumbnailFilename: "thumb.jpg", notes: "latte", createdAt: date, updatedAt: date)
    }
    private func splitRecord(date: Date = Date(timeIntervalSince1970: 300)) throws -> SavedCalculationRecord {
        let session = SplitSession(id: UUID(), name: "Dinner Split", mode: .equal, currencyCode: "USD", subtotal: 90, tax: 9, tipAmount: 18, total: 117, participants: [SplitParticipant(name: "Alex", isPaid: true), SplitParticipant(name: "Sam")], items: [], taxAllocationMode: .equal, tipAllocationMode: .equal, roundingRule: .exactCents, sourceCalculationID: nil, receiptID: nil, createdAt: date, updatedAt: date)
        let result = try SplitCalculationEngine().calculate(session: session)
        return SavedCalculationRecord(id: session.id, recordType: .split, tipResult: nil, splitResult: result, receiptID: nil, merchantName: nil, notes: "birthday", currencyConversion: nil, shareSummary: nil, createdAt: date, updatedAt: date)
    }
    func testHistoryCombinesAndSortsNewestFirst() throws {
        let entries = HistoryCombiner().combine(calculations: [try tipRecord(), try splitRecord()], receipts: [receipt()])
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(HistoryViewState(entries: entries).filteredAndSorted.first?.recordType, .split)
    }
    func testHistorySearchTypeCurrencyAndAmountSorting() throws {
        let entries = HistoryCombiner().combine(calculations: [try tipRecord(), try splitRecord()], receipts: [receipt()])
        XCTAssertEqual(HistoryViewState(entries: entries, query: "elan").filteredAndSorted.first?.recordType, .receipt)
        XCTAssertEqual(HistoryViewState(entries: entries, query: "alex").filteredAndSorted.first?.recordType, .split)
        XCTAssertEqual(HistoryViewState(entries: entries, filter: HistoryFilter(recordType: .tipCalculation)).filteredAndSorted.count, 1)
        XCTAssertEqual(HistoryViewState(entries: entries, filter: HistoryFilter(currencyCode: "USD")).filteredAndSorted.count, 3)
        XCTAssertEqual(HistoryViewState(entries: entries, sort: .highestTotal).filteredAndSorted.first?.recordType, .split)
        XCTAssertEqual(HistoryViewState(entries: entries, sort: .title).filteredAndSorted.first?.title, "Cafe Élan")
    }
    func testGuideDeepLinksResolveForEveryService() {
        let validSectionIDs: Set<String> = ["restaurants", "bars", "coffee-shops", "taxis-rideshare", "food-delivery", "hotels", "bell-staff", "housekeeping", "tour-guides", "salons-spas", "valet", "coat-check", "entertainment", "other-counter", "included-gratuity"]
        XCTAssertTrue(TippingGuidance.services.allSatisfy { service in service.guideSectionID.map(validSectionIDs.contains) == true })
    }
    func testShareSummariesDoNotExposeIdentifiers() throws {
        let tip = try XCTUnwrap(try tipRecord().tipResult)
        let summary = ShareSummaryBuilder().tipSummary(tip)
        XCTAssertFalse(summary.contains(tip.id.uuidString))
        XCTAssertTrue(summary.contains("Tips for Tips"))
    }
}
