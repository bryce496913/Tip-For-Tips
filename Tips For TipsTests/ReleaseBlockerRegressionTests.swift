import XCTest
@testable import Tips_For_Tips

final class ReleaseBlockerRegressionTests: XCTestCase {
    @MainActor
    func testSplitHandoffPreservesIncludedAndAdditionalGratuity() throws {
        var input = TipCalculationInput.defaults()
        input.subtotal = 100; input.tax = 8; input.gratuityStatus = .yes
        input.includedGratuityEntryMode = .amount; input.includedGratuityAmount = 18
        input.serviceQuality = .poor
        let tipResult = try TipRecommendationEngine().calculate(input: input)
        let context = SplitCalculatorContext.tipResult(tipResult)
        let model = SplitBillViewModel(context: context)

        XCTAssertEqual(context.includedGratuityAmount, 18)
        XCTAssertEqual(context.additionalTipAmount, 0)
        XCTAssertEqual(model.session.tipAmount, 18)
        XCTAssertEqual(model.session.total, 126)
        XCTAssertEqual(model.result?.participantResults.reduce(Decimal(0)) { $0 + $1.finalAmount }, 126)
    }

    @MainActor
    func testSplitHandoffBlocksAnUnreconciledSuppliedTotal() {
        let context = SplitCalculatorContext(sourceCalculationID: nil, receiptID: nil, currencyCode: "USD", subtotal: 100, tax: 8, includedGratuityAmount: 18, additionalTipAmount: 2, total: 129, suggestedPeopleCount: 2)
        let model = SplitBillViewModel(context: context)
        XCTAssertEqual(model.session.total, 129)
        XCTAssertNil(model.result)
        XCTAssertNotNil(model.validationMessage)
        XCTAssertFalse(model.canSave)
        XCTAssertFalse(model.canShare)
    }

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
        let initiallyStoredReceipts = try await repo.fetchReceipts()
        XCTAssertEqual(initiallyStoredReceipts, [])
        let metadata = root.appendingPathComponent("V2/Receipts/receipts.json")
        try FileManager.default.createDirectory(at: metadata.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: metadata)
        do { _ = try await repo.fetchReceipts(); XCTFail("Corrupt metadata must throw") } catch { }
        let backups = root.appendingPathComponent("V2/Receipts/Backups")
        XCTAssertTrue((try FileManager.default.contentsOfDirectory(atPath: backups.path)).contains { $0.contains("receipts-corrupt") })
        XCTAssertEqual(String(data: try Data(contentsOf: metadata), encoding: .utf8), "not json")
    }

    func testPartialMigrationDoesNotWriteCompletionMarker() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let receipts = root.appendingPathComponent("Receipts", isDirectory: true)
        try FileManager.default.createDirectory(at: receipts, withIntermediateDirectories: true)
        try Data("{ not valid json".utf8).write(to: receipts.appendingPathComponent("receipts.json"))

        let report = await V2MigrationCoordinator(rootURL: root).migrateIfNeeded()

        XCTAssertFalse(report.succeeded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("V2/migration-v2-complete.json").path))
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

final class IncludedGratuityPercentageReleaseTests: XCTestCase {
    @MainActor
    func testPercentageOnlyReceiptCarriesTwentyDollarsIntoSplitAndReconciles() throws {
        let charge = DetectedReceiptCharge(label: "Included gratuity: 20%", amount: nil, percentage: 20, kind: .includedGratuity, confidence: 1, userClassification: .includedGratuity)
        let receipt = ReceiptRecord(id: UUID(), merchantName: "Fixture", receiptDate: nil, subtotal: 100, tax: 8, total: 128, detectedCharges: [charge], imageFilename: nil, thumbnailFilename: nil, notes: "", createdAt: Date(), updatedAt: Date())
        let context = SplitCalculatorContext.receipt(receipt)
        let model = SplitBillViewModel(context: context)

        XCTAssertEqual(context.includedGratuityAmount, 20)
        XCTAssertEqual(model.session.tipAmount, 20)
        XCTAssertEqual(model.session.additionalTipAmount, 0)
        XCTAssertEqual(model.session.total, 128)
        XCTAssertEqual(model.result?.participantResults.reduce(Decimal(0)) { $0 + $1.finalAmount }, 128)
    }

    func testPercentageIncludedGratuityDerivesSubtotalFromPreTaxBase() throws {
        var input = TipCalculationInput.defaults()
        input.serviceID = "restaurant"
        input.calculationBasis = .subtotalBeforeTax
        input.subtotal = nil
        input.tax = 8
        input.finalTotal = 128
        input.finalTotalIncludesIncludedGratuity = true
        input.gratuityStatus = .yes
        input.includedGratuityEntryMode = .percentage
        input.includedGratuityPercentage = 20
        input.serviceQuality = .poor
        let result = try TipRecommendationEngine().calculate(input: input)
        XCTAssertEqual(result.baseBillAmount, 100)
        XCTAssertEqual(result.includedGratuityAmount, 20)
        XCTAssertEqual(result.finalTotal, 128)
    }

    func testIncludedGratuityCreditsNonstandardRecommendationBranches() throws {
        var input = TipCalculationInput.defaults()
        input.gratuityStatus = .yes; input.includedGratuityEntryMode = .amount; input.includedGratuityAmount = 10
        input.subtotal = 100; input.tax = 0; input.serviceQuality = .good

        input.serviceID = "bar"; input.bartenderTipMode = .perDrink; input.numberOfDrinks = 5
        XCTAssertEqual(try TipRecommendationEngine().calculate(input: input).suggestedAdditionalTip, 0)

        input.serviceID = "bell-staff"; input.numberOfBags = 3
        XCTAssertEqual(try TipRecommendationEngine().calculate(input: input).suggestedAdditionalTip, 0)
    }

    func testAfterTaxBaseRemovesIncludedGratuityExactlyOnce() throws {
        var input = TipCalculationInput.defaults()
        input.serviceID = "restaurant"; input.calculationBasis = .finalTotalAfterTax
        input.subtotal = 100; input.tax = 8; input.finalTotal = 128
        input.gratuityStatus = .yes; input.includedGratuityEntryMode = .percentage; input.includedGratuityPercentage = 20
        input.finalTotalIncludesIncludedGratuity = true; input.serviceQuality = .poor
        let result = try TipRecommendationEngine().calculate(input: input)
        XCTAssertEqual(result.baseBillAmount, 108)
        XCTAssertEqual(result.includedGratuityAmount, 20)
        XCTAssertEqual(result.finalTotal, 128)
    }

    func testReceiptConversionExcludesUnconfirmedCharges() {
        let charges = [
            DetectedReceiptCharge(label: "Gratuity", amount: 18, percentage: nil, kind: .automaticGratuity, confidence: 1, userClassification: .includedGratuity),
            DetectedReceiptCharge(label: "Delivery", amount: 5, percentage: nil, kind: .deliveryFee, confidence: 1, userClassification: .deliveryFee),
            DetectedReceiptCharge(label: "Service", amount: 4, percentage: nil, kind: .serviceCharge, confidence: 1, userClassification: .serviceChargeUnsure)
        ]
        let receipt = ReceiptRecord(id: UUID(), merchantName: nil, receiptDate: nil, subtotal: nil, tax: nil, total: nil, detectedCharges: charges, imageFilename: nil, thumbnailFilename: nil, notes: "", createdAt: Date(), updatedAt: Date())
        XCTAssertEqual(receipt.convertibleAmounts.first { $0.id == "included-gratuity" }?.amount, 18)
        XCTAssertEqual(receipt.convertibleAmounts.first { $0.id == "included-gratuity" }?.label, "Included gratuity")
    }

    func testPercentageOnlyReceiptGratuityIsConvertible() {
        let charge = DetectedReceiptCharge(label: "Gratuity 18%", amount: nil, percentage: 18, kind: .automaticGratuity, confidence: 1, userClassification: .includedGratuity)
        let receipt = ReceiptRecord(id: UUID(), merchantName: nil, receiptDate: nil, subtotal: 100, tax: 8, total: 126, detectedCharges: [charge], imageFilename: nil, thumbnailFilename: nil, notes: "", createdAt: Date(), updatedAt: Date())
        XCTAssertEqual(receipt.convertibleAmounts.first { $0.id == "included-gratuity" }?.amount, 18)
    }

    func testInformationalServicePreservesConfirmedIncludedGratuity() throws {
        var input = TipCalculationInput.defaults()
        input.serviceID = "service-charges"; input.subtotal = 100; input.finalTotal = 120
        input.gratuityStatus = .yes; input.includedGratuityEntryMode = .amount
        input.includedGratuityAmount = 20; input.finalTotalIncludesIncludedGratuity = true
        let result = try TipRecommendationEngine().calculate(input: input)
        XCTAssertEqual(result.includedGratuityAmount, 20)
        XCTAssertEqual(result.suggestedAdditionalTip, 0)
        XCTAssertEqual(result.combinedGratuity, 20)
        XCTAssertEqual(result.finalTotal, 120)
    }
}
