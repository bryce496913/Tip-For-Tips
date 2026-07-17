import XCTest
@testable import Tips_For_Tips

final class ReceiptFieldParserTests: XCTestCase {
    private let parser = ReceiptFieldParser()
    private func parse(_ text: String, confidence: Float = 0.9) -> ReceiptDetectionResult {
        let observations = text.split(separator: "\n").map { RecognizedTextObservation(text: String($0), confidence: confidence, boundingBox: .zero, candidates: []) }
        return parser.parse(recognizedText: RecognizedReceiptText(observations: observations, fullText: text), locale: Locale(identifier: "en_US"))
    }

    func testBasicRestaurantReceiptDetectsCoreFields() {
        let result = parse("""
        Bistro Cafe
        07/14/2026 7:30 PM
        Subtotal $72.00
        Sales Tax $6.00
        Total $78.00
        """)
        XCTAssertEqual(result.merchantCandidates.first?.value, "Bistro Cafe")
        XCTAssertEqual(result.subtotalCandidates.first?.value, 72)
        XCTAssertEqual(result.taxCandidates.first?.value, 6)
        XCTAssertEqual(result.totalCandidates.first?.value, 78)
    }

    func testAutomaticGratuityAndSuggestedExtraTipAreDistinct() {
        let result = parse("""
        Dinner House
        Subtotal 100.00
        Automatic gratuity 18% $18.00
        Tax $8.00
        Total $126.00
        Suggested tip 20% $20.00
        """)
        XCTAssertTrue(result.chargeCandidates.contains { $0.kind == .automaticGratuity })
        XCTAssertTrue(result.chargeCandidates.contains { $0.kind == .suggestedGratuity })
        XCTAssertTrue(result.warnings.contains(.suggestedGratuityNotIncluded))
    }

    func testServiceHospitalityAdministrativeAndDeliveryFeesAreClassifiedAmbiguously() {
        let result = parse("""
        Service charge $5.00
        Hospitality charge $4.00
        Admin fee $2.00
        Delivery fee $3.00
        """)
        XCTAssertTrue(result.chargeCandidates.contains { $0.kind == .serviceCharge })
        XCTAssertTrue(result.chargeCandidates.contains { $0.kind == .hospitalityCharge })
        XCTAssertTrue(result.chargeCandidates.contains { $0.kind == .administrativeFee })
        XCTAssertTrue(result.chargeCandidates.contains { $0.kind == .deliveryFee })
        XCTAssertFalse(result.chargeCandidates.contains { $0.kind == .includedGratuity && $0.label.localizedCaseInsensitiveContains("delivery") })
    }

    func testMultipleTotalsCashChangeAndAuthorizationWarnings() {
        let result = parse("""
        Subtotal 40.00
        Tax 3.00
        Total 43.00
        Cash tendered 50.00
        Change 7.00
        Authorization amount 43.00
        Grand Total 43.00
        """)
        XCTAssertEqual(result.totalCandidates.count, 2)
        XCTAssertTrue(result.warnings.contains(.multipleTotals))
    }

    func testLocalizedAndLargeAmountParsingRejectsPhoneAndCardNumbers() {
        XCTAssertEqual(ReceiptAmountParser.parse("USD 1,234.56"), Decimal(string: "1234.56"))
        XCTAssertEqual(ReceiptAmountParser.parse("12,50"), Decimal(string: "12.50"))
        XCTAssertNil(ReceiptAmountParser.parse("555-123-4567"))
        XCTAssertNil(ReceiptAmountParser.parse("20%"))
    }

    func testReceiptAmountParserAcceptsManualEntryFormatsWithoutCents() {
        XCTAssertEqual(ReceiptAmountParser.parse("20"), Decimal(20))
        XCTAssertEqual(ReceiptAmountParser.parse("20.00"), Decimal(20))
        XCTAssertEqual(ReceiptAmountParser.parse("$20"), Decimal(20))
        XCTAssertEqual(ReceiptAmountParser.parse("1,234.56"), Decimal(string: "1234.56"))
        XCTAssertEqual(ReceiptAmountParser.parse("1.234,56"), Decimal(string: "1234.56"))
        XCTAssertEqual(ReceiptAmountParser.parse("0"), Decimal(0))
        XCTAssertNil(ReceiptAmountParser.parse(""))
        XCTAssertNil(ReceiptAmountParser.parse("   "))
    }

    func testReceiptAmountParserRejectsMalformedManualEntry() {
        XCTAssertNil(ReceiptAmountParser.parse("-20"))
        XCTAssertNil(ReceiptAmountParser.parse("12,34,567"))
        XCTAssertNil(ReceiptAmountParser.parse("twenty"))
        XCTAssertNil(ReceiptAmountParser.parse("12.30.40"))
    }

    func testReceiptFieldParserDetectsWholeDollarAmounts() {
        let result = parse("""
        Counter Cafe
        Subtotal $20
        Tax 0
        Total 20
        """)
        XCTAssertEqual(result.subtotalCandidates.first?.value, 20)
        XCTAssertEqual(result.taxCandidates.first?.value, 0)
        XCTAssertEqual(result.totalCandidates.first?.value, 20)
    }

    func testLowConfidenceAndMissingFields() {
        let result = parse("Cafe\nTotal $12.00", confidence: 0.4)
        XCTAssertTrue(result.warnings.contains(.lowConfidenceFields))
        XCTAssertTrue(result.subtotalCandidates.isEmpty)
        XCTAssertTrue(result.taxCandidates.isEmpty)
    }
}
