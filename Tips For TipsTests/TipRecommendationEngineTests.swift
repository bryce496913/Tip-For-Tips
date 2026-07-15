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
