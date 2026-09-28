import XCTest
@testable import Tips_For_Tips

private final class FailingMarkerRemovalFileManager: FileManager, @unchecked Sendable {
    override func removeItem(at URL: URL) throws {
        if URL.lastPathComponent == "migration-v2-complete.json" {
            throw CocoaError(.fileWriteNoPermission)
        }
        try super.removeItem(at: URL)
    }
}

private final class FailOnceLegacyNoteMoveFileManager: FileManager, @unchecked Sendable {
    private let filename: String
    private(set) var matchingMoveAttempts = 0

    init(filename: String) { self.filename = filename }

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        if srcURL.lastPathComponent == filename && dstURL.deletingLastPathComponent().lastPathComponent == "Legacy" {
            matchingMoveAttempts += 1
            if matchingMoveAttempts == 1 { throw CocoaError(.fileWriteNoPermission) }
        }
        try super.moveItem(at: srcURL, to: dstURL)
    }
}

final class ReleaseBlockerRegressionTests: XCTestCase {
    func testReleaseLinksMatchProductionURLsAndAreSecure() {
        let expectedURLs = [
            AppLinks.privacyPolicy: "https://sites.google.com/view/tipfortips/privacy-policy",
            AppLinks.support: "https://sites.google.com/view/tipfortips/home"
        ]

        for (url, expectedValue) in expectedURLs {
            XCTAssertEqual(url.scheme, "https")
            XCTAssertNotNil(url.host)
            XCTAssertEqual(url.absoluteString, expectedValue)
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

    func testTimestampedNoteArchiveFailureIsRetrySafeAcrossRelaunch() async throws {
        let fm = FailOnceLegacyNoteMoveFileManager(filename: "10 04 2024 14:34.txt")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let firstSource = root.appendingPathComponent("10 04 2024 14:34.txt")
        let secondSource = root.appendingPathComponent("10 04 2024 14:35.txt")
        let unrelatedSource = root.appendingPathComponent("shopping-list.txt")
        try Data("first legacy note".utf8).write(to: firstSource)
        try Data("second legacy note".utf8).write(to: secondSource)
        try Data("not a timestamped note".utf8).write(to: unrelatedSource)

        let existingID = UUID()
        let existing = SavedNote(id: existingID, text: "current-format note", createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 1))
        let notesURL = root.appendingPathComponent("Notes/notes.json")
        try fm.createDirectory(at: notesURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(StoredDataEnvelope(version: 1, records: [existing])).write(to: notesURL)

        let failed = await V2MigrationCoordinator(rootURL: root, fileManager: fm).migrateIfNeeded()
        XCTAssertFalse(failed.succeeded)
        XCTAssertTrue(fm.fileExists(atPath: firstSource.path), "A failed archive must leave the recovery source available")
        XCTAssertFalse(fm.fileExists(atPath: secondSource.path), "Other timestamped notes should still be archived")
        XCTAssertTrue(fm.fileExists(atPath: unrelatedSource.path), "Unrelated text files must be ignored")

        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let afterFailure = try decoder.decode(StoredDataEnvelope<SavedNote>.self, from: Data(contentsOf: notesURL)).records
        XCTAssertEqual(afterFailure.count, 3)
        let firstID = try XCTUnwrap(afterFailure.first(where: { $0.text == "first legacy note" })?.id)

        // A new coordinator simulates relaunch: it must recognize the deterministic ID and
        // perform only the archive operation that failed previously.
        let retried = await V2MigrationCoordinator(rootURL: root, fileManager: fm).migrateIfNeeded()
        XCTAssertTrue(retried.succeeded)
        let afterRetry = try decoder.decode(StoredDataEnvelope<SavedNote>.self, from: Data(contentsOf: notesURL)).records
        XCTAssertEqual(afterRetry.count, 3)
        XCTAssertEqual(afterRetry.first(where: { $0.text == "first legacy note" })?.id, firstID)
        XCTAssertEqual(afterRetry.filter { $0.id == firstID }.count, 1)
        XCTAssertEqual(afterRetry.filter { $0.id == existingID }.count, 1)
        XCTAssertEqual(fm.matchingMoveAttempts, 2, "Retry must attempt the unfinished archive again")
        XCTAssertFalse(fm.fileExists(atPath: firstSource.path))
        XCTAssertTrue(fm.fileExists(atPath: root.appendingPathComponent("Notes/Legacy/10 04 2024 14:34.txt").path))
    }

    func testExistingArchivedDestinationAndMigratedNoteDoNotDuplicate() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let source = root.appendingPathComponent("11 04 2024 09:15.txt")
        try Data("legacy note".utf8).write(to: source)

        let initial = await V2MigrationCoordinator(rootURL: root).migrateIfNeeded()
        XCTAssertTrue(initial.succeeded)
        let archive = root.appendingPathComponent("Notes/Legacy/11 04 2024 09:15.txt")
        try fm.copyItem(at: archive, to: source)
        try fm.removeItem(at: root.appendingPathComponent("V2/migration-v2-complete.json"))

        let retried = await V2MigrationCoordinator(rootURL: root).migrateIfNeeded()
        XCTAssertTrue(retried.succeeded)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let notes = try decoder.decode(StoredDataEnvelope<SavedNote>.self, from: Data(contentsOf: root.appendingPathComponent("Notes/notes.json"))).records
        XCTAssertEqual(notes.count, 1)
        XCTAssertFalse(fm.fileExists(atPath: source.path), "An already-archived duplicate source should be cleaned up")
        XCTAssertTrue(fm.fileExists(atPath: archive.path))
    }

    func testNoteStoreDoesNotMigrateTimestampedLegacyFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("12 04 2024 10:20.txt")
        try Data("coordinator-owned legacy note".utf8).write(to: source)

        let notes = try await NoteStore(rootURL: root).loadNotes()
        XCTAssertEqual(notes, [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Notes/notes.json").path))
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


    func testDeleteReceiptsReportsMigrationMarkerDeletionFailure() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let v2 = root.appendingPathComponent("V2", isDirectory: true)
        try fm.createDirectory(at: v2, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: v2.appendingPathComponent("migration-v2-complete.json"))
        defer { try? fm.removeItem(at: root) }
        let service = FileAppDataService(
            rootURL: root,
            fileManager: FailingMarkerRemovalFileManager(),
            receiptRepository: FileReceiptRepository(rootURL: root),
            calculationRepository: FileCalculationRepository(rootURL: root),
            preferencesRepository: FileUserPreferencesRepository(rootURL: root)
        )

        let report = await service.deleteReceipts()

        XCTAssertFalse(report.completedFully)
        XCTAssertEqual(report.failures.map(\.category), [.migrationMarkers])
        XCTAssertTrue(fm.fileExists(atPath: v2.appendingPathComponent("migration-v2-complete.json").path))
    }

    func testDeletionReportRequiresEnvironmentRefreshForPartialPreferenceDeletion() {
        let report = DataDeletionReport(
            deletedCategories: [.preferences],
            failures: [.init(category: .receipts, message: "Receipt deletion failed")]
        )

        XCTAssertFalse(report.completedFully)
        XCTAssertTrue(report.requiresEnvironmentRefresh)
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
            DetectedReceiptCharge(label: "Automatic gratuity", amount: 10, percentage: nil, kind: .automaticGratuity, confidence: 1, userClassification: .includedGratuity, isIncludedInReceiptTotal: true),
            DetectedReceiptCharge(label: "Included gratuity 5%", amount: nil, percentage: 5, kind: .includedGratuity, confidence: 1, userClassification: .includedGratuity, isIncludedInReceiptTotal: true),
            DetectedReceiptCharge(label: "Suggested tip", amount: 99, percentage: nil, kind: .suggestedGratuity, confidence: 1, userClassification: .suggestedGratuityOnly)
        ]
        let receipt = ReceiptRecord(id: UUID(), merchantName: "Fixture", receiptDate: nil, subtotal: 100, tax: 8, total: 123, detectedCharges: charges, imageFilename: nil, thumbnailFilename: nil, notes: "", createdAt: Date(), updatedAt: Date())
        XCTAssertEqual(receipt.confirmedIncludedGratuity(), .amount(15))
        XCTAssertEqual(receipt.tipCalculationInput().includedGratuityAmount, 15)
        XCTAssertEqual(SplitCalculatorContext.receipt(receipt).includedGratuityAmount, 15)
        XCTAssertEqual(receipt.convertibleAmounts.first(where: { $0.id == "included-gratuity" })?.amount, 15)
    }


    func testConfirmedGratuityWithoutIncludedTotalFlagIsNotCounted() {
        let charge = DetectedReceiptCharge(label: "Automatic gratuity", amount: 10, percentage: nil, kind: .automaticGratuity, confidence: 1, userClassification: .includedGratuity, isIncludedInReceiptTotal: nil)
        let receipt = ReceiptRecord(id: UUID(), merchantName: "Fixture", receiptDate: nil, subtotal: 100, tax: 8, total: 118, detectedCharges: [charge], imageFilename: nil, thumbnailFilename: nil, notes: "", createdAt: Date(), updatedAt: Date())
        XCTAssertEqual(receipt.confirmedIncludedGratuity(), .amount(0))
        XCTAssertEqual(receipt.tipCalculationInput().gratuityStatus, .no)
        XCTAssertNil(receipt.tipCalculationInput().includedGratuityAmount)
        XCTAssertNil(SplitCalculatorContext.receipt(receipt).includedGratuityAmount)
    }

    func testPercentageWithoutSubtotalRequiresReviewEverywhere() {
        let charge = DetectedReceiptCharge(label: "Included gratuity 18%", amount: nil, percentage: 18, kind: .includedGratuity, confidence: 1, userClassification: .includedGratuity, isIncludedInReceiptTotal: true)
        let receipt = ReceiptRecord(id: UUID(), merchantName: nil, receiptDate: nil, subtotal: nil, tax: nil, total: 118, detectedCharges: [charge], imageFilename: nil, thumbnailFilename: nil, notes: "", createdAt: Date(), updatedAt: Date())
        XCTAssertEqual(receipt.confirmedIncludedGratuity(), .needsSubtotal)
        XCTAssertEqual(receipt.tipCalculationInput().includedGratuityEntryMode, .unknown)
        XCTAssertNotNil(SplitCalculatorContext.receipt(receipt).handoffValidationMessage)
        XCTAssertNil(receipt.convertibleAmounts.first(where: { $0.id == "included-gratuity" }))
    }
    @MainActor
    func testPercentageOnlyReceiptCarriesTwentyDollarsIntoSplitAndReconciles() throws {
        let charge = DetectedReceiptCharge(label: "Included gratuity: 20%", amount: nil, percentage: 20, kind: .includedGratuity, confidence: 1, userClassification: .includedGratuity, isIncludedInReceiptTotal: true)
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
            DetectedReceiptCharge(label: "Gratuity", amount: 18, percentage: nil, kind: .automaticGratuity, confidence: 1, userClassification: .includedGratuity, isIncludedInReceiptTotal: true),
            DetectedReceiptCharge(label: "Delivery", amount: 5, percentage: nil, kind: .deliveryFee, confidence: 1, userClassification: .deliveryFee),
            DetectedReceiptCharge(label: "Service", amount: 4, percentage: nil, kind: .serviceCharge, confidence: 1, userClassification: .serviceChargeUnsure)
        ]
        let receipt = ReceiptRecord(id: UUID(), merchantName: nil, receiptDate: nil, subtotal: nil, tax: nil, total: nil, detectedCharges: charges, imageFilename: nil, thumbnailFilename: nil, notes: "", createdAt: Date(), updatedAt: Date())
        XCTAssertEqual(receipt.convertibleAmounts.first { $0.id == "included-gratuity" }?.amount, 18)
        XCTAssertEqual(receipt.convertibleAmounts.first { $0.id == "included-gratuity" }?.label, "Included gratuity")
    }

    func testPercentageOnlyReceiptGratuityIsConvertible() {
        let charge = DetectedReceiptCharge(label: "Gratuity 18%", amount: nil, percentage: 18, kind: .automaticGratuity, confidence: 1, userClassification: .includedGratuity, isIncludedInReceiptTotal: true)
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

    @MainActor func testImageAttemptReturnsToSourceOnlyWithoutDraft() {
        let model = ReceiptScannerViewModel(calculationRepository: IdentityCalculationRepository())
        model.cameraCancelled()
        XCTAssertEqual(model.stage, .sourceSelection)

        model.startManualEntry()
        let id = model.draft?.id
        model.cameraCancelled()
        XCTAssertEqual(model.stage, .confirmation)
        XCTAssertEqual(model.draft?.id, id)
    }

    @MainActor func testPhotoCancellationAndLoadFailurePreserveCompleteDraft() {
        let model = ReceiptScannerViewModel(calculationRepository: IdentityCalculationRepository())
        model.startManualEntry()
        let id = model.draft!.id
        model.draft?.merchantName = "Corner Cafe"
        model.draft?.subtotalText = "12.00"
        model.draft?.taxText = "1.00"
        model.draft?.totalText = "15.00"
        model.draft?.notes = "Window seat"
        model.draft?.detectedCharges = [.init(id: UUID(), label: "Service", amountText: "2.00", kind: .serviceCharge, confidence: 1, userClassification: .otherOrUnclear)]

        model.photoSelectionChanged(nil)
        XCTAssertEqual(model.stage, .confirmation)
        model.imageLoadingFailed()
        XCTAssertEqual(model.stage, .confirmation)
        XCTAssertEqual(model.draft?.id, id)
        XCTAssertEqual(model.draft?.merchantName, "Corner Cafe")
        XCTAssertEqual(model.draft?.subtotalText, "12.00")
        XCTAssertEqual(model.draft?.taxText, "1.00")
        XCTAssertEqual(model.draft?.totalText, "15.00")
        XCTAssertEqual(model.draft?.detectedCharges.first?.label, "Service")
        XCTAssertEqual(model.draft?.notes, "Window seat")
    }

    @MainActor func testManualEntryReopensRatherThanReplacingExistingDraft() {
        let model = ReceiptScannerViewModel(calculationRepository: IdentityCalculationRepository())
        model.startManualEntry()
        model.draft?.merchantName = "Preserved"
        let id = model.draft!.id
        model.startManualEntry()
        XCTAssertEqual(model.draft?.id, id)
        XCTAssertEqual(model.draft?.merchantName, "Preserved")
    }

    @MainActor func testExistingImageLoadsWithoutDirtyingEditAndReplacementDoes() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 8, height: 8)) }
        let receipt = scannerTestReceipt(imageFilename: "saved.jpg")
        let repository = ScannerReceiptRepository(receipt: receipt, imageResult: .success(image))
        let model = ReceiptScannerViewModel(context: .editReceipt(receipt.id), repository: repository, calculationRepository: IdentityCalculationRepository())

        await model.loadExistingReceiptIfNeeded()
        XCTAssertEqual(model.imageState, .existingLoaded)
        XCTAssertNotNil(model.draft?.sourceImage)
        XCTAssertNil(model.draft?.processed)
        XCTAssertNil(model.draft?.imageRevision)
        XCTAssertFalse(model.hasUnsavedChanges)

        model.process(image)
        for _ in 0..<100 where model.imageState != .replacementSelected { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(model.imageState, .replacementSelected)
        XCTAssertTrue(model.hasUnsavedChanges)
    }

    @MainActor func testMissingAndCorruptExistingImagesStayDistinctAndPreserveMetadata() async {
        for (error, expected): (ReceiptStorageError, ReceiptDraftImageState) in [(.imageMissing, .existingMissing), (.imageCorrupt, .existingCorrupt)] {
            let receipt = scannerTestReceipt(imageFilename: "saved.jpg")
            let repository = ScannerReceiptRepository(receipt: receipt, imageResult: .failure(error))
            let model = ReceiptScannerViewModel(context: .editReceipt(receipt.id), repository: repository, calculationRepository: IdentityCalculationRepository())
            await model.loadExistingReceiptIfNeeded()
            XCTAssertEqual(model.imageState, expected)
            XCTAssertEqual(model.draft?.merchantName, receipt.merchantName)
            XCTAssertEqual(model.draft?.notes, receipt.notes)
            XCTAssertFalse(model.hasUnsavedChanges)
        }
    }
}

private func scannerTestReceipt(imageFilename: String?) -> ReceiptRecord {
    ReceiptRecord(id: UUID(), merchantName: "Saved Cafe", receiptDate: Date(timeIntervalSince1970: 1_700_000_000), currencyCode: "USD", subtotal: 10, tax: 1, total: 13, detectedCharges: [], imageFilename: imageFilename, thumbnailFilename: nil, notes: "Saved note", createdAt: Date(timeIntervalSince1970: 1_700_000_000), updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
}

private final class ScannerReceiptRepository: ReceiptRepository, @unchecked Sendable {
    let receiptValue: ReceiptRecord
    let imageResult: Result<UIImage, Error>
    init(receipt: ReceiptRecord, imageResult: Result<UIImage, Error>) { receiptValue = receipt; self.imageResult = imageResult }
    func fetchReceipts() async throws -> [ReceiptRecord] { [receiptValue] }
    func receipt(id: UUID) async throws -> ReceiptRecord? { id == receiptValue.id ? receiptValue : nil }
    func create(draft: ReceiptRecord, fullImage: UIImage, thumbnail: UIImage) async throws -> ReceiptRecord { draft }
    func createMetadataOnly(draft: ReceiptRecord) async throws {}
    func saveReceipt(_ receipt: ReceiptRecord) async throws {}
    func replaceImage(receiptID: UUID, image: UIImage) async throws -> ReceiptRecord { receiptValue }
    func rename(receiptID: UUID, newName: String) async throws -> ReceiptRecord { receiptValue }
    func deleteReceipt(id: UUID) async throws {}
    func loadImage(filename: String) async throws -> UIImage { try imageResult.get() }
    func loadThumbnail(filename: String) async throws -> UIImage { try imageResult.get() }
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
