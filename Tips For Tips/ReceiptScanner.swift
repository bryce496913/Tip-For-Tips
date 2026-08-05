import SwiftUI
import PhotosUI
import Vision
import AVFoundation
import UIKit

// MARK: - Scanner routing and state

enum ReceiptScannerContext: Hashable { case newReceipt, attachToCalculation(UUID), replaceImage(UUID), editReceipt(UUID) }
enum ReceiptScanStage: Equatable { case sourceSelection, capturing, processing, confirmation, saving, completed, failure }
enum ReceiptScannerPresentation: Identifiable { case camera; var id: String { "camera" } }

enum DetectionConfidence: String, Equatable { case high, medium, low
    init(_ value: Decimal) { self = value >= 0.78 ? .high : (value >= 0.5 ? .medium : .low) }
    var reviewText: String { self == .low ? "Please check this value" : (self == .medium ? "Review suggested value" : "Detected confidently") }
}

struct RecognizedTextObservation: Equatable, Hashable { var text: String; var confidence: Float; var boundingBox: CGRect; var candidates: [String] }
struct RecognizedReceiptText: Equatable, Hashable { var observations: [RecognizedTextObservation]; var fullText: String }
struct DetectedField<Value: Equatable>: Equatable { let value: Value; let confidence: Decimal; let sourceText: String }
enum ReceiptDetectionWarning: String, Equatable, Identifiable { case amountsDoNotAddUp, multipleTotals, serviceChargeMayNotBeGratuity, suggestedGratuityNotIncluded, receiptMayAlreadyContainGratuity, lowConfidenceFields; var id: String { rawValue }
    var message: String { switch self { case .amountsDoNotAddUp: return "The detected amounts do not add up to the total."; case .multipleTotals: return "More than one possible total was found."; case .serviceChargeMayNotBeGratuity: return "A service charge was found, but it may not be a gratuity."; case .suggestedGratuityNotIncluded: return "Suggested gratuity amounts were found and are not included in the total."; case .receiptMayAlreadyContainGratuity: return "The receipt may already contain gratuity."; case .lowConfidenceFields: return "Some detected values need review." } }
}
struct ReceiptDetectionResult: Equatable { var merchantCandidates: [DetectedField<String>] = []; var dateCandidates: [DetectedField<Date>] = []; var subtotalCandidates: [DetectedField<Decimal>] = []; var taxCandidates: [DetectedField<Decimal>] = []; var totalCandidates: [DetectedField<Decimal>] = []; var chargeCandidates: [DetectedReceiptCharge] = []; var currencyCandidates: [DetectedField<String>] = []; var warnings: [ReceiptDetectionWarning] = [] }

struct ProcessedReceiptImage { let fullImage: UIImage; let ocrImage: CGImage; let thumbnail: UIImage }

protocol ReceiptTextRecognizing { func recognizeText(in image: CGImage) async throws -> RecognizedReceiptText }
protocol ReceiptFieldParsing { func parse(recognizedText: RecognizedReceiptText, locale: Locale) -> ReceiptDetectionResult }

struct VisionReceiptTextRecognizer: ReceiptTextRecognizing {
    func recognizeText(in image: CGImage) async throws -> RecognizedReceiptText {
        try Task.checkCancellation()
        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate; request.usesLanguageCorrection = true; request.recognitionLanguages = ["en-US"]
            let handler = VNImageRequestHandler(cgImage: image, options: [:]); try handler.perform([request]); try Task.checkCancellation()
            let observations = (request.results ?? []).compactMap { observation -> RecognizedTextObservation? in
                guard let top = observation.topCandidates(3).first else { return nil }
                return RecognizedTextObservation(text: top.string, confidence: top.confidence, boundingBox: observation.boundingBox, candidates: observation.topCandidates(3).map(\.string))
            }
            if observations.isEmpty { throw ReceiptScannerError.noTextFound }
            return RecognizedReceiptText(observations: observations, fullText: observations.map(\.text).joined(separator: "\n"))
        }.value
    }
}

enum ReceiptScannerError: LocalizedError { case cameraUnavailable, cameraDenied, imageLoadFailed, imageDecodeFailed, noTextFound, ocrFailed, saveFailed, invalidCalculationAmount
    var errorDescription: String? { switch self { case .cameraUnavailable: return "Camera is not available on this device. Choose a receipt from your photo library instead."; case .cameraDenied: return "Camera access is turned off. You can enable it in Settings or choose a receipt from your photo library."; case .imageLoadFailed: return "We could not load that receipt image. Try another photo or enter values manually."; case .imageDecodeFailed: return "We could not prepare that receipt image. Try another photo."; case .noTextFound, .ocrFailed: return "We couldn’t read all the details from this receipt. You can enter the values manually or try another photo."; case .saveFailed: return "We could not save this receipt. Please try again."; case .invalidCalculationAmount: return "Enter a valid subtotal or final total before continuing to the Tip Assistant." } }
}

struct ReceiptImageProcessor { static func process(_ image: UIImage) async throws -> ProcessedReceiptImage { try await Task.detached(priority: .userInitiated) { let normalized = image.normalizedForReceipt(); let full = normalized.resizedForReceipt(maxDimension: 2200); let ocr = normalized.resizedForReceipt(maxDimension: 1800); let thumb = normalized.resizedForReceipt(maxDimension: 420); guard let cg = ocr.cgImage else { throw ReceiptScannerError.imageDecodeFailed }; return ProcessedReceiptImage(fullImage: full, ocrImage: cg, thumbnail: thumb) }.value } }

struct ReceiptAmountParser {
    static func parse(_ text: String, locale: Locale = .current, expectedCurrencyCode: String? = "USD") -> Decimal? {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !cleaned.contains("%"), !cleaned.hasPrefix("-") else { return nil }
        if let code = expectedCurrencyCode, !code.isEmpty { cleaned = cleaned.replacingOccurrences(of: code, with: "", options: [.caseInsensitive, .anchored]) }
        if expectedCurrencyCode?.uppercased() == "USD" { cleaned = cleaned.replacingOccurrences(of: "$", with: "") }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "")
        guard !cleaned.isEmpty, cleaned.range(of: #"[A-Za-z]"#, options: .regularExpression) == nil else { return nil }
        guard cleaned.allSatisfy({ $0.isNumber || $0 == "." || $0 == "," }) else { return nil }
        let decimalSeparator = locale.decimalSeparator ?? "."
        let dotCount = cleaned.filter { $0 == "." }.count
        let commaCount = cleaned.filter { $0 == "," }.count
        let actualDecimal: Character?
        if dotCount > 0 && commaCount > 0 { actualDecimal = cleaned.lastIndex(of: ".")! > cleaned.lastIndex(of: ",")! ? "." : "," }
        else if dotCount == 1 && decimalSeparator == "." { actualDecimal = "." }
        else if commaCount == 1 && decimalSeparator == "," { actualDecimal = "," }
        else if commaCount == 1 && decimalSeparator == "." && !isValidGrouped(cleaned, separator: ",") { actualDecimal = "," }
        else if dotCount == 1 && decimalSeparator == "," && !isValidGrouped(cleaned, separator: ".") { actualDecimal = "." }
        else { actualDecimal = nil }
        if dotCount > 1 && actualDecimal == "." || commaCount > 1 && actualDecimal == "," { return nil }
        var integerPart = cleaned
        var fractionPart: String? = nil
        if let dec = actualDecimal, let idx = cleaned.lastIndex(of: dec) {
            integerPart = String(cleaned[..<idx]); fractionPart = String(cleaned[cleaned.index(after: idx)...])
            guard let fractionPart, (1...2).contains(fractionPart.count), fractionPart.allSatisfy(\.isNumber) else { return nil }
        }
        let groupChars = [",", "."].filter { Character($0) != actualDecimal }
        for sep in groupChars where integerPart.contains(sep) { guard isValidGrouped(integerPart, separator: Character(sep)) else { return nil } }
        for sep in groupChars { integerPart = integerPart.replacingOccurrences(of: sep, with: "") }
        guard !integerPart.isEmpty, integerPart.allSatisfy(\.isNumber) else { return nil }
        let normalized = integerPart + fractionPart.map { "." + $0 }.or("")
        guard let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")), value >= 0 else { return nil }
        return value
    }
    private static func isValidGrouped(_ text: String, separator: Character) -> Bool {
        let parts = text.split(separator: separator, omittingEmptySubsequences: false)
        guard parts.count > 1, (1...3).contains(parts[0].count), parts[0].allSatisfy(\.isNumber) else { return false }
        return parts.dropFirst().allSatisfy { $0.count == 3 && $0.allSatisfy(\.isNumber) }
    }
}

struct ReceiptFieldParser: ReceiptFieldParsing {
    func parse(recognizedText: RecognizedReceiptText, locale: Locale = .current) -> ReceiptDetectionResult {
        let lines = recognizedText.observations.isEmpty ? recognizedText.fullText.split(separator: "\n").map { RecognizedTextObservation(text: String($0), confidence: 0.55, boundingBox: .zero, candidates: []) } : recognizedText.observations
        var result = ReceiptDetectionResult(); if recognizedText.fullText.contains("$") { result.currencyCandidates.append(.init(value: "USD", confidence: 0.7, sourceText: "$")) }
        detectMerchant(lines, &result); detectDates(lines, &result); detectAmounts(lines, &result); detectCharges(lines, &result); reconcile(&result); return result
    }
    private func detectMerchant(_ lines: [RecognizedTextObservation], _ result: inout ReceiptDetectionResult) { for line in lines.prefix(6) { let t = line.text.trimmingCharacters(in: .whitespaces); let lower = t.lowercased(); if t.count > 2 && !t.contains(where: { $0.isNumber }) && !lower.contains("receipt") && !lower.contains("tel") && !lower.contains("www") { result.merchantCandidates.append(.init(value: t, confidence: Decimal(Double(line.confidence)) * 0.9, sourceText: t)) } } }
    private func detectDates(_ lines: [RecognizedTextObservation], _ result: inout ReceiptDetectionResult) { let fmts = ["M/d/yyyy", "MM/dd/yyyy", "M/d/yy", "MM/dd/yy", "MMM d, yyyy", "MMM d yyyy"]; let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); for line in lines { guard !looksLikePhoneOrCard(line.text) else { continue }; for fmt in fmts { formatter.dateFormat = fmt; if let match = line.text.range(of: #"\b(?:\d{1,2}/\d{1,2}/\d{2,4}|[A-Za-z]{3}\s+\d{1,2},?\s+\d{4})\b"#, options: .regularExpression), let date = formatter.date(from: String(line.text[match])) { result.dateCandidates.append(.init(value: date, confidence: Decimal(Double(line.confidence)) * 0.85, sourceText: line.text)); break } } } }
    private func detectAmounts(_ lines: [RecognizedTextObservation], _ result: inout ReceiptDetectionResult) { for line in lines { let lower = line.text.lowercased(); guard let amount = lastAmount(in: line.text), !looksLikePhoneOrCard(line.text), !lower.contains("change"), !lower.contains("cash tender"), !lower.contains("auth") else { continue }; let conf = Decimal(Double(line.confidence)); if lower.contains("subtotal") || lower.contains("sub total") || lower.contains("net amount") { result.subtotalCandidates.append(.init(value: amount, confidence: conf * 0.95, sourceText: line.text)) } else if lower.contains("tax") && !lower.contains("tip") { result.taxCandidates.append(.init(value: amount, confidence: conf * 0.9, sourceText: line.text)) } else if (lower.contains("grand total") || lower.contains("amount due") || lower.contains("balance due") || lower.contains("check total") || lower == "total" || lower.hasPrefix("total ")) && !lower.contains("subtotal") && !lower.contains("suggest") { result.totalCandidates.append(.init(value: amount, confidence: conf * 0.95, sourceText: line.text)) } }
        if result.taxCandidates.count > 1 { let sum = result.taxCandidates.reduce(Decimal(0)) { $0 + $1.value }; result.taxCandidates.insert(.init(value: sum, confidence: 0.7, sourceText: "Combined tax lines"), at: 0) }
    }
    private func detectCharges(_ lines: [RecognizedTextObservation], _ result: inout ReceiptDetectionResult) { for line in lines { let lower = line.text.lowercased(); let kind: ReceiptChargeKind? = lower.contains("suggest") || lower.contains("tip guide") || lower.contains("gratuity guide") ? .suggestedGratuity : lower.contains("auto gratuity") || lower.contains("automatic gratuity") ? .automaticGratuity : lower.contains("included gratuity") || lower.contains("gratuity") ? .includedGratuity : lower.contains("hospitality") ? .hospitalityCharge : lower.contains("admin") ? .administrativeFee : lower.contains("delivery") ? .deliveryFee : lower.contains("service charge") ? .serviceCharge : nil; guard let kind else { continue }; let percent = percentAmount(in: line.text); let amount = lastAmount(in: line.text); result.chargeCandidates.append(DetectedReceiptCharge(label: line.text, amount: amount, percentage: percent, kind: kind, confidence: Decimal(Double(line.confidence)) * (kind == .suggestedGratuity ? 0.75 : 0.85), userClassification: nil)); if [.serviceCharge, .hospitalityCharge, .administrativeFee].contains(kind) { result.warnings.append(.serviceChargeMayNotBeGratuity) }; if kind == .suggestedGratuity { result.warnings.append(.suggestedGratuityNotIncluded) }; if kind == .includedGratuity || kind == .automaticGratuity { result.warnings.append(.receiptMayAlreadyContainGratuity) } }
    }
    private func reconcile(_ result: inout ReceiptDetectionResult) { if result.totalCandidates.count > 1 { result.warnings.append(.multipleTotals) }; if [result.merchantCandidates.first?.confidence, result.subtotalCandidates.first?.confidence, result.totalCandidates.first?.confidence].compactMap({ $0 }).contains(where: { $0 < 0.5 }) { result.warnings.append(.lowConfidenceFields) }; if let subtotal = result.subtotalCandidates.first?.value, let total = result.totalCandidates.first?.value { let tax = result.taxCandidates.first?.value ?? 0; let included = result.chargeCandidates.filter { [.includedGratuity, .automaticGratuity].contains($0.kind) }.compactMap(\.amount).reduce(0, +); let diff = abs(((subtotal + tax + included - total) as NSDecimalNumber).doubleValue); if diff > 0.05 { result.warnings.append(.amountsDoNotAddUp) } } }
    private func lastAmount(in text: String) -> Decimal? {
        let matches = text.matches(#"(?<![\d.,-])(?:USD\s*)?\$?\s*(?:\d{1,3}(?:,\d{3})+|\d+)(?:[.,]\d{1,2})?(?![\d.,%])"#)
        return matches.compactMap { ReceiptAmountParser.parse($0) }.last
    }
    private func percentAmount(in text: String) -> Decimal? { text.matches(#"\d{1,2}(?:\.\d+)?\s*%"#).first.flatMap { Decimal(string: $0.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) } }
    private func looksLikePhoneOrCard(_ text: String) -> Bool { let digits = text.filter(\.isNumber); return digits.count >= 10 && !text.contains(".") }
}

extension String { func matches(_ pattern: String) -> [String] { (try? NSRegularExpression(pattern: pattern)).map { regex in regex.matches(in: self, range: NSRange(startIndex..., in: self)).compactMap { Range($0.range, in: self).map { String(self[$0]) } } } ?? [] } }

struct ReceiptChargeDraft: Identifiable, Hashable { var id: UUID; var label: String; var amountText: String = ""; var percentageText: String = ""; var amount: Decimal?; var percentage: Decimal?; var kind: ReceiptChargeKind; var confidence: Decimal; var userClassification: ReceiptChargeClassification; var isIncludedInReceiptTotal: Bool? = nil; var source: ReceiptChargeSource = .ocr }
struct ReceiptDraftFingerprint: Equatable { var merchantName: String; var receiptDate: Date?; var currencyCode: String; var subtotal: Decimal?; var tax: Decimal?; var total: Decimal?; var charges: [ReceiptChargeDraft]; var notes: String; var imageRevision: UUID? }
struct ReceiptDraft: Identifiable { let id: UUID; var sourceImage: UIImage?; var processed: ProcessedReceiptImage?; var merchantName = ""; var receiptDate: Date?; var currencyCode = "USD"; var subtotalText = ""; var taxText = ""; var totalText = ""; var detectedCharges: [ReceiptChargeDraft] = []; var notes = ""; var recognizedText: String?; var warnings: [ReceiptDetectionWarning] = []; var imageRevision: UUID?
    var fingerprint: ReceiptDraftFingerprint { .init(merchantName: merchantName, receiptDate: receiptDate, currencyCode: currencyCode, subtotal: ReceiptAmountParser.parse(subtotalText), tax: ReceiptAmountParser.parse(taxText), total: ReceiptAmountParser.parse(totalText), charges: detectedCharges, notes: notes, imageRevision: imageRevision) }
    var hasMeaningfulContent: Bool { sourceImage != nil || !merchantName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || receiptDate != nil || !subtotalText.isEmpty || !taxText.isEmpty || !totalText.isEmpty || !notes.isEmpty || !detectedCharges.isEmpty }
}

@MainActor final class ReceiptScannerViewModel: ObservableObject {
    @Published var stage: ReceiptScanStage = .sourceSelection; @Published var presentation: ReceiptScannerPresentation?; @Published var selectedPhoto: PhotosPickerItem?; @Published var draft: ReceiptDraft?; @Published var message: String?; @Published var savedReceiptID: UUID?; @Published var pendingTipInput: TipCalculationInput?; @Published var pendingTipReceiptID: UUID?; @Published var showUnsavedChanges = false; @Published var isSaving = false
    let context: ReceiptScannerContext; let preferences: UserPreferences; private let recognizer: ReceiptTextRecognizing; private let parser: ReceiptFieldParsing; let repository: ReceiptRepository; let calculationRepository: CalculationRepository; private var processingTask: Task<Void, Never>?; private(set) var savedDraftFingerprint: ReceiptDraftFingerprint?
    var hasUnsavedChanges: Bool { guard let draft, draft.hasMeaningfulContent else { return false }; return draft.fingerprint != savedDraftFingerprint }
    static func initialClassification(for kind: ReceiptChargeKind) -> ReceiptChargeClassification {
        switch kind {
        case .includedGratuity, .automaticGratuity, .serviceCharge, .hospitalityCharge,
             .administrativeFee, .suggestedGratuity, .deliveryFee: return .unreviewed
        default: return .otherOrUnclear
        }
    }
    var isReplacementOnly: Bool { if case .replaceImage = context { return true }; return false }
    var isEditingExistingReceipt: Bool { if case .editReceipt = context { return true }; return false }
    var replacementCompleted: Bool { isReplacementOnly && stage == .completed }
    var editCompleted: Bool { isEditingExistingReceipt && stage == .completed }
    init(context: ReceiptScannerContext = .newReceipt, prefilledInput: TipCalculationInput? = nil, preferences: UserPreferences = .defaults, recognizer: ReceiptTextRecognizing = VisionReceiptTextRecognizer(), parser: ReceiptFieldParsing = ReceiptFieldParser(), repository: ReceiptRepository = FileReceiptRepository(), calculationRepository: CalculationRepository = FileCalculationRepository()) { self.context = context; self.preferences = preferences; self.recognizer = recognizer; self.parser = parser; self.repository = repository; self.calculationRepository = calculationRepository; if let input = prefilledInput { var d = ReceiptDraft(id: UUID()); d.currencyCode = input.currencyCode; d.subtotalText = input.subtotal.map(String.init(describing:)) ?? ""; d.taxText = input.tax.map(String.init(describing:)) ?? ""; d.totalText = input.finalTotal.map(String.init(describing:)) ?? ""; draft = d; stage = .confirmation } }
    func loadExistingReceiptIfNeeded() async {
        guard draft == nil else { return }
        let id: UUID
        switch context { case let .replaceImage(receiptID), let .editReceipt(receiptID): id = receiptID; default: return }
        guard let receipt = try? await repository.receipt(id: id) else { return }
        var value = ReceiptDraft(id: receipt.id)
        value.merchantName = receipt.merchantName ?? ""; value.receiptDate = receipt.receiptDate; value.currencyCode = receipt.currencyCode
        value.subtotalText = receipt.subtotal.map(String.init(describing:)) ?? ""; value.taxText = receipt.tax.map(String.init(describing:)) ?? ""; value.totalText = receipt.total.map(String.init(describing:)) ?? ""
        value.detectedCharges = receipt.detectedCharges.map { .init(id: $0.id, label: $0.label, amount: $0.amount, percentage: $0.percentage, kind: $0.kind, confidence: $0.confidence, userClassification: $0.userClassification ?? .unreviewed, isIncludedInReceiptTotal: $0.isIncludedInReceiptTotal, source: $0.source) }
        value.notes = receipt.notes; value.recognizedText = receipt.recognizedText
        draft = value; savedDraftFingerprint = value.fingerprint; stage = .confirmation
    }
    func loadReplacementReceipt() async { await loadExistingReceiptIfNeeded() }
    func chooseCamera() { guard UIImagePickerController.isSourceTypeAvailable(.camera) else { message = ReceiptScannerError.cameraUnavailable.localizedDescription; return }; let status = AVCaptureDevice.authorizationStatus(for: .video); if status == .denied || status == .restricted { message = ReceiptScannerError.cameraDenied.localizedDescription; return }; presentation = .camera }
    func cameraCancelled() { presentation = nil; stage = .sourceSelection }
    func captured(_ image: UIImage) { presentation = nil; process(image) }
    func photoSelectionChanged(_ item: PhotosPickerItem?) { guard let item else { stage = .sourceSelection; return }; stage = .processing; Task { do { guard let data = try await item.loadTransferable(type: Data.self), let image = await Task.detached(priority: .userInitiated, operation: { UIImage(data: data) }).value else { throw ReceiptScannerError.imageLoadFailed }; process(image) } catch { message = ReceiptScannerError.imageLoadFailed.localizedDescription; stage = .sourceSelection } } }
    func process(_ image: UIImage) { processingTask?.cancel(); stage = .processing; processingTask = Task { do { let processed = try await ReceiptImageProcessor.process(image); let recognized = try await recognizer.recognizeText(in: processed.ocrImage); let detection = parser.parse(recognizedText: recognized, locale: .current); makeDraft(image: image, processed: processed, recognized: recognized, detection: detection) } catch is CancellationError { } catch { let processed = try? await ReceiptImageProcessor.process(image); if let processed { var preserved = draft ?? ReceiptDraft(id: UUID()); preserved.sourceImage = image; preserved.processed = processed; preserved.recognizedText = preserved.recognizedText; preserved.imageRevision = UUID(); draft = preserved; stage = .confirmation }; message = "Receipt text could not be read. Your existing receipt details were kept. Review the new image and enter any missing values manually." } } }
    func cancelProcessing() { processingTask?.cancel(); stage = draft == nil ? .sourceSelection : .confirmation }
    func startManualEntry() { var value = ReceiptDraft(id: UUID(), sourceImage: nil, processed: nil, recognizedText: nil, warnings: []); value.currencyCode = preferences.homeCurrencyCode; draft = value; stage = .confirmation }
    private func makeDraft(image: UIImage, processed: ProcessedReceiptImage, recognized: RecognizedReceiptText, detection: ReceiptDetectionResult) {
        // Image OCR is advisory. Preserve edits already made by the user, and only fill
        // fields that are still empty. Notes and reviewed charge classifications are never replaced.
        var d = draft ?? ReceiptDraft(id: UUID())
        d.sourceImage = image; d.processed = processed; d.imageRevision = UUID()
        if d.merchantName.isEmpty { d.merchantName = detection.merchantCandidates.first?.value ?? "" }
        if d.receiptDate == nil { d.receiptDate = detection.dateCandidates.first?.value }
        if d.currencyCode.isEmpty || d.currencyCode == preferences.homeCurrencyCode { d.currencyCode = detection.currencyCandidates.first?.value ?? d.currencyCode }
        if d.subtotalText.isEmpty { d.subtotalText = detection.subtotalCandidates.first.map { "\($0.value)" } ?? "" }
        if d.taxText.isEmpty { d.taxText = detection.taxCandidates.first.map { "\($0.value)" } ?? "" }
        if d.totalText.isEmpty { d.totalText = detection.totalCandidates.first.map { "\($0.value)" } ?? "" }
        if d.detectedCharges.isEmpty { d.detectedCharges = detection.chargeCandidates.map { ReceiptChargeDraft(id: $0.id, label: $0.label, amount: $0.amount, percentage: $0.percentage, kind: $0.kind, confidence: $0.confidence, userClassification: Self.initialClassification(for: $0.kind), source: .ocr) } }
        if d.recognizedText == nil { d.recognizedText = recognized.fullText }
        d.warnings = detection.warnings; draft = d; stage = .confirmation
    }
    var hasUnreviewedFinancialCharges: Bool { guard let draft else { return false }; return !ReceiptFinancialReviewValidator().review(record(from: draft, id: draft.id)).isReadyForFinancialUse }
    private func requireChargeReview() -> Bool {
        guard hasUnreviewedFinancialCharges else { return true }
        message = "Review the detected gratuity and service-charge items before continuing."
        stage = .confirmation
        return false
    }
    func saveReceipt() async -> UUID? {
        guard !isSaving, let draft else { return savedReceiptID }
        if !isReplacementOnly { guard requireChargeReview() else { return nil } }
        isSaving = true; stage = .saving; defer { isSaving = false }
        do {
            if case let .replaceImage(receiptID) = context {
                guard !replacementCompleted else { return receiptID }
                guard let processed = draft.processed else { message = "Choose a replacement receipt image."; stage = .confirmation; return nil }
                // The repository atomically replaces only image files and updates updatedAt;
                // OCR suggestions and the editable draft are deliberately never saved here.
                _ = try await repository.replaceImage(receiptID: receiptID, image: processed.fullImage)
                savedReceiptID = receiptID; savedDraftFingerprint = draft.fingerprint; stage = .completed; return receiptID
            }
            if let editID = existingEditableReceiptID(), let existing = try await repository.receipt(id: editID) {
                savedReceiptID = editID
                var updated = record(from: draft, id: editID)
                updated.imageFilename = existing.imageFilename; updated.thumbnailFilename = existing.thumbnailFilename; updated.createdAt = existing.createdAt; updated.updatedAt = Date()
                if draft.imageRevision != savedDraftFingerprint?.imageRevision, let processed = draft.processed { let imageUpdated = try await repository.replaceImage(receiptID: editID, image: processed.fullImage); updated.imageFilename = imageUpdated.imageFilename; updated.thumbnailFilename = imageUpdated.thumbnailFilename }
                try await repository.saveReceipt(updated); savedDraftFingerprint = draft.fingerprint; stage = .completed; return editID
            }
            if let savedReceiptID, let existing = try await repository.receipt(id: savedReceiptID) {
                var updated = record(from: draft, id: savedReceiptID)
                if draft.imageRevision != savedDraftFingerprint?.imageRevision, let processed = draft.processed {
                    let imageUpdated = try await repository.replaceImage(receiptID: savedReceiptID, image: processed.fullImage)
                    updated.imageFilename = imageUpdated.imageFilename; updated.thumbnailFilename = imageUpdated.thumbnailFilename
                } else { updated.imageFilename = existing.imageFilename; updated.thumbnailFilename = existing.thumbnailFilename }
                updated.createdAt = existing.createdAt; updated.updatedAt = Date()
                try await repository.saveReceipt(updated); savedDraftFingerprint = draft.fingerprint; stage = .completed; return savedReceiptID
            }
            if case let .attachToCalculation(calculationID) = context, try await calculationRepository.fetchCalculations().contains(where: { $0.id == calculationID }) == false { message = "The saved calculation could not be found."; stage = .confirmation; return nil }
            let record = record(from: draft, id: draft.id)
            if let processed = draft.processed { _ = try await repository.create(draft: record, fullImage: processed.fullImage, thumbnail: processed.thumbnail) } else { try await repository.createMetadataOnly(draft: record) }
            if case let .attachToCalculation(calculationID) = context {
                var calculations = try await calculationRepository.fetchCalculations()
                guard let index = calculations.firstIndex(where: { $0.id == calculationID }) else { throw ReceiptScannerError.saveFailed }
                calculations[index].receiptID = record.id; calculations[index].updatedAt = Date()
                do { try await calculationRepository.saveCalculation(calculations[index]) }
                catch { try? await repository.deleteReceipt(id: record.id); throw error }
            }
            savedReceiptID = record.id; savedDraftFingerprint = draft.fingerprint; stage = .completed; return record.id
        } catch { message = ReceiptScannerError.saveFailed.localizedDescription; stage = .confirmation; return nil }
    }
    private func existingEditableReceiptID() -> UUID? { if let savedReceiptID { return savedReceiptID }; if case let .editReceipt(id) = context { return id }; return nil }
    func saveAndCalculate() { Task { if let id = await saveReceipt() { continueToAssistant(receiptID: id) } } }
    func continueToAssistant(receiptID: UUID? = nil) { guard requireChargeReview() else { return }; guard let draft, ReceiptAmountParser.parse(draft.subtotalText).or(ReceiptAmountParser.parse(draft.totalText)) != nil else { message = ReceiptScannerError.invalidCalculationAmount.localizedDescription; return }; pendingTipReceiptID = receiptID; pendingTipInput = record(from: draft, id: receiptID ?? draft.id).tipCalculationInput(defaults: preferences) }
    private func record(from draft: ReceiptDraft, id: UUID) -> ReceiptRecord { let now = Date(); let preliminary = ReceiptRecord(id: id, merchantName: draft.merchantName.nilIfBlank, receiptDate: draft.receiptDate, currencyCode: draft.currencyCode, subtotal: ReceiptAmountParser.parse(draft.subtotalText), tax: ReceiptAmountParser.parse(draft.taxText), total: ReceiptAmountParser.parse(draft.totalText), detectedCharges: draft.detectedCharges.map { DetectedReceiptCharge(id: $0.id, label: $0.label, amount: $0.amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : ReceiptAmountParser.parse($0.amountText), percentage: $0.percentageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : ReceiptAmountParser.parse($0.percentageText), kind: $0.kind, confidence: $0.confidence, userClassification: $0.userClassification, isIncludedInReceiptTotal: $0.isIncludedInReceiptTotal, source: $0.source) }, imageFilename: draft.processed == nil ? nil : "\(id.uuidString).jpg", thumbnailFilename: draft.processed == nil ? nil : "\(id.uuidString)-thumb.jpg", recognizedText: draft.recognizedText, notes: draft.notes, confirmationStatus: .userConfirmed, createdAt: now, updatedAt: now, financialReviewVersion: ReceiptFinancialReviewValidator.currentVersion); let ready = ReceiptFinancialReviewValidator().review(preliminary).isReadyForFinancialUse; var final = preliminary; final.confirmationStatus = ready ? .userConfirmed : .needsReview; final.financialReviewVersion = ready ? ReceiptFinancialReviewValidator.currentVersion : nil; return final }
}

extension Optional where Wrapped == Decimal { func or(_ other: Decimal?) -> Decimal? { self ?? other } }
extension Optional where Wrapped == String { func or(_ other: String) -> String { self ?? other } }
extension String { var nilIfBlank: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self } }

struct ReceiptScannerView: View { @StateObject private var model: ReceiptScannerViewModel; @State private var showFullImage = false; @Environment(\.dismiss) private var dismiss
    init(context: ReceiptScannerContext = .newReceipt, prefilledInput: TipCalculationInput? = nil, preferences: UserPreferences = .defaults, repository: ReceiptRepository = FileReceiptRepository(), calculationRepository: CalculationRepository = FileCalculationRepository()) { _model = StateObject(wrappedValue: ReceiptScannerViewModel(context: context, prefilledInput: prefilledInput, preferences: preferences, repository: repository, calculationRepository: calculationRepository)) }
    var body: some View { AppScreen { content }.navigationTitle(model.isReplacementOnly ? "Replace Receipt Image" : (model.isEditingExistingReceipt ? "Edit Receipt" : "Receipt Scanner")).navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if model.hasUnsavedChanges { model.showUnsavedChanges = true } else { dismiss() } } } }.task { await model.loadExistingReceiptIfNeeded() }.onChange(of: model.replacementCompleted) { if $0 { dismiss() } }.onChange(of: model.editCompleted) { if $0 { dismiss() } }.sheet(item: $model.presentation) { _ in ReceiptCameraView(onCapture: model.captured, onCancel: model.cameraCancelled, onFailure: { model.message = $0.localizedDescription; model.cameraCancelled() }) }.onChange(of: model.selectedPhoto) { model.photoSelectionChanged($0) }.alert("Receipt Scanner", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) { Button("OK", role: .cancel) {} } message: { Text(model.message ?? "") }.alert("Unsaved receipt", isPresented: $model.showUnsavedChanges) { Button(model.isReplacementOnly ? "Replace Receipt Image" : "Save Receipt") { Task { if await model.saveReceipt() != nil { dismiss() } } }; Button("Discard", role: .destructive) { dismiss() }; Button("Keep Editing", role: .cancel) {} } message: { Text("Save before leaving, discard the selected image, or keep editing.") }.navigationDestination(isPresented: Binding(get: { model.pendingTipInput != nil }, set: { presented in if !presented { model.pendingTipInput = nil; model.pendingTipReceiptID = nil } })) { GuidedTipAssistantView(preferences: model.preferences, prefilledInput: model.pendingTipInput, linkedReceiptID: model.pendingTipReceiptID, repository: model.calculationRepository) } }
    @ViewBuilder private var content: some View { switch model.stage { case .sourceSelection: source; case .processing: processing; case .confirmation, .saving, .completed, .failure: confirmation; case .capturing: source } }
    private var source: some View { ScrollView { VStack(spacing: AppSpacing.section) { ScreenTitle(text: "Scan Receipt", subtitle: "Photos and recognized text stay on this device. OCR suggestions must be reviewed before calculating."); ThemedCard { PrimaryButton(title: "Take Photo", systemImage: "camera") { model.chooseCamera() }; PhotosPicker(selection: $model.selectedPhoto, matching: .images) { Label("Choose from Photo Library", systemImage: "photo").appFont(.headline).frame(maxWidth: .infinity, minHeight: 44) }.buttonStyle(AppButtonStylePublic.secondary).accessibilityLabel("Choose receipt from photo library"); SecondaryButton(title: "Enter Values Manually", systemImage: "square.and.pencil") { model.startManualEntry() } }; privacy }.padding(AppSpacing.screen) } }
    private var privacy: some View { ThemedCard { Text("Privacy").appFont(.title2); Text("Text recognition uses Apple Vision on-device. Receipt images and optional recognized text are saved locally only; no receipt content is sent to currency services or analytics.").appFont(.body) } }
    private var processing: some View { VStack(spacing: AppSpacing.section) { if let image = model.draft?.sourceImage { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 260).accessibilityLabel("Selected receipt image") }; LoadingStateView(message: "Reading receipt…").accessibilityLabel("Reading receipt"); SecondaryButton(title: "Cancel Reading") { model.cancelProcessing() } }.padding(AppSpacing.screen) }
    private var confirmation: some View { ReceiptConfirmationView(model: model) }
}

struct ReceiptConfirmationView: View { @ObservedObject var model: ReceiptScannerViewModel; @State private var showImage = false
    var body: some View { ScrollView { VStack(spacing: AppSpacing.section) { ScreenTitle(text: model.isReplacementOnly ? "Replace Receipt Image" : "Review Receipt", subtitle: model.isReplacementOnly ? "Choose a new image. Existing receipt details will be preserved." : "Every value is editable. Suggested gratuity is informational and is not treated as paid."); if model.draft != nil { let draft = Binding<ReceiptDraft>(get: { model.draft! }, set: { model.draft = $0 }); imageSection(draft); if model.isReplacementOnly { replacementContext(draft) } else { details(draft); amounts(draft); charges(draft); warnings(draft) }; actions } else { manualStart } }.padding(AppSpacing.screen) }.hideKeyboardToolbar().fullScreenCover(isPresented: $showImage) { if let image = model.draft?.sourceImage { NavigationStack { AppScreen { Image(uiImage: image).resizable().scaledToFit().padding().accessibilityLabel("Full screen receipt image") }.toolbar { Button("Done") { showImage = false } } } } } }
    private func replacementContext(_ draft: Binding<ReceiptDraft>) -> some View { ThemedCard { Text("Saved receipt").appFont(.title2); ResultSummaryRow(label: "Merchant", value: draft.wrappedValue.merchantName.nilIfBlank ?? "Receipt"); if let total = ReceiptAmountParser.parse(draft.wrappedValue.totalText) { ResultSummaryRow(label: "Total", value: "\(draft.wrappedValue.currencyCode) \(total)") }; Text("These details are read-only during image replacement.").appFont(.footnote).foregroundStyle(AppTheme.secondaryText) } }
    private var manualStart: some View { ThemedCard { Text("Manual receipt entry").appFont(.title2); Text("Enter merchant, date, currency, amounts, charges, and notes. A photo is optional.").appFont(.body); SecondaryButton(title: "Start Manual Entry", systemImage: "square.and.pencil") { model.startManualEntry() } } }
    private func imageSection(_ draft: Binding<ReceiptDraft>) -> some View { ThemedCard { if let image = draft.wrappedValue.sourceImage { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 260).clipShape(RoundedRectangle(cornerRadius: 14)).accessibilityLabel("Receipt image preview"); HStack { Button("View") { showImage = true }; Button("Retake") { model.chooseCamera() }; PhotosPicker(selection: $model.selectedPhoto, matching: .images) { Text("Replace") } }.appFont(.body).foregroundStyle(AppTheme.accent) } else { Label("Manual entry", systemImage: "doc.text").appFont(.headline); Text("No receipt image is attached.").appFont(.body); HStack { Button("Add Receipt Image") { model.chooseCamera() }; PhotosPicker(selection: $model.selectedPhoto, matching: .images) { Text("Choose Photo") } }.appFont(.body).foregroundStyle(AppTheme.accent) } } }
    private func details(_ draft: Binding<ReceiptDraft>) -> some View { ThemedCard { Text("Merchant and date").appFont(.title2); TextField("Merchant name", text: draft.merchantName).textFieldStyle(AppTextFieldStyle()).accessibilityLabel("Merchant name"); DatePicker("Receipt date", selection: Binding(get: { draft.wrappedValue.receiptDate ?? Date() }, set: { draft.wrappedValue.receiptDate = $0 }), displayedComponents: .date); Button("Clear date") { draft.wrappedValue.receiptDate = nil }; TextField("Currency code", text: draft.currencyCode).textFieldStyle(AppTextFieldStyle()).textInputAutocapitalization(.characters) } }
    private func amounts(_ draft: Binding<ReceiptDraft>) -> some View { ThemedCard { Text("Amounts").appFont(.title2); TextField("Subtotal", text: draft.subtotalText).keyboardType(.decimalPad).textFieldStyle(AppTextFieldStyle()); TextField("Tax", text: draft.taxText).keyboardType(.decimalPad).textFieldStyle(AppTextFieldStyle()); TextField("Total", text: draft.totalText).keyboardType(.decimalPad).textFieldStyle(AppTextFieldStyle()); Text("Low-confidence or missing values can be corrected before calculating.").appFont(.body).foregroundStyle(AppTheme.secondaryText) } }
    private func charges(_ draft: Binding<ReceiptDraft>) -> some View { ThemedCard { Text("Charges and gratuity").appFont(.title2); if draft.detectedCharges.isEmpty { Text("No gratuity or service-charge wording was detected. Add any missed charge before calculating.").appFont(.body) }; ForEach(draft.detectedCharges) { $charge in VStack(alignment: .leading, spacing: AppSpacing.small) { TextField("Charge label", text: $charge.label).textFieldStyle(AppTextFieldStyle()); Text(charge.kind.explanation).appFont(.body); TextField("Amount", text: $charge.amountText).keyboardType(.decimalPad).textFieldStyle(AppTextFieldStyle()).onAppear { if charge.amountText.isEmpty, let amount = charge.amount { charge.amountText = "\(amount)" } }; TextField("Percentage", text: $charge.percentageText).keyboardType(.decimalPad).textFieldStyle(AppTextFieldStyle()).onAppear { if charge.percentageText.isEmpty, let pct = charge.percentage { charge.percentageText = "\(pct)" } }; Picker("Classification", selection: $charge.userClassification) { ForEach(ReceiptChargeClassification.allCases) { Text($0.title).tag($0) } }.pickerStyle(.menu).accessibilityLabel("Classification for \(charge.label)"); Picker("Included in receipt total", selection: Binding(get: { charge.isIncludedInReceiptTotal.map { $0 ? "yes" : "no" } ?? "unknown" }, set: { charge.isIncludedInReceiptTotal = $0 == "unknown" ? nil : ($0 == "yes") })) { Text("Confirm included status").tag("unknown"); Text("Included in total").tag("yes"); Text("Not included in total").tag("no") }.pickerStyle(.menu); Button("Remove Charge", role: .destructive) { model.draft?.detectedCharges.removeAll { $0.id == charge.id } }; if DetectionConfidence(charge.confidence) != .high { Label(DetectionConfidence(charge.confidence).reviewText, systemImage: "exclamationmark.triangle").appFont(.body).foregroundStyle(AppTheme.highlight) } }.padding(.vertical, 6) }; Button("Add Charge") { model.draft?.detectedCharges.append(ReceiptChargeDraft(id: UUID(), label: "", amountText: "", percentageText: "", amount: nil, percentage: nil, kind: .unknownCharge, confidence: 1, userClassification: .unreviewed, source: .manual)) }; TextField("Notes", text: draft.notes, axis: .vertical).textFieldStyle(AppTextFieldStyle()) } }
    private func warnings(_ draft: Binding<ReceiptDraft>) -> some View { Group { if !draft.wrappedValue.warnings.isEmpty { ThemedCard { Text("Review notes").appFont(.title2); ForEach(draft.wrappedValue.warnings) { warning in Label(warning.message, systemImage: "exclamationmark.triangle").appFont(.body).foregroundStyle(AppTheme.highlight) } } } } }
    @ViewBuilder private var actions: some View {
        ThemedCard {
            if model.isReplacementOnly {
                Text("Only the image and thumbnail will change. Saved merchant, amounts, charges, notes, recognized text, dates, and links remain unchanged.").appFont(.body)
                PrimaryButton(title: model.isSaving ? "Replacing…" : "Replace Receipt Image", systemImage: "photo.badge.arrow.down", isDisabled: model.isSaving || model.draft?.processed == nil || model.replacementCompleted) { Task { _ = await model.saveReceipt() } }
            } else if model.isEditingExistingReceipt {
                PrimaryButton(title: model.isSaving ? "Updating…" : "Update Receipt", systemImage: "checkmark", isDisabled: model.isSaving || model.hasUnreviewedFinancialCharges) { Task { _ = await model.saveReceipt() } }
                SecondaryButton(title: "Rescan", systemImage: "camera") { model.chooseCamera() }
            } else {
                PrimaryButton(title: "Continue to Tip Assistant", systemImage: "sparkles") { model.continueToAssistant() }
                PrimaryButton(title: model.isSaving ? "Saving…" : "Save Receipt", systemImage: "checkmark", isDisabled: model.isSaving || model.hasUnreviewedFinancialCharges) { Task { _ = await model.saveReceipt() } }
                SecondaryButton(title: "Save and Calculate", systemImage: "arrow.right", isDisabled: model.isSaving || model.hasUnreviewedFinancialCharges) { model.saveAndCalculate() }
                SecondaryButton(title: "Enter Values Manually", systemImage: "square.and.pencil") { model.message = "Edit any field above. OCR is optional." }
                SecondaryButton(title: "Rescan", systemImage: "camera") { model.chooseCamera() }
            }
        }
    }
}

struct ReceiptCameraView: UIViewControllerRepresentable { let onCapture: (UIImage) -> Void; let onCancel: () -> Void; let onFailure: (Error) -> Void
    func makeUIViewController(context: Context) -> UIImagePickerController { let picker = UIImagePickerController(); guard UIImagePickerController.isSourceTypeAvailable(.camera) else { DispatchQueue.main.async { onFailure(ReceiptScannerError.cameraUnavailable) }; return picker }; picker.sourceType = .camera; picker.delegate = context.coordinator; return picker }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture, onCancel: onCancel, onFailure: onFailure) }
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate { let onCapture: (UIImage) -> Void; let onCancel: () -> Void; let onFailure: (Error) -> Void; init(onCapture: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void, onFailure: @escaping (Error) -> Void) { self.onCapture = onCapture; self.onCancel = onCancel; self.onFailure = onFailure }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) { guard let image = info[.originalImage] as? UIImage else { picker.dismiss(animated: true) { self.onFailure(ReceiptScannerError.imageLoadFailed) }; return }; picker.dismiss(animated: true) { self.onCapture(image) } }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { picker.dismiss(animated: true) { self.onCancel() } }
    }
}

extension ReceiptChargeKind { var explanation: String { switch self { case .includedGratuity, .automaticGratuity: return "May already be included in the bill."; case .serviceCharge, .hospitalityCharge, .administrativeFee: return "May not be the same as a voluntary tip; confirm before counting it."; case .deliveryFee: return "Do not assume this is a driver tip."; case .suggestedGratuity: return "Informational suggestion only, not already paid."; default: return "Review this charge." } } }
