import Foundation
import UIKit

protocol CalculationRepository {
    func fetchCalculations() async throws -> [SavedCalculationRecord]
    func saveCalculation(_ record: SavedCalculationRecord) async throws
    func deleteCalculation(id: UUID) async throws
}

protocol ReceiptRepository: Sendable {
    func fetchReceipts() async throws -> [ReceiptRecord]
    func receipt(id: UUID) async throws -> ReceiptRecord?
    func create(draft: ReceiptRecord, fullImage: UIImage, thumbnail: UIImage) async throws -> ReceiptRecord
    func createMetadataOnly(draft: ReceiptRecord) async throws
    func saveReceipt(_ receipt: ReceiptRecord) async throws
    func replaceImage(receiptID: UUID, image: UIImage) async throws -> ReceiptRecord
    func rename(receiptID: UUID, newName: String) async throws -> ReceiptRecord
    func deleteReceipt(id: UUID) async throws
    func loadImage(filename: String) async throws -> UIImage
    func loadThumbnail(filename: String) async throws -> UIImage
}

protocol UserPreferencesRepository {
    func loadPreferences() async throws -> UserPreferences
    func savePreferences(_ preferences: UserPreferences) async throws
}

protocol CurrencyRateRepository {
    func cachedRate(from sourceCurrencyCode: String, to destinationCurrencyCode: String) async throws -> CurrencyConversionSnapshot?
    func saveRateSnapshot(_ snapshot: CurrencyConversionSnapshot) async throws
}

protocol GuideBookmarkRepository {
    func bookmarkedGuideSectionIDs() async throws -> Set<String>
    func setBookmarked(_ isBookmarked: Bool, guideSectionID: String) async throws
}

enum V2PersistenceError: LocalizedError {
    case readFailed
    case writeFailed
    case migrationFailed(String)

    var errorDescription: String? {
        switch self {
        case .readFailed: return "Saved app data could not be read."
        case .writeFailed: return "Saved app data could not be written."
        case .migrationFailed(let message): return "Some V1 data could not be migrated: \(message)"
        }
    }
}

struct StoredDataEnvelope<Record: Codable>: Codable {
    var version: Int
    var records: [Record]
}

struct V2MigrationReport: Codable, Hashable {
    var fromVersion: Int
    var toVersion: Int
    var migratedNotesCount: Int
    var migratedReceiptsCount: Int
    var partialFailures: [String]
    var completedAt: Date

    var succeeded: Bool { partialFailures.isEmpty }
}

actor CodableFileStore<Record: Codable & Identifiable> where Record.ID: Hashable {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL) {
        self.fileURL = fileURL
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load(version: Int) throws -> [Record] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do { return try decoder.decode(StoredDataEnvelope<Record>.self, from: Data(contentsOf: fileURL)).records }
        catch { throw V2PersistenceError.readFailed }
    }

    func save(_ records: [Record], version: Int) throws {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try encoder.encode(StoredDataEnvelope(version: version, records: records))
            try data.write(to: fileURL, options: [.atomic])
        } catch { throw V2PersistenceError.writeFailed }
    }
}

actor FileUserPreferencesRepository: UserPreferencesRepository {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(rootURL: URL? = nil) {
        let root = rootURL ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = root.appendingPathComponent("V2/Preferences/user-preferences.json")
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadPreferences() async throws -> UserPreferences {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .defaults }
        do { return try decoder.decode(UserPreferences.self, from: Data(contentsOf: fileURL)).validated }
        catch { return .defaults }
    }

    func savePreferences(_ preferences: UserPreferences) async throws {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(preferences).write(to: fileURL, options: [.atomic])
        } catch { throw V2PersistenceError.writeFailed }
    }
}

actor V2MigrationCoordinator {
    static let currentVersion = 2
    private let rootURL: URL
    private let fileManager: FileManager

    init(rootURL: URL? = nil, fileManager: FileManager = .default) {
        self.rootURL = rootURL ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.fileManager = fileManager
    }

    func migrateIfNeeded() async -> V2MigrationReport {
        let markerURL = rootURL.appendingPathComponent("V2/migration-v2-complete.json")
        if let data = try? Data(contentsOf: markerURL), let report = try? JSONDecoder().decode(V2MigrationReport.self, from: data) { return report }

        var failures: [String] = []
        var migratedReceipts = 0
        var migratedNotes = 0

        do { try backupLegacyFileIfPresent(named: "receipts.json"); migratedReceipts = try await migrateLegacyReceiptsMetadata() }
        catch { failures.append("Receipts: \(error.localizedDescription)") }

        do { try backupLegacyFileIfPresent(named: "notes.json"); migratedNotes = try await migrateLegacyNotes() }
        catch { failures.append("Notes: \(error.localizedDescription)") }

        let report = V2MigrationReport(fromVersion: 1, toVersion: Self.currentVersion, migratedNotesCount: migratedNotes, migratedReceiptsCount: migratedReceipts, partialFailures: failures, completedAt: Date())
        if report.succeeded {
            do {
                try fileManager.createDirectory(at: markerURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
                try encoder.encode(report).write(to: markerURL, options: [.atomic])
            } catch { }
        }
        return report
    }

    private func backupLegacyFileIfPresent(named fileName: String) throws {
        let legacyURL = rootURL.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: legacyURL.path) else { return }
        let backupDir = rootURL.appendingPathComponent("V2/Backups", isDirectory: true)
        try fileManager.createDirectory(at: backupDir, withIntermediateDirectories: true)
        let backupURL = backupDir.appendingPathComponent("\(fileName).v1-backup")
        if !fileManager.fileExists(atPath: backupURL.path) { try fileManager.copyItem(at: legacyURL, to: backupURL) }
    }

    private func migrateLegacyReceiptsMetadata() async throws -> Int {
        let legacyURL = rootURL.appendingPathComponent("Receipts/receipts.json")
        guard fileManager.fileExists(atPath: legacyURL.path) else { return 0 }
        struct LegacyReceipt: Codable { var id: UUID; var name: String; var imageFilename: String; var thumbnailFilename: String?; var createdAt: Date; var updatedAt: Date }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(StoredDataEnvelope<LegacyReceipt>.self, from: Data(contentsOf: legacyURL))
        let records = envelope.records.map { legacy in
            ReceiptRecord(id: legacy.id, merchantName: legacy.name, receiptDate: nil, subtotal: nil, tax: nil, total: nil, detectedCharges: [], imageFilename: legacy.imageFilename, thumbnailFilename: legacy.thumbnailFilename, notes: "", createdAt: legacy.createdAt, updatedAt: legacy.updatedAt)
        }
        let target = CodableFileStore<ReceiptRecord>(fileURL: rootURL.appendingPathComponent("V2/Receipts/receipts.json"))
        try await target.save(records, version: Self.currentVersion)
        return records.count
    }

    private func migrateLegacyNotes() async throws -> Int {
        let legacyURL = rootURL.appendingPathComponent("notes.json")
        guard fileManager.fileExists(atPath: legacyURL.path) else { return 0 }
        return 0
    }
}


actor FileReceiptRepository: ReceiptRepository {
    private let root: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var receiptsDir: URL { root.appendingPathComponent("V2/Receipts", isDirectory: true) }
    private var imagesDir: URL { receiptsDir.appendingPathComponent("Images", isDirectory: true) }
    private var thumbsDir: URL { receiptsDir.appendingPathComponent("Thumbnails", isDirectory: true) }
    private var backupsDir: URL { receiptsDir.appendingPathComponent("Backups", isDirectory: true) }
    private var temporaryDir: URL { receiptsDir.appendingPathComponent("Temporary", isDirectory: true) }
    private var metadataURL: URL { receiptsDir.appendingPathComponent("receipts.json") }

    init(rootURL: URL? = nil, fileManager: FileManager = .default) {
        root = rootURL ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.fileManager = fileManager
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func fetchReceipts() async throws -> [ReceiptRecord] { try loadRecords() }
    func receipt(id: UUID) async throws -> ReceiptRecord? { try loadRecords().first { $0.id == id } }
    func create(draft: ReceiptRecord, fullImage: UIImage, thumbnail: UIImage) async throws -> ReceiptRecord {
        try ensureDirectories()
        let imageName = draft.imageFilename ?? "\(draft.id.uuidString).jpg"
        let thumbName = draft.thumbnailFilename ?? "\(draft.id.uuidString)-thumb.jpg"
        guard let fullData = fullImage.jpegData(compressionQuality: 0.82), let thumbData = thumbnail.jpegData(compressionQuality: 0.78) else { throw ReceiptStorageError.conversion }
        let imageURL = try validatedURL(filename: imageName, in: imagesDir)
        let thumbURL = try validatedURL(filename: thumbName, in: thumbsDir)
        do { try fullData.write(to: imageURL, options: [.atomic]); try thumbData.write(to: thumbURL, options: [.atomic]) } catch { throw ReceiptStorageError.imageWrite }
        var record = draft; record.imageFilename = imageName; record.thumbnailFilename = thumbName
        do { try persistReceipt(record); return record } catch { try? fileManager.removeItem(at: imageURL); try? fileManager.removeItem(at: thumbURL); throw error }
    }
    func createMetadataOnly(draft: ReceiptRecord) async throws { var record = draft; record.imageFilename = nil; record.thumbnailFilename = nil; try ensureDirectories(); try persistReceipt(record) }
    func saveReceipt(_ receipt: ReceiptRecord) async throws { try persistReceipt(receipt) }
    private func persistReceipt(_ receipt: ReceiptRecord) throws { var records = try loadRecords(); records.removeAll { $0.id == receipt.id }; records.insert(receipt, at: 0); try writeRecordsAtomically(records) }
    func deleteReceipt(id: UUID) async throws {
        var records = try loadRecords()
        guard let receipt = records.first(where: { $0.id == id }) else { return }
        let staged = try stageFilesForDeletion(receipt)
        records.removeAll { $0.id == id }
        do { try writeRecordsAtomically(records); try staged.forEach { if fileManager.fileExists(atPath: $0.temporaryURL.path) { try fileManager.removeItem(at: $0.temporaryURL) } } }
        catch { try restore(stagedFiles: staged); throw error }
    }

    func replaceImage(receiptID: UUID, image: UIImage) async throws -> ReceiptRecord {
        guard var record = try loadRecords().first(where: { $0.id == receiptID }) else { throw ReceiptStorageError.metadataRead }
        try ensureDirectories()
        let processed = image.normalizedForReceipt()
        let imageName = record.imageFilename ?? "\(receiptID.uuidString).jpg"
        let thumbName = record.thumbnailFilename ?? "\(receiptID.uuidString)-thumb.jpg"
        guard let fullData = processed.resizedForReceipt(maxDimension: 1800).jpegData(compressionQuality: 0.82), let thumbData = processed.resizedForReceipt(maxDimension: 420).jpegData(compressionQuality: 0.78) else { throw ReceiptStorageError.conversion }
        let imageURL = try validatedURL(filename: imageName, in: imagesDir)
        let thumbURL = try validatedURL(filename: thumbName, in: thumbsDir)
        let stagedImageURL = temporaryDir.appendingPathComponent("replace-\(UUID().uuidString)-\(imageName)")
        let stagedThumbURL = temporaryDir.appendingPathComponent("replace-\(UUID().uuidString)-\(thumbName)")
        let oldImageBackupURL = temporaryDir.appendingPathComponent("old-\(UUID().uuidString)-\(imageName)")
        let oldThumbBackupURL = temporaryDir.appendingPathComponent("old-\(UUID().uuidString)-\(thumbName)")
        var movedOldImage = false
        var movedOldThumb = false
        do {
            try fullData.write(to: stagedImageURL, options: [.atomic])
            try thumbData.write(to: stagedThumbURL, options: [.atomic])
            guard UIImage(contentsOfFile: stagedImageURL.path) != nil, UIImage(contentsOfFile: stagedThumbURL.path) != nil else { throw ReceiptStorageError.imageWrite }
            if fileManager.fileExists(atPath: imageURL.path) { try fileManager.moveItem(at: imageURL, to: oldImageBackupURL); movedOldImage = true }
            if fileManager.fileExists(atPath: thumbURL.path) { try fileManager.moveItem(at: thumbURL, to: oldThumbBackupURL); movedOldThumb = true }
            try fileManager.moveItem(at: stagedImageURL, to: imageURL)
            try fileManager.moveItem(at: stagedThumbURL, to: thumbURL)
        } catch {
            try? fileManager.removeItem(at: stagedImageURL)
            try? fileManager.removeItem(at: stagedThumbURL)
            try? fileManager.removeItem(at: imageURL)
            try? fileManager.removeItem(at: thumbURL)
            if movedOldImage { try? fileManager.moveItem(at: oldImageBackupURL, to: imageURL) }
            if movedOldThumb { try? fileManager.moveItem(at: oldThumbBackupURL, to: thumbURL) }
            throw ReceiptStorageError.imageWrite
        }
        record.imageFilename = imageName; record.thumbnailFilename = thumbName; record.updatedAt = Date()
        do {
            try persistReceipt(record)
            try? fileManager.removeItem(at: oldImageBackupURL)
            try? fileManager.removeItem(at: oldThumbBackupURL)
        } catch {
            try? fileManager.removeItem(at: imageURL)
            try? fileManager.removeItem(at: thumbURL)
            if movedOldImage { try? fileManager.moveItem(at: oldImageBackupURL, to: imageURL) }
            if movedOldThumb { try? fileManager.moveItem(at: oldThumbBackupURL, to: thumbURL) }
            throw error
        }
        return record
    }
    func rename(receiptID: UUID, newName: String) async throws -> ReceiptRecord {
        var records = try loadRecords(); guard let index = records.firstIndex(where: { $0.id == receiptID }) else { throw ReceiptStorageError.metadataRead }
        records[index].merchantName = newName; records[index].updatedAt = Date(); try writeRecordsAtomically(records); return records[index]
    }
    func loadImage(filename: String) async throws -> UIImage { guard let image = UIImage(contentsOfFile: (try validatedURL(filename: filename, in: imagesDir)).path) else { throw ReceiptStorageError.imageLoad }; return image }
    func loadThumbnail(filename: String) async throws -> UIImage { guard let image = UIImage(contentsOfFile: (try validatedURL(filename: filename, in: thumbsDir)).path) else { throw ReceiptStorageError.imageLoad }; return image }

    func imageURL(for record: ReceiptRecord, thumbnail: Bool = false) throws -> URL {
        if thumbnail, let thumb = record.thumbnailFilename { return try validatedURL(filename: thumb, in: thumbsDir) }
        guard let image = record.imageFilename else { throw ReceiptStorageError.invalidImageFilename }
        return try validatedURL(filename: image, in: imagesDir)
    }

    private func ensureDirectories() throws { for dir in [receiptsDir, imagesDir, thumbsDir, backupsDir, temporaryDir] { try fileManager.createDirectory(at: dir, withIntermediateDirectories: true) } }
    private func loadRecords() throws -> [ReceiptRecord] {
        try ensureDirectories()
        guard fileManager.fileExists(atPath: metadataURL.path) else { return [] }
        do { let envelope = try decoder.decode(StoredDataEnvelope<ReceiptRecord>.self, from: Data(contentsOf: metadataURL)); guard envelope.version == V2MigrationCoordinator.currentVersion else { throw ReceiptStorageError.metadataRead }; return envelope.records.sorted { $0.updatedAt > $1.updatedAt } }
        catch { try backupCorruptMetadataIfNeeded(); throw ReceiptStorageError.metadataRead }
    }
    private func backupCorruptMetadataIfNeeded() throws {
        try ensureDirectories()
        let attrs = try? fileManager.attributesOfItem(atPath: metadataURL.path)
        let stamp = Int((attrs?[.modificationDate] as? Date ?? Date()).timeIntervalSince1970)
        let backupURL = backupsDir.appendingPathComponent("receipts-corrupt-").appendingPathExtension("\(stamp).json")
        if !fileManager.fileExists(atPath: backupURL.path) { try fileManager.copyItem(at: metadataURL, to: backupURL) }
    }
    private func writeRecordsAtomically(_ records: [ReceiptRecord]) throws {
        try ensureDirectories()
        let envelope = StoredDataEnvelope(version: V2MigrationCoordinator.currentVersion, records: records)
        let tempURL = temporaryDir.appendingPathComponent("receipts-\(UUID().uuidString).json")
        do {
            let data = try encoder.encode(envelope)
            try data.write(to: tempURL, options: [.atomic])
            _ = try decoder.decode(StoredDataEnvelope<ReceiptRecord>.self, from: Data(contentsOf: tempURL))
            if fileManager.fileExists(atPath: metadataURL.path) {
                let previous = backupsDir.appendingPathComponent("receipts-previous-\(Int(Date().timeIntervalSince1970)).json")
                try? fileManager.copyItem(at: metadataURL, to: previous)
            }
            if fileManager.fileExists(atPath: metadataURL.path) { _ = try fileManager.replaceItemAt(metadataURL, withItemAt: tempURL, backupItemName: nil, options: [.usingNewMetadataOnly]) } else { try fileManager.moveItem(at: tempURL, to: metadataURL) }
        } catch { try? fileManager.removeItem(at: tempURL); throw ReceiptStorageError.metadataWrite }
    }
    private struct StagedReceiptFile: Sendable { let originalURL: URL; let temporaryURL: URL }
    private func stageFilesForDeletion(_ record: ReceiptRecord) throws -> [StagedReceiptFile] {
        try ensureDirectories()
        var staged: [StagedReceiptFile] = []
        do {
            for (filename, dir) in [(record.imageFilename, imagesDir), (record.thumbnailFilename, thumbsDir)] {
                guard let filename else { continue }
                let source = try validatedURL(filename: filename, in: dir)
                guard fileManager.fileExists(atPath: source.path) else { continue }
                let destination = temporaryDir.appendingPathComponent("delete-\(UUID().uuidString)-\(source.lastPathComponent)")
                try fileManager.moveItem(at: source, to: destination)
                staged.append(StagedReceiptFile(originalURL: source, temporaryURL: destination))
            }
            return staged
        } catch { try? restore(stagedFiles: staged); throw error }
    }
    private func restore(stagedFiles: [StagedReceiptFile]) throws {
        var failures: [Error] = []
        for staged in stagedFiles where fileManager.fileExists(atPath: staged.temporaryURL.path) {
            do { try fileManager.moveItem(at: staged.temporaryURL, to: staged.originalURL) } catch { failures.append(error) }
        }
        if !failures.isEmpty { throw ReceiptStorageError.delete }
    }
    private func validatedURL(filename: String, in directory: URL) throws -> URL {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed == (trimmed as NSString).lastPathComponent, !trimmed.contains(".."), !trimmed.hasPrefix("/") else { throw ReceiptStorageError.invalidImageFilename }
        let dir = directory.standardizedFileURL.resolvingSymlinksInPath()
        let url = dir.appendingPathComponent(trimmed, isDirectory: false).standardizedFileURL.resolvingSymlinksInPath()
        guard url.path.hasPrefix(dir.path + "/"), url.path != dir.path, url.deletingLastPathComponent().path == dir.path else { throw ReceiptStorageError.invalidImageFilename }
        return url
    }
}

actor FileCalculationRepository: CalculationRepository {
    private let store: CodableFileStore<SavedCalculationRecord>
    init(rootURL: URL? = nil) {
        let root = rootURL ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        store = CodableFileStore(fileURL: root.appendingPathComponent("V2/Calculations/calculations.json"))
    }
    func fetchCalculations() async throws -> [SavedCalculationRecord] { try await store.load(version: V2MigrationCoordinator.currentVersion) }
    func saveCalculation(_ record: SavedCalculationRecord) async throws { var records = try await fetchCalculations(); records.removeAll { $0.id == record.id }; records.insert(record, at: 0); try await store.save(records, version: V2MigrationCoordinator.currentVersion) }
    func deleteCalculation(id: UUID) async throws { var records = try await fetchCalculations(); records.removeAll { $0.id == id }; try await store.save(records, version: V2MigrationCoordinator.currentVersion) }
}

// MARK: - Repositories and Services

actor FileCurrencyRateRepository: CurrencyRateRepository {
    private let store: CodableFileStore<StoredExchangeRate>
    init(rootURL: URL? = nil) { let root = rootURL ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]; store = CodableFileStore(fileURL: root.appendingPathComponent("V2/Currency/rates.json")) }
    func cachedRate(from sourceCurrencyCode: String, to destinationCurrencyCode: String) async throws -> CurrencyConversionSnapshot? {
        let source = sourceCurrencyCode.uppercased(), destination = destinationCurrencyCode.uppercased()
        guard let record = try await store.load(version: V2MigrationCoordinator.currentVersion).first(where: { $0.sourceCode == source && $0.destinationCode == destination }) else { return nil }
        return CurrencyConversionSnapshot(sourceCurrencyCode: source, destinationCurrencyCode: destination, billAmount: 0, tipAmount: 0, totalAmount: 0, convertedBillAmount: 0, convertedTipAmount: 0, convertedTotalAmount: 0, rate: record.rate, rateDate: record.rateDate, fetchedAt: record.fetchedAt, usedCachedRate: true)
    }
    func saveRateSnapshot(_ snapshot: CurrencyConversionSnapshot) async throws {
        let source = snapshot.sourceCurrencyCode.uppercased(), destination = snapshot.destinationCurrencyCode.uppercased()
        guard FrankfurterSupportedCurrencies.codes.contains(source), FrankfurterSupportedCurrencies.codes.contains(destination), snapshot.rate > 0 else { return }
        var records = try await store.load(version: V2MigrationCoordinator.currentVersion).filter { !($0.sourceCode == source && $0.destinationCode == destination) }
        records.insert(StoredExchangeRate(sourceCode: source, destinationCode: destination, rate: snapshot.rate, rateDate: snapshot.rateDate, fetchedAt: snapshot.fetchedAt), at: 0)
        if records.count > 50 { records = Array(records.prefix(50)) }
        try await store.save(records, version: V2MigrationCoordinator.currentVersion)
    }
}

struct HistoryCombiner {
    func combine(calculations: [SavedCalculationRecord], receipts: [ReceiptRecord]) -> [HistoryEntry] {
        var entries: [HistoryEntry] = []
        let receiptsByID = Dictionary(uniqueKeysWithValues: receipts.map { ($0.id, $0) })
        for receipt in receipts {
            let linked = calculations.filter { $0.receiptID == receipt.id }
            let types = ["Receipt"] + linked.compactMap { $0.tipResult != nil ? "Tip" : ($0.splitResult != nil ? "Split" : nil) }
            entries.append(HistoryEntry(id: receipt.id, recordType: .receipt, linkedRecordID: receipt.id, title: receipt.displayName, subtitle: types.joined(separator: " + "), serviceID: nil, merchantName: receipt.merchantName, currencyCode: receipt.currencyCode, totalAmount: receipt.total, createdAt: receipt.createdAt, updatedAt: receipt.updatedAt, participantNames: [], notes: receipt.notes, receiptThumbnailFilename: receipt.thumbnailFilename, paidSummary: nil))
        }
        for record in calculations {
            if record.recordType == .receiptOnly { continue }
            if let split = record.splitResult {
                let paid = split.participantResults.filter(\.isPaid).count
                let total = split.participantResults.count
                let receipt = record.receiptID.flatMap { receiptsByID[$0] }
                entries.append(HistoryEntry(id: record.id, recordType: .split, linkedRecordID: record.id, title: record.merchantName ?? split.session.name, subtitle: receipt == nil ? "Bill Split" : "Receipt + Split", serviceID: nil, merchantName: record.merchantName ?? receipt?.merchantName, currencyCode: split.session.currencyCode, totalAmount: split.roundedCollectedTotal, createdAt: record.createdAt, updatedAt: record.updatedAt, participantNames: split.participantResults.map(\.participantName), notes: record.notes, receiptThumbnailFilename: receipt?.thumbnailFilename, paidSummary: paid == total ? "All paid" : "\(paid) of \(total) paid"))
            } else if let tip = record.tipResult {
                let receipt = record.receiptID.flatMap { receiptsByID[$0] }
                entries.append(HistoryEntry(id: record.id, recordType: .tipCalculation, linkedRecordID: record.id, title: record.merchantName ?? tip.service.name, subtitle: receipt == nil ? "Tip Calculation" : "Receipt + Tip", serviceID: tip.service.id, merchantName: record.merchantName ?? receipt?.merchantName, currencyCode: tip.input.currencyCode, totalAmount: tip.finalTotal, createdAt: record.createdAt, updatedAt: record.updatedAt, participantNames: [], notes: record.notes, receiptThumbnailFilename: receipt?.thumbnailFilename, paidSummary: nil))
            }
        }
        var seen = Set<String>()
        return entries.filter { seen.insert("\($0.recordType.rawValue)-\($0.linkedRecordID.uuidString)").inserted }
    }
}

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var state = HistoryViewState(entries: [])
    @Published var isLoading = false
    @Published var errorMessage: String?
    private let calculationRepository: CalculationRepository
    private let receiptRepository: ReceiptRepository
    private let combiner = HistoryCombiner()
    init(calculationRepository: CalculationRepository = FileCalculationRepository(), receiptRepository: ReceiptRepository = FileReceiptRepository()) { self.calculationRepository = calculationRepository; self.receiptRepository = receiptRepository }
    func load() async { isLoading = true; defer { isLoading = false }; do { state.entries = combiner.combine(calculations: try await calculationRepository.fetchCalculations(), receipts: try await receiptRepository.fetchReceipts()); errorMessage = nil } catch { errorMessage = "History could not be loaded." } }
    func delete(_ entry: HistoryEntry) async { do { switch entry.recordType { case .receipt: try await receiptRepository.deleteReceipt(id: entry.linkedRecordID); case .tipCalculation, .split: try await calculationRepository.deleteCalculation(id: entry.linkedRecordID) }; await load() } catch { errorMessage = "That history item could not be deleted." } }
    func deleteAllActivity() async { do { for entry in state.entries { switch entry.recordType { case .receipt: try await receiptRepository.deleteReceipt(id: entry.linkedRecordID); case .tipCalculation, .split: try await calculationRepository.deleteCalculation(id: entry.linkedRecordID) } }; await load() } catch { errorMessage = "Some saved activity could not be deleted." } }
}

struct ShareSummaryBuilder {
    func tipSummary(_ result: TipCalculationResult) -> String { ["Tips for Tips", "", "\(result.service.name): \(formatMoney(result.baseBillAmount, code: result.input.currencyCode))", "Tax: \(formatMoney(result.input.tax ?? 0, code: result.input.currencyCode))", "Tip: \(result.recommendedPercentage.map { "\($0)% — " } ?? "")\(formatMoney(result.suggestedAdditionalTip, code: result.input.currencyCode))", "Final total: \(formatMoney(result.finalTotal, code: result.input.currencyCode))", "Split between \(result.input.peopleCount) people: \(formatMoney(result.amountPerPerson, code: result.input.currencyCode)) each", "", result.explanation].joined(separator: "\n") }
    func splitSummary(_ result: SplitCalculationResult) -> String { (["Tips for Tips — Bill Split", "", result.session.name, "Total: \(formatMoney(result.roundedCollectedTotal, code: result.session.currencyCode))", ""] + result.participantResults.map { "\($0.participantName): \(formatMoney($0.finalAmount, code: result.session.currencyCode))" }).joined(separator: "\n") }
    func receiptSummary(_ receipt: ReceiptRecord, includeImageNotice: Bool = false) -> String { ["Tips for Tips — Receipt", "", receipt.displayName, receipt.receiptDate?.formatted(date: .abbreviated, time: .omitted), receipt.subtotal.map { "Subtotal: \(formatMoney($0, code: receipt.currencyCode))" }, receipt.tax.map { "Tax: \(formatMoney($0, code: receipt.currencyCode))" }, receipt.total.map { "Total: \(formatMoney($0, code: receipt.currencyCode))" }, receipt.notes.isEmpty ? nil : "Notes: \(receipt.notes)", includeImageNotice ? "Receipt image intentionally included by the user." : nil].compactMap { $0 }.joined(separator: "\n") }
    func currencySummary(source: ConvertibleAmount, converted: Decimal, rate: Decimal, from: String, to: String, fetchedAt: Date, cached: Bool) -> String { "Tips for Tips — Currency Conversion\n\n\(formatMoney(source.amount, code: from)) ≈ \(formatMoney(converted, code: to))\n1 \(from) = \(rate) \(to)\n\nUsing a \(cached ? "cached" : "downloaded") rate downloaded \(fetchedAt.formatted(date: .abbreviated, time: .shortened))." }
}
