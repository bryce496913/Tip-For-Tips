import XCTest
@testable import Tips_For_Tips

final class ReleaseBlockerRegressionTests: XCTestCase {
    func testReleaseLinksAreSecureAndNotPlaceholders() {
        for url in [AppLinks.privacyPolicy, AppLinks.support] {
            XCTAssertEqual(url.scheme, "https")
            XCTAssertNotNil(url.host)
            XCTAssertFalse(url.absoluteString.lowercased().contains("example"))
            XCTAssertFalse(url.absoluteString.lowercased().contains("placeholder"))
        }
    }

    @MainActor
    func testFinancialOCRKindsAlwaysStartUnreviewed() {
        let kinds: [ReceiptChargeKind] = [.includedGratuity, .automaticGratuity, .serviceCharge, .hospitalityCharge, .administrativeFee, .suggestedGratuity, .deliveryFee]
        for kind in kinds { XCTAssertEqual(ReceiptScannerViewModel.initialClassification(for: kind), .unreviewed) }
    }

    func testUnreviewedChargeIsNotTrustedAsIncludedGratuity() {
        let charge = DetectedReceiptCharge(label: "Automatic gratuity 20.00", amount: 20, kind: .automaticGratuity, confidence: 1, userClassification: .unreviewed)
        let receipt = ReceiptRecord(id: UUID(), merchantName: "Fixture", receiptDate: nil, subtotal: 100, tax: 8, total: 128, detectedCharges: [charge], imageFilename: nil, thumbnailFilename: nil, notes: "", confirmationStatus: .needsReview, createdAt: Date(), updatedAt: Date())
        XCTAssertTrue(receipt.hasUnreviewedFinancialCharges)
        XCTAssertEqual(receipt.confirmedIncludedGratuity(), .amount(0))
        XCTAssertEqual(receipt.tipCalculationInput().includedGratuityAmount, 0)
    }

    func testTimestampedNoteFailureReportsExactSourceAndPreservesValidNote() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("valid note".utf8).write(to: root.appendingPathComponent("10 04 2024 14:34.txt"))
        try Data([0xFF, 0xFE]).write(to: root.appendingPathComponent("10 04 2024 14:35.txt"))
        let coordinator = V2MigrationCoordinator(rootURL: root)
        let report = await coordinator.migrateIfNeeded()
        let issues = await coordinator.recoveryIssues
        XCTAssertFalse(report.succeeded)
        XCTAssertEqual(issues.map(\.sourceRelativePath), ["10 04 2024 14:35.txt"])
        XCTAssertEqual(issues.first?.phase, .timestampedNote)
        let data = try Data(contentsOf: root.appendingPathComponent("Notes/notes.json"))
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(StoredDataEnvelope<SavedNote>.self, from: data).records.map(\.text), ["valid note"])
    }
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
    func testEveryWorkflowAggregatesAllConfirmedCharges() {
        let charges = [
            DetectedReceiptCharge(label: "Automatic gratuity", amount: 10, percentage: nil, kind: .automaticGratuity, confidence: 1, userClassification: .includedGratuity),
            DetectedReceiptCharge(label: "Included gratuity 5%", amount: nil, percentage: 5, kind: .includedGratuity, confidence: 1, userClassification: .includedGratuity),
            DetectedReceiptCharge(label: "Suggested tip", amount: 99, percentage: nil, kind: .suggestedGratuity, confidence: 1, userClassification: .suggestedGratuityOnly)
        ]
        let receipt = ReceiptRecord(id: UUID(), merchantName: "Fixture", receiptDate: nil, subtotal: 100, tax: 8, total: 123, detectedCharges: charges, imageFilename: nil, thumbnailFilename: nil, notes: "", createdAt: Date(), updatedAt: Date())
        XCTAssertEqual(receipt.confirmedIncludedGratuity(), .amount(15))
        XCTAssertEqual(receipt.tipCalculationInput().includedGratuityAmount, 15)
        XCTAssertEqual(SplitCalculatorContext.receipt(receipt).includedGratuityAmount, 15)
        XCTAssertEqual(receipt.convertibleAmounts.first(where: { $0.id == "included-gratuity" })?.amount, 15)
    }

    func testPercentageWithoutSubtotalRequiresReviewEverywhere() {
        let charge = DetectedReceiptCharge(label: "Included gratuity 18%", amount: nil, percentage: 18, kind: .includedGratuity, confidence: 1, userClassification: .includedGratuity)
        let receipt = ReceiptRecord(id: UUID(), merchantName: nil, receiptDate: nil, subtotal: nil, tax: nil, total: 118, detectedCharges: [charge], imageFilename: nil, thumbnailFilename: nil, notes: "", createdAt: Date(), updatedAt: Date())
        XCTAssertEqual(receipt.confirmedIncludedGratuity(), .needsSubtotal)
        XCTAssertEqual(receipt.tipCalculationInput().includedGratuityEntryMode, .unknown)
        XCTAssertNotNil(SplitCalculatorContext.receipt(receipt).handoffValidationMessage)
        XCTAssertNil(receipt.convertibleAmounts.first(where: { $0.id == "included-gratuity" }))
    }
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

private actor IdentityCalculationRepository: CalculationRepository {
    private var records: [SavedCalculationRecord] = []
    func fetchCalculations() async throws -> [SavedCalculationRecord] { records }
    func saveCalculation(_ record: SavedCalculationRecord) async throws { records.removeAll { $0.id == record.id }; records.append(record) }
    func deleteCalculation(id: UUID) async throws { records.removeAll { $0.id == id } }
}

final class ScannerEnvironmentRegressionTests: XCTestCase {
    @MainActor func testScannerRetainsInjectedCalculationRepositoryIdentityAndPreferences() {
        let repository = IdentityCalculationRepository()
        var preferences = UserPreferences.defaults
        preferences.homeCurrencyCode = "EUR"
        preferences.defaultPeopleCount = 4
        preferences.showTippingExplanations = false
        let model = ReceiptScannerViewModel(preferences: preferences, calculationRepository: repository)

        XCTAssertTrue((model.calculationRepository as AnyObject) === repository)
        model.startManualEntry()
        model.draft?.subtotalText = "20"
        model.continueToAssistant()
        XCTAssertEqual(model.pendingTipInput?.currencyCode, "EUR")
        XCTAssertEqual(model.pendingTipInput?.peopleCount, 4)
        XCTAssertEqual(model.preferences.showTippingExplanations, false)
    }

    @MainActor func testReceiptCurrencyOverridesHomeCurrency() {
        var preferences = UserPreferences.defaults; preferences.homeCurrencyCode = "EUR"
        let model = ReceiptScannerViewModel(preferences: preferences, calculationRepository: IdentityCalculationRepository())
        model.startManualEntry(); model.draft?.subtotalText = "20"; model.draft?.currencyCode = "CAD"
        model.continueToAssistant()
        XCTAssertEqual(model.pendingTipInput?.currencyCode, "CAD")
    }

    @MainActor func testManualDraftDirtyStateSnapshotsAfterSave() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = ReceiptScannerViewModel(preferences: .defaults, repository: FileReceiptRepository(rootURL: root), calculationRepository: IdentityCalculationRepository())
        model.startManualEntry()
        XCTAssertFalse(model.hasUnsavedChanges)
        model.draft?.merchantName = "Cafe"
        XCTAssertTrue(model.hasUnsavedChanges)
        let savedID = await model.saveReceipt()
        XCTAssertNotNil(savedID)
        XCTAssertFalse(model.hasUnsavedChanges)
        model.draft?.notes = "Changed"
        XCTAssertTrue(model.hasUnsavedChanges)
    }
}

final class MigrationRecoveryRegressionTests: XCTestCase {
    func testCorruptRootReceiptCanBeQuarantinedWithoutTouchingV2Data() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("{ corrupt".utf8).write(to: root.appendingPathComponent("receipts.json"))
        let coordinator = V2MigrationCoordinator(rootURL: root)
        let failed = await coordinator.migrateIfNeeded()
        XCTAssertFalse(failed.succeeded)
        let issues = await coordinator.recoveryIssues
        let issue = try XCTUnwrap(issues.first)
        try await coordinator.quarantine(issue, appVersion: "2.0", build: "27")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("receipts.json").path))
        let quarantine = root.appendingPathComponent("V2/Backups/Quarantine")
        let folders = try FileManager.default.contentsOfDirectory(at: quarantine, includingPropertiesForKeys: nil)
        XCTAssertEqual(folders.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folders[0].appendingPathComponent("quarantine-manifest.json").path))
        let retried = await coordinator.migrateIfNeeded()
        XCTAssertTrue(retried.succeeded)
    }

    func testDeleteRecoverySourceLeavesExistingV2Metadata() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let v2 = root.appendingPathComponent("V2/Receipts/receipts.json")
        try FileManager.default.createDirectory(at: v2.deletingLastPathComponent(), withIntermediateDirectories: true)
        let existing = Data("existing-v2".utf8); try existing.write(to: v2)
        try Data("bad".utf8).write(to: root.appendingPathComponent("receipts.json"))
        let coordinator = V2MigrationCoordinator(rootURL: root)
        _ = await coordinator.migrateIfNeeded()
        let issues = await coordinator.recoveryIssues
        let issue = try XCTUnwrap(issues.first)
        try await coordinator.deleteSource(issue)
        XCTAssertEqual(try Data(contentsOf: v2), existing)
    }
}
