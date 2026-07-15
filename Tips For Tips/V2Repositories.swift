import Foundation

protocol CalculationRepository {
    func fetchCalculations() async throws -> [SavedCalculationRecord]
    func saveCalculation(_ record: SavedCalculationRecord) async throws
    func deleteCalculation(id: UUID) async throws
}

protocol ReceiptRepository {
    func fetchReceipts() async throws -> [ReceiptRecord]
    func saveReceipt(_ receipt: ReceiptRecord) async throws
    func deleteReceipt(id: UUID) async throws
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
        do { return try decoder.decode(UserPreferences.self, from: Data(contentsOf: fileURL)) }
        catch { throw V2PersistenceError.readFailed }
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
        do {
            try fileManager.createDirectory(at: markerURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(report).write(to: markerURL, options: [.atomic])
        } catch { }
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
        // Phase 1 intentionally backs up standalone notes but does not attach them to unrelated receipts.
        return 0
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
