import XCTest
import UIKit
@testable import Tips_For_Tips

private struct TemporaryTestStore {
    let root: URL
    let defaults: UserDefaults
    init(_ testName: String = UUID().uuidString) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("TipsForTipsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "TipsForTipsTests.\(testName).\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}

private func testImage(_ color: UIColor = .blue) -> UIImage {
    UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24)).image { context in
        color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
    }
}

private func makeTipResult() throws -> TipCalculationResult {
    var input = TipCalculationInput.defaults(); input.subtotal = 40; input.tax = 4; input.serviceQuality = .good
    return try TipRecommendationEngine().calculate(input: input)
}

private func populateNonReceiptStores(root: URL, defaults: UserDefaults) async throws {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let note = SavedNote(id: UUID(), text: "Export note", createdAt: now, updatedAt: now)
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
    let notesURL = root.appendingPathComponent("Notes/notes.json")
    try FileManager.default.createDirectory(at: notesURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try encoder.encode(StoredDataEnvelope(version: 1, records: [note])).write(to: notesURL)

    let tip = try makeTipResult()
    let calculation = SavedCalculationRecord(id: UUID(), recordType: .tipOnly, tipResult: tip, splitResult: nil, receiptID: nil, merchantName: "Cafe", notes: "tip", currencyConversion: nil, shareSummary: nil, createdAt: now, updatedAt: now)
    let participants = [SplitParticipant(name: "A"), SplitParticipant(name: "B")]
    let session = SplitSession(id: UUID(), name: "Dinner", mode: .equal, currencyCode: "USD", subtotal: 40, tax: 4, tipAmount: 8, total: 52, participants: participants, items: [], taxAllocationMode: .proportional, tipAllocationMode: .proportional, roundingRule: .exactCents, sourceCalculationID: nil, receiptID: nil, createdAt: now, updatedAt: now)
    let split = try SplitCalculationEngine().calculate(session: session)
    let splitRecord = SavedCalculationRecord(id: UUID(), recordType: .split, tipResult: nil, splitResult: split, receiptID: nil, merchantName: "Dinner", notes: "split", currencyConversion: nil, shareSummary: nil, createdAt: now, updatedAt: now)
    let calculations = FileCalculationRepository(rootURL: root)
    try await calculations.saveCalculation(calculation); try await calculations.saveCalculation(splitRecord)

    defaults.set("guide-a", forKey: "guide.bookmarks")
    defaults.set("guide-a:Guide A", forKey: "guide.recent")
    defaults.set("USD,EUR", forKey: "currency.favoriteCodes")
    defaults.set("USD-EUR", forKey: "currency.recentPairs")
    let rate = CurrencyConversionSnapshot(sourceCurrencyCode: "USD", destinationCurrencyCode: "EUR", billAmount: 1, tipAmount: 0, totalAmount: 1, convertedBillAmount: 0.9, convertedTipAmount: 0, convertedTotalAmount: 0.9, rate: 0.9, rateDate: now, fetchedAt: now, usedCachedRate: false)
    try await FileCurrencyRateRepository(rootURL: root).saveRateSnapshot(rate)
}

final class CompleteExportRegressionTests: XCTestCase {
    func testCompleteExportContentsAndRecoveryOptIn() async throws {
        let store = try TemporaryTestStore(#function); defer { store.remove() }
        let receiptRepo = FileReceiptRepository(rootURL: store.root)
        let metadata = ReceiptRecord(id: UUID(), merchantName: "Metadata Only", receiptDate: nil, subtotal: 12, tax: 1, total: 13, detectedCharges: [], imageFilename: nil, thumbnailFilename: nil, notes: "no image", createdAt: .init(timeIntervalSince1970: 100), updatedAt: .init(timeIntervalSince1970: 100))
        try await receiptRepo.createMetadataOnly(draft: metadata)
        let imageID = UUID()
        let backed = ReceiptRecord(id: imageID, merchantName: "Image Receipt", receiptDate: nil, subtotal: 20, tax: 2, total: 22, detectedCharges: [], imageFilename: "\(imageID).jpg", thumbnailFilename: "\(imageID)-thumb.jpg", notes: "", createdAt: .init(timeIntervalSince1970: 200), updatedAt: .init(timeIntervalSince1970: 200))
        _ = try await receiptRepo.create(draft: backed, fullImage: testImage(), thumbnail: testImage(.green))
        let missing = ReceiptRecord(id: UUID(), merchantName: "Missing Optional Image", receiptDate: nil, subtotal: 3, tax: 0, total: 3, detectedCharges: [], imageFilename: "missing.jpg", thumbnailFilename: nil, notes: "", createdAt: .init(timeIntervalSince1970: 300), updatedAt: .init(timeIntervalSince1970: 300))
        try await receiptRepo.saveReceipt(missing)
        var preferences = UserPreferences.defaults; preferences.homeCurrencyCode = "CAD"; preferences.hasCompletedOnboarding = true
        let preferencesRepo = FileUserPreferencesRepository(rootURL: store.root); try await preferencesRepo.savePreferences(preferences)
        try await populateNonReceiptStores(root: store.root, defaults: store.defaults)
        let recovery = store.root.appendingPathComponent("V2/Backups/receipts.json.v1-backup")
        try FileManager.default.createDirectory(at: recovery.deletingLastPathComponent(), withIntermediateDirectories: true); try Data("recovery".utf8).write(to: recovery)
        let service = FileAppDataService(rootURL: store.root, receiptRepository: receiptRepo, calculationRepository: FileCalculationRepository(rootURL: store.root), preferencesRepository: preferencesRepo, userDefaults: store.defaults)

        let normal = try await service.createExport(includeRecoveryData: false)
        defer { try? FileManager.default.removeItem(at: normal.deletingLastPathComponent()) }
        let names = Set(try FileManager.default.contentsOfDirectory(atPath: normal.path))
        XCTAssertTrue(["preferences.json", "receipts.json", "calculations.json", "saved-splits.json", "notes.json", "guide-bookmarks.json", "guide-recents.json", "currency-favorites.json", "recent-currency-pairs.json", "currency-cache.json", "receipt-images", "receipt-thumbnails", "export-manifest.json"].allSatisfy(names.contains))
        XCTAssertFalse(names.contains("migration-recovery"))
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(AppDataExportManifest.self, from: Data(contentsOf: normal.appendingPathComponent("export-manifest.json")))
        XCTAssertEqual(manifest.exportSchemaVersion, 1)
        XCTAssertEqual(manifest.recordCounts["receipts"], 3); XCTAssertEqual(manifest.recordCounts["calculations"], 1); XCTAssertEqual(manifest.recordCounts["splits"], 1); XCTAssertEqual(manifest.recordCounts["notes"], 1)
        XCTAssertEqual(manifest.recordCounts["guideBookmarks"], 1); XCTAssertEqual(manifest.recordCounts["guideRecents"], 1); XCTAssertEqual(manifest.recordCounts["currencyFavorites"], 2); XCTAssertEqual(manifest.recordCounts["recentCurrencyPairs"], 1); XCTAssertEqual(manifest.recordCounts["cachedExchangeRates"], 1)
        XCTAssertEqual(manifest.missingOptionalImageFiles, ["missing.jpg"]); XCTAssertFalse(manifest.recoveryDataIncluded)
        let exportedReceipts = try decoder.decode([ReceiptRecord].self, from: Data(contentsOf: normal.appendingPathComponent("receipts.json")))
        XCTAssertNil(exportedReceipts.first(where: { $0.id == metadata.id })?.imageFilename)
        XCTAssertTrue(FileManager.default.fileExists(atPath: normal.appendingPathComponent("receipt-images/\(imageID).jpg").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: normal.appendingPathComponent("receipt-thumbnails/\(imageID)-thumb.jpg").path))
        for url in try FileManager.default.contentsOfDirectory(at: normal, includingPropertiesForKeys: nil) where url.pathExtension == "json" {
            XCTAssertFalse(try String(contentsOf: url).contains(store.root.path), "Export leaked an absolute internal path in \(url.lastPathComponent)")
        }
        let optedIn = try await service.createExport(includeRecoveryData: true)
        defer { try? FileManager.default.removeItem(at: optedIn.deletingLastPathComponent()) }
        XCTAssertEqual(try Data(contentsOf: optedIn.appendingPathComponent("migration-recovery/receipts.json.v1-backup")), Data("recovery".utf8))
    }
}

final class DeleteAllRelaunchRegressionTests: XCTestCase {
    @MainActor func testDeleteAllThenRelaunchPreservesRecoveryByDefault() async throws { try await assertDeleteAndRelaunch(includeRecovery: false) }
    @MainActor func testDeleteAllThenRelaunchDeletesRecoveryWhenRequested() async throws { try await assertDeleteAndRelaunch(includeRecovery: true) }

    @MainActor private func assertDeleteAndRelaunch(includeRecovery: Bool) async throws {
        let store = try TemporaryTestStore(#function); defer { store.remove() }
        var environment: AppEnvironment? = AppEnvironment(rootURL: store.root, userDefaults: store.defaults)
        try await environment!.receiptRepository.createMetadataOnly(draft: ReceiptRecord(id: UUID(), merchantName: "Delete", receiptDate: nil, subtotal: 1, tax: 0, total: 1, detectedCharges: [], imageFilename: nil, thumbnailFilename: nil, notes: "", createdAt: Date(), updatedAt: Date()))
        try await populateNonReceiptStores(root: store.root, defaults: store.defaults)
        var prefs = UserPreferences.defaults; prefs.hasCompletedOnboarding = true; try await environment!.preferencesRepository.savePreferences(prefs)
        let backup = store.root.appendingPathComponent("V2/Backups/recovery.bin"); try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true); try Data([1]).write(to: backup)
        let report = await environment!.dataService.deleteAllLocalData(includeRecoveryData: includeRecovery)
        XCTAssertTrue(report.completedFully, "\(report.failures)")
        environment = nil
        let relaunched = AppEnvironment(rootURL: store.root, userDefaults: store.defaults); await relaunched.prepare()
        let receipts = try await relaunched.receiptRepository.fetchReceipts()
        let calculations = try await relaunched.calculationRepository.fetchCalculations()
        let notes = try await NoteStore(rootURL: store.root).loadNotes()
        let cachedRate = try await relaunched.currencyRateRepository.cachedRate(from: "USD", to: "EUR")
        XCTAssertEqual(receipts.count, 0); XCTAssertEqual(calculations.count, 0); XCTAssertEqual(notes.count, 0); XCTAssertNil(cachedRate)
        XCTAssertEqual(relaunched.preferences, .defaults); XCTAssertEqual(relaunched.rootRoute, .onboarding)
        XCTAssertEqual(FileManager.default.fileExists(atPath: backup.path), !includeRecovery)
        XCTAssertNil(store.defaults.string(forKey: "guide.bookmarks")); XCTAssertNil(store.defaults.string(forKey: "currency.recentPairs"))
    }
}

final class HistoricalReceiptDecodingRegressionTests: XCTestCase {
    func testPrePR33ReceiptPreservesFieldsAndRequiresFinancialReview() throws {
        // This fixture matches ReceiptRecord immediately before merge PR #33 (commit a27566d):
        // it intentionally has neither financialReviewVersion nor charge review attribution.
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/PrePR33/receipt-record.json")
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let receipt = try decoder.decode(ReceiptRecord.self, from: Data(contentsOf: fixture))
        XCTAssertEqual(receipt.id.uuidString, "8B26D588-1581-4DF0-A899-4D52F4E24910")
        XCTAssertEqual(receipt.merchantName, "Harbor House")
        XCTAssertEqual(receipt.receiptDate, Date(timeIntervalSince1970: 1_739_561_400))
        XCTAssertEqual(receipt.createdAt, Date(timeIntervalSince1970: 1_739_561_700))
        XCTAssertEqual(receipt.updatedAt, Date(timeIntervalSince1970: 1_739_561_760))
        XCTAssertEqual(receipt.subtotal, 84.50); XCTAssertEqual(receipt.tax, 7.18); XCTAssertEqual(receipt.total, 109.68)
        XCTAssertEqual(receipt.imageFilename, "8B26D588-1581-4DF0-A899-4D52F4E24910.jpg")
        XCTAssertEqual(receipt.thumbnailFilename, "8B26D588-1581-4DF0-A899-4D52F4E24910-thumb.jpg")
        XCTAssertEqual(receipt.recognizedText, "HARBOR HOUSE\nSubtotal 84.50\nTax 7.18\nAutomatic Gratuity 18.00\nTotal 109.68")
        XCTAssertEqual(receipt.notes, "Birthday dinner")
        XCTAssertNil(receipt.financialReviewVersion); XCTAssertEqual(receipt.detectedCharges.first?.source, .migrated)
        XCTAssertTrue(receipt.hasUnreviewedFinancialCharges)
        XCTAssertFalse(ReceiptFinancialReviewValidator().review(receipt).isReadyForFinancialUse)
    }
}

final class ReceiptEditPersistenceRegressionTests: XCTestCase {
    func testReceiptDetailAlwaysUsesSharedEditorWithReviewAwareTitle() {
        let reviewed = ReceiptRecord(id: UUID(), merchantName: "Reviewed", receiptDate: nil, subtotal: 10, tax: 1, total: 11, detectedCharges: [], imageFilename: nil, thumbnailFilename: nil, notes: "", confirmationStatus: .userConfirmed, createdAt: Date(), updatedAt: Date(), financialReviewVersion: ReceiptFinancialReviewValidator.currentVersion)
        let charge = DetectedReceiptCharge(label: "Service charge", amount: 2, percentage: 20, kind: .serviceCharge, confidence: 1, userClassification: .unreviewed)
        let needsReview = ReceiptRecord(id: UUID(), merchantName: "Review", receiptDate: nil, subtotal: 10, tax: 1, total: 13, detectedCharges: [charge], imageFilename: nil, thumbnailFilename: nil, notes: "", confirmationStatus: .needsReview, createdAt: Date(), updatedAt: Date())

        XCTAssertEqual(ReceiptDetailEditAction.title(for: reviewed), "Edit Receipt")
        XCTAssertEqual(ReceiptDetailEditAction.context(for: reviewed), .editReceipt(reviewed.id))
        XCTAssertEqual(ReceiptDetailEditAction.title(for: needsReview), "Edit and Review Charges")
        XCTAssertEqual(ReceiptDetailEditAction.context(for: needsReview), .editReceipt(needsReview.id))
    }

    @MainActor func testEditingExistingReceiptPersistsIdentityDatesImageAndValuesWithoutDuplicate() async throws {
        let store = try TemporaryTestStore(#function); defer { store.remove() }
        let repo = FileReceiptRepository(rootURL: store.root)
        let calculationRepo = FileCalculationRepository(rootURL: store.root)
        let id = UUID(), created = Date(timeIntervalSince1970: 1_700_000_000)
        let falseChargeID = UUID()
        let falseCharge = DetectedReceiptCharge(id: falseChargeID, label: "False OCR charge", amount: 99, percentage: nil, kind: .unknownCharge, confidence: 0.2, userClassification: .otherOrUnclear, isIncludedInReceiptTotal: false, source: .ocr)
        let unreviewedCharge = DetectedReceiptCharge(label: "Possible service charge", amount: 2, percentage: 18, kind: .serviceCharge, confidence: 0.7, userClassification: .unreviewed, source: .ocr)
        let original = ReceiptRecord(id: id, merchantName: "Old", receiptDate: created, currencyCode: "USD", subtotal: 10, tax: 1, total: 11, detectedCharges: [falseCharge, unreviewedCharge], imageFilename: "\(id).jpg", thumbnailFilename: "\(id)-thumb.jpg", recognizedText: "ORIGINAL OCR TEXT", notes: "old", confirmationStatus: .needsReview, createdAt: created, updatedAt: created)
        _ = try await repo.create(draft: original, fullImage: testImage(), thumbnail: testImage())
        let linked = SavedCalculationRecord(id: UUID(), recordType: .tipOnly, tipResult: nil, splitResult: nil, receiptID: id, merchantName: "Old", notes: "linked", currencyConversion: nil, shareSummary: nil, createdAt: created, updatedAt: created)
        try await calculationRepo.saveCalculation(linked)
        let model = ReceiptScannerViewModel(context: .editReceipt(id), repository: repo, calculationRepository: calculationRepo)
        await model.loadExistingReceiptIfNeeded()
        XCTAssertTrue(model.hasUnreviewedFinancialCharges)
        let editedDate = Date(timeIntervalSince1970: 1_710_000_000)
        let addedChargeID = UUID()
        model.draft?.merchantName = "New Merchant"; model.draft?.receiptDate = editedDate; model.draft?.currencyCode = "CAD"; model.draft?.subtotalText = "20.00"; model.draft?.taxText = "2.00"; model.draft?.totalText = "25.00"; model.draft?.notes = "updated"
        model.draft?.detectedCharges = [.init(id: addedChargeID, label: "Service charge", amountText: "3.00", percentageText: "15", amount: 3, percentage: 15, kind: .serviceCharge, confidence: 1, userClassification: .serviceChargeNotGratuity, isIncludedInReceiptTotal: true, source: .manual)]
        XCTAssertFalse(model.hasUnreviewedFinancialCharges)
        let savedID = await model.saveReceipt(); XCTAssertEqual(savedID, id)

        let loaded = try await FileReceiptRepository(rootURL: store.root).receipt(id: id)
        let reloaded = try XCTUnwrap(loaded)
        XCTAssertEqual(reloaded.id, id); XCTAssertEqual(reloaded.createdAt, created)
        XCTAssertGreaterThan(reloaded.updatedAt, created)
        XCTAssertEqual(reloaded.merchantName, "New Merchant"); XCTAssertEqual(reloaded.receiptDate, editedDate); XCTAssertEqual(reloaded.currencyCode, "CAD")
        XCTAssertEqual(reloaded.subtotal, 20); XCTAssertEqual(reloaded.tax, 2); XCTAssertEqual(reloaded.total, 25); XCTAssertEqual(reloaded.notes, "updated")
        XCTAssertEqual(reloaded.detectedCharges.count, 1); XCTAssertFalse(reloaded.detectedCharges.contains { $0.id == falseChargeID })
        XCTAssertEqual(reloaded.detectedCharges.first?.id, addedChargeID); XCTAssertEqual(reloaded.detectedCharges.first?.amount, 3); XCTAssertEqual(reloaded.detectedCharges.first?.percentage, 15); XCTAssertEqual(reloaded.detectedCharges.first?.label, "Service charge")
        XCTAssertEqual(reloaded.detectedCharges.first?.userClassification, .serviceChargeNotGratuity); XCTAssertEqual(reloaded.detectedCharges.first?.isIncludedInReceiptTotal, true)
        XCTAssertEqual(reloaded.imageFilename, "\(id).jpg"); XCTAssertEqual(reloaded.thumbnailFilename, "\(id)-thumb.jpg")
        XCTAssertEqual(reloaded.recognizedText, "ORIGINAL OCR TEXT")
        let preservedImage = try await repo.loadImage(filename: "\(id).jpg")
        let preservedThumbnail = try await repo.loadThumbnail(filename: "\(id)-thumb.jpg")
        XCTAssertNotNil(preservedImage); XCTAssertNotNil(preservedThumbnail)
        XCTAssertTrue(ReceiptFinancialReviewValidator().review(reloaded).isReadyForFinancialUse)
        let linkedAfterEdit = try await calculationRepo.fetchCalculations().first { $0.id == linked.id }
        XCTAssertEqual(linkedAfterEdit?.receiptID, id)
        let allReceipts = try await FileReceiptRepository(rootURL: store.root).fetchReceipts(); XCTAssertEqual(allReceipts.count, 1)
    }
}

private struct StubOCR: ReceiptTextRecognizing {
    let result: Result<RecognizedReceiptText, Error>
    func recognizeText(in image: CGImage) async throws -> RecognizedReceiptText { try result.get() }
}
private struct StubParser: ReceiptFieldParsing {
    let detection: ReceiptDetectionResult
    func parse(recognizedText: RecognizedReceiptText, locale: Locale) -> ReceiptDetectionResult { detection }
}
private enum StubOCRError: Error { case failed }

final class OCRInitializationRegressionTests: XCTestCase {
    private func detection() -> ReceiptDetectionResult {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        return ReceiptDetectionResult(merchantCandidates: [.init(value: "OCR Cafe", confidence: 0.9, sourceText: "OCR Cafe")], dateCandidates: [.init(value: date, confidence: 0.9, sourceText: "Nov 14")], subtotalCandidates: [.init(value: 100, confidence: 0.9, sourceText: "Subtotal")], taxCandidates: [.init(value: 8, confidence: 0.9, sourceText: "Tax")], totalCandidates: [.init(value: 128, confidence: 0.9, sourceText: "Total")], chargeCandidates: [.init(id: UUID(), label: "Automatic gratuity", amount: 20, percentage: 20, kind: .automaticGratuity, confidence: 0.95)], currencyCandidates: [.init(value: "EUR", confidence: 0.9, sourceText: "EUR")], warnings: [])
    }

    @MainActor func testOCRInitializesEveryDraftValueAndFinancialChargeUnreviewed() async throws {
        let recognized = RecognizedReceiptText(observations: [], fullText: "fixture")
        var prefs = UserPreferences.defaults; prefs.homeCurrencyCode = "USD"
        let model = ReceiptScannerViewModel(preferences: prefs, recognizer: StubOCR(result: .success(recognized)), parser: StubParser(detection: detection()), calculationRepository: IdentityCalculationRepositoryForCoverage())
        model.process(testImage()); try await waitForOCR(model)
        XCTAssertEqual(model.draft?.merchantName, "OCR Cafe"); XCTAssertEqual(model.draft?.receiptDate, Date(timeIntervalSince1970: 1_700_000_000)); XCTAssertEqual(model.draft?.currencyCode, "EUR")
        XCTAssertEqual(model.draft?.subtotalText, "100"); XCTAssertEqual(model.draft?.taxText, "8"); XCTAssertEqual(model.draft?.totalText, "128")
        let charge = try XCTUnwrap(model.draft?.detectedCharges.first)
        XCTAssertEqual(charge.label, "Automatic gratuity"); XCTAssertEqual(charge.amountText, "20"); XCTAssertEqual(charge.percentageText, "20"); XCTAssertEqual(charge.userClassification, .unreviewed)
        XCTAssertTrue(model.hasUnreviewedFinancialCharges)
    }

    @MainActor func testLaterOCRDoesNotOverwriteEditedFields() async throws {
        let recognized = RecognizedReceiptText(observations: [], fullText: "fixture")
        let model = ReceiptScannerViewModel(recognizer: StubOCR(result: .success(recognized)), parser: StubParser(detection: detection()), calculationRepository: IdentityCalculationRepositoryForCoverage())
        model.startManualEntry(); model.draft?.merchantName = "Edited"; model.draft?.receiptDate = Date(timeIntervalSince1970: 42); model.draft?.currencyCode = "CAD"; model.draft?.subtotalText = "9"; model.draft?.taxText = "1"; model.draft?.totalText = "10"; model.draft?.notes = "keep"; model.draft?.detectedCharges = [.init(id: UUID(), label: "Edited fee", amountText: "2", percentageText: "", amount: 2, percentage: nil, kind: .deliveryFee, confidence: 1, userClassification: .deliveryFee)]
        model.process(testImage()); try await waitForOCR(model)
        XCTAssertEqual(model.draft?.merchantName, "Edited"); XCTAssertEqual(model.draft?.receiptDate, Date(timeIntervalSince1970: 42)); XCTAssertEqual(model.draft?.currencyCode, "CAD"); XCTAssertEqual(model.draft?.subtotalText, "9"); XCTAssertEqual(model.draft?.taxText, "1"); XCTAssertEqual(model.draft?.totalText, "10"); XCTAssertEqual(model.draft?.notes, "keep"); XCTAssertEqual(model.draft?.detectedCharges.first?.label, "Edited fee")
    }

    @MainActor func testOCRFailurePreservesExistingDraft() async throws {
        let model = ReceiptScannerViewModel(recognizer: StubOCR(result: .failure(StubOCRError.failed)), parser: StubParser(detection: detection()), calculationRepository: IdentityCalculationRepositoryForCoverage())
        model.startManualEntry(); let id = model.draft!.id; model.draft?.merchantName = "Keep me"; model.draft?.subtotalText = "17"; model.draft?.notes = "existing"
        model.process(testImage()); try await waitForOCR(model)
        XCTAssertEqual(model.draft?.id, id); XCTAssertEqual(model.draft?.merchantName, "Keep me"); XCTAssertEqual(model.draft?.subtotalText, "17"); XCTAssertEqual(model.draft?.notes, "existing"); XCTAssertEqual(model.stage, .confirmation); XCTAssertNotNil(model.message)
    }

    @MainActor private func waitForOCR(_ model: ReceiptScannerViewModel) async throws {
        for _ in 0..<200 where model.stage == .processing { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertNotEqual(model.stage, .processing)
    }
}

private actor IdentityCalculationRepositoryForCoverage: CalculationRepository {
    private var records: [SavedCalculationRecord] = []
    func fetchCalculations() async throws -> [SavedCalculationRecord] { records }
    func saveCalculation(_ record: SavedCalculationRecord) async throws { records.removeAll { $0.id == record.id }; records.append(record) }
    func deleteCalculation(id: UUID) async throws { records.removeAll { $0.id == id } }
}

final class OnboardingRoutingRegressionTests: XCTestCase {
    @MainActor func testFreshCompletionAndRelaunchUseActualRootRoute() async throws {
        let store = try TemporaryTestStore(#function); defer { store.remove() }
        var environment: AppEnvironment? = AppEnvironment(rootURL: store.root, userDefaults: store.defaults)
        XCTAssertEqual(environment!.rootRoute, .loading); await environment!.prepare(); XCTAssertEqual(environment!.rootRoute, .onboarding)
        try await environment!.updatePreferences { $0.hasCompletedOnboarding = true }
        XCTAssertEqual(environment!.rootRoute, .mainMenu); let persisted = try await FileUserPreferencesRepository(rootURL: store.root).loadPreferences(); XCTAssertTrue(persisted.hasCompletedOnboarding)
        environment = nil
        let relaunched = AppEnvironment(rootURL: store.root, userDefaults: store.defaults); await relaunched.prepare(); XCTAssertEqual(relaunched.rootRoute, .mainMenu)
    }

    @MainActor func testRestartOnboardingIsImmediateAndPreservesUserData() async throws {
        let store = try TemporaryTestStore(#function); defer { store.remove() }
        let environment = AppEnvironment(rootURL: store.root, userDefaults: store.defaults)
        var prefs = UserPreferences.defaults; prefs.hasCompletedOnboarding = true; try await environment.preferencesRepository.savePreferences(prefs); await environment.prepare()
        try await environment.receiptRepository.createMetadataOnly(draft: ReceiptRecord(id: UUID(), merchantName: "Keep", receiptDate: nil, subtotal: 1, tax: 0, total: 1, detectedCharges: [], imageFilename: nil, thumbnailFilename: nil, notes: "", createdAt: Date(), updatedAt: Date()))
        try await populateNonReceiptStores(root: store.root, defaults: store.defaults)
        try await environment.updatePreferences { $0.hasCompletedOnboarding = false }
        XCTAssertEqual(environment.rootRoute, .onboarding)
        let receipts = try await environment.receiptRepository.fetchReceipts(); let notes = try await NoteStore(rootURL: store.root).loadNotes(); let calculations = try await environment.calculationRepository.fetchCalculations()
        XCTAssertEqual(receipts.count, 1); XCTAssertEqual(notes.count, 1); XCTAssertEqual(calculations.filter { $0.tipResult != nil }.count, 1)
        try await environment.updatePreferences { $0.hasCompletedOnboarding = true }; XCTAssertEqual(environment.rootRoute, .mainMenu)
    }

    @MainActor func testDeleteAllReturnsCompletedUserToOnboarding() async throws {
        let store = try TemporaryTestStore(#function); defer { store.remove() }
        let environment = AppEnvironment(rootURL: store.root, userDefaults: store.defaults); var prefs = UserPreferences.defaults; prefs.hasCompletedOnboarding = true; try await environment.preferencesRepository.savePreferences(prefs); await environment.prepare(); XCTAssertEqual(environment.rootRoute, .mainMenu)
        let report = await environment.dataService.deleteAllLocalData(includeRecoveryData: false); XCTAssertTrue(report.completedFully); await environment.resetAfterDataDeletion()
        XCTAssertEqual(environment.rootRoute, .onboarding); XCTAssertFalse(environment.preferences.hasCompletedOnboarding)
    }
}
