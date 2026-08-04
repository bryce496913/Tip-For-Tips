import Foundation
import UIKit

protocol CalculationRepository: Sendable {
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

protocol UserPreferencesRepository: Sendable {
    func loadPreferences() async throws -> UserPreferences
    func savePreferences(_ preferences: UserPreferences) async throws
}

protocol CurrencyRateRepository: Sendable {
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
    case unsupportedSchema(found: Int, supported: Int)
    case corruptEnvelope

    var errorDescription: String? {
        switch self {
        case .readFailed: return "Saved app data could not be read."
        case .writeFailed: return "Saved app data could not be written."
        case .migrationFailed(let message): return "Some V1 data could not be migrated: \(message)"
        case .unsupportedSchema(let found, let supported): return "Saved data uses schema version \(found), but this app supports version \(supported)."
        case .corruptEnvelope: return "Saved data is corrupt and could not be decoded."
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

enum LegacyMigrationSourceKind: String, Codable, Hashable { case rootReceipts, intermediateReceipts, notes }
enum MigrationPhase: String, Codable, Hashable {
    case rootEmbeddedReceipts, intermediateReceiptMetadata, intermediateReceiptImages
    case timestampedNote, legacyNotesEnvelope, verification
}
struct MigrationRecoveryIssue: Identifiable, Codable, Hashable {
    let id: UUID
    let sourceKind: LegacyMigrationSourceKind
    let sourceRelativePath: String
    let phase: MigrationPhase
    let message: String
    let backupAvailable: Bool
    let detectedAt: Date
}
struct QuarantineManifest: Codable, Hashable {
    let sourceRelativePath: String; let migrationPhase: MigrationPhase; let failure: String
    let quarantinedAt: Date; let appVersion: String; let build: String
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
        do {
            let envelope = try decoder.decode(StoredDataEnvelope<Record>.self, from: Data(contentsOf: fileURL))
            guard envelope.version <= version else { throw V2PersistenceError.unsupportedSchema(found: envelope.version, supported: version) }
            // Version 1 and 2 envelopes have the same generic record representation;
            // accepting v1 here is the explicit lossless migration to the current model.
            guard envelope.version == version || envelope.version == 1 else { throw V2PersistenceError.unsupportedSchema(found: envelope.version, supported: version) }
            return envelope.records
        } catch let error as V2PersistenceError { throw error }
        catch { throw V2PersistenceError.corruptEnvelope }
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
    private let receiptRepository: ReceiptRepository?
    private(set) var recoveryIssues: [MigrationRecoveryIssue] = []

    init(rootURL: URL? = nil, fileManager: FileManager = .default, receiptRepository: ReceiptRepository? = nil) {
        self.rootURL = rootURL ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.fileManager = fileManager
        self.receiptRepository = receiptRepository
    }

    func migrateIfNeeded() async -> V2MigrationReport {
        recoveryIssues = []
        let markerURL = rootURL.appendingPathComponent("V2/migration-v2-complete.json")
        if let data = try? Data(contentsOf: markerURL), let report = try? JSONDecoder().decode(V2MigrationReport.self, from: data) { return report }

        var failures: [String] = []
        var migratedReceipts = 0
        var migratedNotes = 0

        do {
            try backupLegacyFileIfPresent(named: "receipts.json")
            migratedReceipts += try await migrateRootLegacyReceipts()
        } catch {
            failures.append("receipts.json: \(error.localizedDescription)")
            recoveryIssues.append(issue(kind: .rootReceipts, path: "receipts.json", phase: .rootEmbeddedReceipts, error: error))
        }

        do {
            migratedReceipts += try await migrateLegacyReceiptsMetadata()
        } catch {
            failures.append("Receipts/receipts.json: \(error.localizedDescription)")
            recoveryIssues.append(issue(kind: .intermediateReceipts, path: "Receipts/receipts.json", phase: .intermediateReceiptMetadata, error: error))
        }

        do { try validateLegacyNotesEnvelope() }
        catch { failures.append("Notes/notes.json: \(error.localizedDescription)"); recoveryIssues.append(issue(kind: .notes, path: "Notes/notes.json", phase: .legacyNotesEnvelope, error: error)) }
        let noteResults = migrateTimestampedNotes()
        migratedNotes += noteResults.filter { $0.failure == nil && $0.migratedNoteID != nil }.count
        for result in noteResults where result.failure != nil {
            let error = V2PersistenceError.migrationFailed(result.failure ?? "The note could not be migrated.")
            failures.append("\(result.sourceRelativePath): \(error.localizedDescription)")
            recoveryIssues.append(issue(kind: .notes, path: result.sourceRelativePath, phase: .timestampedNote, error: error))
        }

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

    func quarantine(_ issue: MigrationRecoveryIssue, appVersion: String, build: String) throws {
        let source = try validatedLegacySource(issue.sourceRelativePath)
        guard fileManager.fileExists(atPath: source.path) else { return }
        let safeName = issue.sourceRelativePath.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ".json", with: "")
        let folder = rootURL.appendingPathComponent("V2/Backups/Quarantine/\(Int(Date().timeIntervalSince1970))-\(safeName)")
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        try fileManager.moveItem(at: source, to: folder.appendingPathComponent(source.lastPathComponent))
        let manifest = QuarantineManifest(sourceRelativePath: issue.sourceRelativePath, migrationPhase: issue.phase, failure: issue.message, quarantinedAt: Date(), appVersion: appVersion, build: build)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: folder.appendingPathComponent("quarantine-manifest.json"), options: .atomic)
    }

    func deleteSource(_ issue: MigrationRecoveryIssue) throws {
        let source = try validatedLegacySource(issue.sourceRelativePath)
        guard fileManager.fileExists(atPath: source.path) else { return }
        try fileManager.removeItem(at: source)
    }

    private func validatedLegacySource(_ relativePath: String) throws -> URL {
        guard !relativePath.hasPrefix("/"), !relativePath.split(separator: "/").contains("..") else {
            throw V2PersistenceError.migrationFailed("The recovery source path is unsafe.")
        }
        let formatter = DateFormatter(); formatter.dateFormat = "dd MM yyyy HH:mm"; formatter.locale = Locale(identifier: "en_US_POSIX")
        let isTimestampedRootNote = !relativePath.contains("/") && relativePath.hasSuffix(".txt") && formatter.date(from: URL(fileURLWithPath: relativePath).deletingPathExtension().lastPathComponent) != nil
        let allowed = relativePath == "receipts.json" || relativePath == "notes.json" || relativePath.hasPrefix("Receipts/") || relativePath.hasPrefix("Notes/") || isTimestampedRootNote
        guard allowed else { throw V2PersistenceError.migrationFailed("The recovery source is outside approved legacy storage.") }
        let source = rootURL.appendingPathComponent(relativePath).standardizedFileURL
        guard source.path.hasPrefix(rootURL.standardizedFileURL.path + "/") else { throw V2PersistenceError.migrationFailed("The recovery source path is unsafe.") }
        let resolvedRoot = rootURL.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        guard source.resolvingSymlinksInPath().path.hasPrefix(resolvedRoot) else { throw V2PersistenceError.migrationFailed("The recovery source symlink leaves approved legacy storage.") }
        return source
    }

    private func issue(kind: LegacyMigrationSourceKind, path: String, phase: MigrationPhase, error: Error) -> MigrationRecoveryIssue {
        let backup = rootURL.appendingPathComponent("V2/Backups/\((path as NSString).lastPathComponent).v1-backup")
        return .init(id: UUID(), sourceKind: kind, sourceRelativePath: path, phase: phase, message: "Legacy \(kind.rawValue) data could not be decoded.", backupAvailable: fileManager.fileExists(atPath: backup.path), detectedAt: Date())
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
        let destinationImages = rootURL.appendingPathComponent("V2/Receipts/Images", isDirectory: true)
        let destinationThumbnails = rootURL.appendingPathComponent("V2/Receipts/Thumbnails", isDirectory: true)
        try fileManager.createDirectory(at: destinationImages, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: destinationThumbnails, withIntermediateDirectories: true)
        var records: [ReceiptRecord] = []
        for legacy in envelope.records {
            let imageName = try copyLegacyImage(named: legacy.imageFilename, from: rootURL.appendingPathComponent("Receipts/Images"), to: destinationImages)
            let thumbnailName = try legacy.thumbnailFilename.flatMap { try copyLegacyImage(named: $0, from: rootURL.appendingPathComponent("Receipts/Thumbnails"), to: destinationThumbnails) }
            records.append(ReceiptRecord(id: legacy.id, merchantName: legacy.name, receiptDate: nil, subtotal: nil, tax: nil, total: nil, detectedCharges: [], imageFilename: imageName, thumbnailFilename: thumbnailName, notes: "", createdAt: legacy.createdAt, updatedAt: legacy.updatedAt))
        }
        let target = CodableFileStore<ReceiptRecord>(fileURL: rootURL.appendingPathComponent("V2/Receipts/receipts.json"))
        let existing = try await target.load(version: Self.currentVersion)
        let existingIDs = Set(existing.map(\.id))
        let additions = records.filter { !existingIDs.contains($0.id) }
        try await target.save(existing + additions, version: Self.currentVersion)
        return additions.count
    }

    /// Imports the original released V1 `Receipt` model: an unwrapped JSON array
    /// containing `id`, PNG `imageData`, and `name`.
    private func migrateRootLegacyReceipts() async throws -> Int {
        let legacyURL = rootURL.appendingPathComponent("receipts.json")
        guard fileManager.fileExists(atPath: legacyURL.path) else { return 0 }
        struct RootV1Receipt: Decodable { let id: UUID?; let imageData: Data?; let name: String
            enum CodingKeys: String, CodingKey { case id, imageData, name }
            init(from decoder: Decoder) throws { let c = try decoder.container(keyedBy: CodingKeys.self); id = try? c.decode(UUID.self, forKey: .id); imageData = try? c.decode(Data.self, forKey: .imageData); name = try c.decode(String.self, forKey: .name) }
        }
        let source = try JSONDecoder().decode([RootV1Receipt].self, from: Data(contentsOf: legacyURL))
        let repository: ReceiptRepository = receiptRepository ?? FileReceiptRepository(rootURL: rootURL, fileManager: fileManager)
        var existingIDs = Set(try await repository.fetchReceipts().map(\.id))
        let fileDate = ((try? fileManager.attributesOfItem(atPath: legacyURL.path)[.modificationDate]) as? Date) ?? Date()
        var migrated = 0
        for (index, legacy) in source.enumerated() {
            let id = legacy.id ?? deterministicLegacyReceiptID(name: legacy.name, index: index)
            guard existingIDs.insert(id).inserted else { continue }
            let record = ReceiptRecord(id: id, merchantName: legacy.name.nilIfBlank, receiptDate: nil, subtotal: nil, tax: nil, total: nil, detectedCharges: [], imageFilename: nil, thumbnailFilename: nil, notes: "", createdAt: fileDate, updatedAt: fileDate)
            if let data = legacy.imageData, let image = UIImage(data: data) {
                _ = try await repository.create(draft: record, fullImage: image, thumbnail: image.resizedForReceipt(maxDimension: 420))
            } else { try await repository.createMetadataOnly(draft: record) }
            guard let verified = try await repository.receipt(id: id), verified.id == id else { throw V2PersistenceError.migrationFailed("A root-level receipt could not be verified.") }
            migrated += 1
        }
        return migrated
    }

    private func deterministicLegacyReceiptID(name: String, index: Int) -> UUID {
        let bytes = Array("tips-for-tips-v1|\(index)|\(name)".utf8)
        var a: UInt64 = 0xcbf29ce484222325, b: UInt64 = 0x84222325cbf29ce4
        for byte in bytes { a = (a ^ UInt64(byte)) &* 0x100000001b3; b = (b ^ UInt64(byte &+ 31)) &* 0x100000001b3 }
        var raw = withUnsafeBytes(of: a.bigEndian, Array.init) + withUnsafeBytes(of: b.bigEndian, Array.init)
        raw[6] = (raw[6] & 0x0f) | 0x50; raw[8] = (raw[8] & 0x3f) | 0x80
        return UUID(uuid: (raw[0],raw[1],raw[2],raw[3],raw[4],raw[5],raw[6],raw[7],raw[8],raw[9],raw[10],raw[11],raw[12],raw[13],raw[14],raw[15]))
    }

    private func validateLegacyNotesEnvelope() throws {
        let notesURL = rootURL.appendingPathComponent("Notes/notes.json")
        guard fileManager.fileExists(atPath: notesURL.path) else { return }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        _ = try decoder.decode(StoredDataEnvelope<SavedNote>.self, from: Data(contentsOf: notesURL))
    }

    struct LegacyNoteMigrationResult {
        var sourceRelativePath: String
        var migratedNoteID: UUID?
        var warning: String?
        var failure: String?
    }

    private func migrateTimestampedNotes() -> [LegacyNoteMigrationResult] {
        let formatter = DateFormatter(); formatter.dateFormat = "dd MM yyyy HH:mm"; formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let candidates = try? fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: [.contentModificationDateKey]).filter({ $0.pathExtension == "txt" && formatter.date(from: $0.deletingPathExtension().lastPathComponent) != nil }) else { return [] }
        let notesURL = rootURL.appendingPathComponent("Notes/notes.json")
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        var notes: [SavedNote] = []
        if fileManager.fileExists(atPath: notesURL.path) {
            guard let existing = try? decoder.decode(StoredDataEnvelope<SavedNote>.self, from: Data(contentsOf: notesURL)).records else { return [] }
            notes = existing
        }
        var results: [LegacyNoteMigrationResult] = []
        for file in candidates {
            let relative = file.lastPathComponent
            do {
                let text = try String(contentsOf: file, encoding: .utf8)
                let values = try file.resourceValues(forKeys: [.contentModificationDateKey])
                let created = formatter.date(from: file.deletingPathExtension().lastPathComponent) ?? values.contentModificationDate ?? Date()
                let note = SavedNote(id: UUID(), text: text, createdAt: created, updatedAt: values.contentModificationDate ?? created)
                var updated = notes; updated.append(note)
                try fileManager.createDirectory(at: notesURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
                try encoder.encode(StoredDataEnvelope(version: 1, records: updated)).write(to: notesURL, options: .atomic)
                let legacy = rootURL.appendingPathComponent("Notes/Legacy", isDirectory: true); try fileManager.createDirectory(at: legacy, withIntermediateDirectories: true)
                try fileManager.moveItem(at: file, to: legacy.appendingPathComponent(relative))
                notes = updated; results.append(.init(sourceRelativePath: relative, migratedNoteID: note.id, warning: nil, failure: nil))
            } catch { results.append(.init(sourceRelativePath: relative, migratedNoteID: nil, warning: nil, failure: error.localizedDescription)) }
        }
        return results
    }

    private func copyLegacyImage(named filename: String, from sourceDirectory: URL, to destinationDirectory: URL) throws -> String? {
        let safeName = (filename as NSString).lastPathComponent
        guard safeName == filename, !safeName.isEmpty else { throw V2PersistenceError.migrationFailed("An image filename was unsafe.") }
        let source = sourceDirectory.appendingPathComponent(safeName)
        guard fileManager.fileExists(atPath: source.path) else { return nil }
        let destination = destinationDirectory.appendingPathComponent(safeName)
        if !fileManager.fileExists(atPath: destination.path) { try fileManager.copyItem(at: source, to: destination) }
        guard fileManager.fileExists(atPath: destination.path) else { throw V2PersistenceError.migrationFailed("An image could not be verified.") }
        return safeName
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
        let token = UUID().uuidString
        let stagedImageURL = temporaryDir.appendingPathComponent("create-\(token)-\(imageName)")
        let stagedThumbURL = temporaryDir.appendingPathComponent("create-\(token)-\(thumbName)")
        var record = draft; record.imageFilename = imageName; record.thumbnailFilename = thumbName
        do {
            try fullData.write(to: stagedImageURL, options: [.atomic]); try thumbData.write(to: stagedThumbURL, options: [.atomic])
            guard UIImage(contentsOfFile: stagedImageURL.path) != nil, UIImage(contentsOfFile: stagedThumbURL.path) != nil else { throw ReceiptStorageError.imageWrite }
            // Refuse to overwrite an existing receipt's images during creation.
            guard !fileManager.fileExists(atPath: imageURL.path), !fileManager.fileExists(atPath: thumbURL.path) else { throw ReceiptStorageError.imageWrite }
            _ = try loadRecords() // validate existing metadata before final file moves
            try fileManager.moveItem(at: stagedImageURL, to: imageURL)
            try fileManager.moveItem(at: stagedThumbURL, to: thumbURL)
            try persistReceipt(record)
            return record
        } catch {
            try? fileManager.removeItem(at: stagedImageURL); try? fileManager.removeItem(at: stagedThumbURL)
            try? fileManager.removeItem(at: imageURL); try? fileManager.removeItem(at: thumbURL)
            throw error
        }
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
    func loadImage(filename: String) async throws -> UIImage {
        let url = try validatedURL(filename: filename, in: imagesDir)
        guard fileManager.fileExists(atPath: url.path) else { throw ReceiptStorageError.imageMissing }
        guard let image = UIImage(contentsOfFile: url.path) else { throw ReceiptStorageError.imageCorrupt }
        return image
    }
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
