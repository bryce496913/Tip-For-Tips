import XCTest
@testable import Tips_For_Tips

final class ReleaseBlockerRegressionTests: XCTestCase {
    func testIncludedGratuityReceiptTotals() throws {
        var input = TipCalculationInput.defaults()
        input.serviceID = "restaurant"
        input.subtotal = 100
        input.tax = 8
        input.finalTotal = nil
        input.gratuityStatus = .yes
        input.includedGratuityEntryMode = .amount
        input.includedGratuityAmount = 20
        input.serviceQuality = .poor
        var result = try TipRecommendationEngine().calculate(input: input)
        XCTAssertEqual(result.finalTotal, 128)

        input.finalTotal = 128
        input.finalTotalIncludesIncludedGratuity = true
        result = try TipRecommendationEngine().calculate(input: input)
        XCTAssertEqual(result.finalTotal, 128)

        input.finalTotal = 108
        input.finalTotalIncludesIncludedGratuity = false
        result = try TipRecommendationEngine().calculate(input: input)
        XCTAssertEqual(result.finalTotal, 128)
    }

    func testIncludedGratuityNegativeDerivedSubtotalRejected() {
        var input = TipCalculationInput.defaults()
        input.serviceID = "restaurant"
        input.calculationBasis = .subtotalBeforeTax
        input.subtotal = nil
        input.tax = 8
        input.finalTotal = 20
        input.finalTotalIncludesIncludedGratuity = true
        input.gratuityStatus = .yes
        input.includedGratuityEntryMode = .amount
        input.includedGratuityAmount = 25
        XCTAssertThrowsError(try TipRecommendationEngine().calculate(input: input))
    }

    func testAdvancedSplitCalculatedTotalAndNoUnallocatedContradiction() throws {
        let session = SplitSession(id: UUID(), name: "Dinner", mode: .equal, currencyCode: "USD", subtotal: 72, tax: 8, tipAmount: 20, total: 100, participants: [SplitParticipant(name: "A"), SplitParticipant(name: "B")], items: [], taxAllocationMode: .proportional, tipAllocationMode: .proportional, roundingRule: .exactCents, sourceCalculationID: nil, receiptID: nil, createdAt: Date(), updatedAt: Date())
        let result = try SplitCalculationEngine().calculate(session: session)
        XCTAssertEqual(result.roundedCollectedTotal, 100)
        XCTAssertEqual(result.participantResults.map(\.finalAmount), [50, 50])
        XCTAssertEqual(result.unallocatedAmount, 0)
    }

    func testContradictorySplitTotalBlocked() {
        let session = SplitSession(id: UUID(), name: "Bad", mode: .equal, currencyCode: "USD", subtotal: 72, tax: 8, tipAmount: 20, total: 128, participants: [SplitParticipant(name: "A"), SplitParticipant(name: "B")], items: [], taxAllocationMode: .proportional, tipAllocationMode: .proportional, roundingRule: .exactCents, sourceCalculationID: nil, receiptID: nil, createdAt: Date(), updatedAt: Date())
        XCTAssertThrowsError(try SplitCalculationEngine().calculate(session: session))
    }

    func testZeroWeightProportionalTaxAndTipFallsBackToEqualAndConserves() throws {
        let people = [SplitParticipant(name: "A"), SplitParticipant(name: "B")]
        let session = SplitSession(id: UUID(), name: "Zero", mode: .equal, currencyCode: "USD", subtotal: 0, tax: 6, tipAmount: 4, total: 10, participants: people, items: [], taxAllocationMode: .proportional, tipAllocationMode: .proportional, roundingRule: .exactCents, sourceCalculationID: nil, receiptID: nil, createdAt: Date(), updatedAt: Date())
        let result = try SplitCalculationEngine().calculate(session: session)
        XCTAssertEqual(result.participantResults.reduce(Decimal(0)) { $0 + $1.taxAmount }, 6)
        XCTAssertEqual(result.participantResults.reduce(Decimal(0)) { $0 + $1.tipAmount }, 4)
        XCTAssertEqual(result.roundedCollectedTotal, 10)
    }

    func testReceiptRepositoryCanonicalPathAndCorruptMetadataBackup() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repo = FileReceiptRepository(rootURL: root)
        XCTAssertEqual(try await repo.fetchReceipts(), [])
        let metadata = root.appendingPathComponent("V2/Receipts/receipts.json")
        try FileManager.default.createDirectory(at: metadata.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: metadata)
        do { _ = try await repo.fetchReceipts(); XCTFail("Corrupt metadata must throw") } catch { }
        let backups = root.appendingPathComponent("V2/Receipts/Backups")
        XCTAssertTrue((try FileManager.default.contentsOfDirectory(atPath: backups.path)).contains { $0.contains("receipts-corrupt") })
        XCTAssertEqual(String(data: try Data(contentsOf: metadata), encoding: .utf8), "not json")
    }

    func testPublicPlaceholderStringsRemovedFromProductionViews() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Tips For Tips")
        let banned = ["coming next", "future phase", "placeholder", "deep link target", "V1 tools"]
        for url in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter({ $0.pathExtension == "swift" }) {
            let text = try String(contentsOf: url).lowercased()
            for phrase in banned { XCTAssertFalse(text.contains(phrase.lowercased()), "\(url.lastPathComponent) contains \(phrase)") }
        }
    }
}
