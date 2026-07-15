import Foundation

// MARK: - V2 Core Domain Models

enum TipCalculationBasis: String, Codable, CaseIterable, Identifiable, Hashable {
    case subtotalBeforeTax
    case finalTotalAfterTax

    var id: String { rawValue }
    var title: String {
        switch self {
        case .subtotalBeforeTax: return "Subtotal before tax"
        case .finalTotalAfterTax: return "Final total after tax"
        }
    }
}

enum ServiceQuality: String, Codable, CaseIterable, Identifiable, Hashable {
    case poor, standard, good, exceptional
    var id: String { rawValue }
}

enum GratuityStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case no, yes, unsure
    var id: String { rawValue }
}

enum IncludedGratuityEntryMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case percentage, amount, unknown
    var id: String { rawValue }
}

enum BartenderTipMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case percentageOfTab, perDrink
    var id: String { rawValue }
}

struct FoodDeliveryDifficulty: OptionSet, Codable, Hashable {
    let rawValue: Int
    static let badWeather = FoodDeliveryDifficulty(rawValue: 1 << 0)
    static let longDistance = FoodDeliveryDifficulty(rawValue: 1 << 1)
    static let difficultEntrance = FoodDeliveryDifficulty(rawValue: 1 << 2)
    static let largeOrder = FoodDeliveryDifficulty(rawValue: 1 << 3)
    static let lateNight = FoodDeliveryDifficulty(rawValue: 1 << 4)
}

enum RoundingPreference: String, Codable, CaseIterable, Identifiable, Hashable {
    case exactCents
    case roundEachPaymentUpToDollar
    case roundToNearestDollar
    var id: String { rawValue }
}

enum AppearancePreference: String, Codable, CaseIterable, Identifiable, Hashable {
    case system, dark, light
    var id: String { rawValue }
}

enum TippingServiceCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case restaurants
    case bars
    case coffeeShops
    case hotels
    case taxisAndRideshare
    case foodDelivery
    case salonsAndSpas
    case tourGuides
    case valetParking
    case coatChecks
    case housekeeping
    case bellStaff
    case entertainmentVenues
    case includedGratuityAndServiceCharges
    case otherOptionalCounterService

    var id: String { rawValue }
    var title: String {
        switch self {
        case .restaurants: return "Restaurants"
        case .bars: return "Bars"
        case .coffeeShops: return "Coffee shops"
        case .hotels: return "Hotels"
        case .taxisAndRideshare: return "Taxis and rideshare"
        case .foodDelivery: return "Food delivery"
        case .salonsAndSpas: return "Salons and spas"
        case .tourGuides: return "Tour guides"
        case .valetParking: return "Valet parking"
        case .coatChecks: return "Coat checks"
        case .housekeeping: return "Housekeeping"
        case .bellStaff: return "Bell staff"
        case .entertainmentVenues: return "Entertainment venues"
        case .includedGratuityAndServiceCharges: return "Included gratuity and service charges"
        case .otherOptionalCounterService: return "Other optional counter service"
        }
    }
}

enum TippingRecommendation: Codable, Hashable {
    case percentage(minimum: Decimal, standard: Decimal, maximum: Decimal)
    case fixedAmount(minimum: Decimal?, standard: Decimal?, maximum: Decimal?, unitDescription: String)
    case optional(suggestedPercentage: Decimal?, explanation: String)
    case informational(String)
}

struct TippingService: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let category: TippingServiceCategory
    let recommendation: TippingRecommendation
    let explanation: String
    let guideSectionID: String?
    var symbolName: String = "questionmark.circle"

    var recommendationSummary: String {
        switch recommendation {
        case let .percentage(minimum, standard, maximum):
            if minimum == maximum { return "\(minimum)%" }
            return "\(minimum)–\(maximum)% (\(standard)% typical)"
        case let .fixedAmount(minimum, standard, maximum, unitDescription):
            let parts = [minimum, standard, maximum].compactMap { $0 }.map { "$\($0)" }
            return parts.isEmpty ? unitDescription : "\(parts.joined(separator: "–")) \(unitDescription)"
        case let .optional(suggestedPercentage, _):
            if let suggestedPercentage { return "Optional, around \(suggestedPercentage)% when appropriate" }
            return "Optional"
        case let .informational(text): return text
        }
    }
}

struct DecimalRange: Codable, Hashable {
    var minimum: Decimal
    var maximum: Decimal
}

struct TipCalculationInput: Codable, Hashable {
    var serviceID: String
    var subtotal: Decimal?
    var tax: Decimal?
    var finalTotal: Decimal?
    var calculationBasis: TipCalculationBasis
    var serviceQuality: ServiceQuality
    var gratuityStatus: GratuityStatus
    var includedGratuityAmount: Decimal?
    var includedGratuityPercentage: Decimal?
    var includedGratuityEntryMode: IncludedGratuityEntryMode
    var finalTotalIncludesIncludedGratuity: Bool
    var peopleCount: Int
    var currencyCode: String
    var bartenderTipMode: BartenderTipMode
    var numberOfDrinks: Int?
    var numberOfBags: Int?
    var numberOfHousekeepingDays: Int?
    var foodDeliveryDifficulty: FoodDeliveryDifficulty

    static func defaults(preferences: UserPreferences = .defaults) -> TipCalculationInput {
        TipCalculationInput(serviceID: "restaurant", subtotal: nil, tax: nil, finalTotal: nil, calculationBasis: preferences.tipCalculationBasis, serviceQuality: .standard, gratuityStatus: .no, includedGratuityAmount: nil, includedGratuityPercentage: nil, includedGratuityEntryMode: .unknown, finalTotalIncludesIncludedGratuity: true, peopleCount: max(1, preferences.defaultPeopleCount), currencyCode: preferences.homeCurrencyCode, bartenderTipMode: .percentageOfTab, numberOfDrinks: nil, numberOfBags: nil, numberOfHousekeepingDays: nil, foodDeliveryDifficulty: [])
    }
}

struct TipAlternative: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var label: String
    var percentage: Decimal?
    var amount: Decimal
    var explanation: String
}

struct TipCalculationResult: Identifiable, Codable, Hashable {
    let id: UUID
    let createdAt: Date
    let input: TipCalculationInput
    let recommendedPercentage: Decimal?
    let normalRange: DecimalRange?
    let service: TippingService
    let baseBillAmount: Decimal
    let customaryGuidance: String
    let includedGratuityAmount: Decimal
    let suggestedAdditionalTip: Decimal
    let combinedGratuity: Decimal
    let recommendedTipAmount: Decimal
    let finalTotal: Decimal
    let lowerAlternative: TipAlternative?
    let higherAlternative: TipAlternative?
    let explanation: String

    var amountPerPerson: Decimal {
        let people = max(input.peopleCount, 1)
        return finalTotal / Decimal(people)
    }
}

struct CurrencyConversionSnapshot: Codable, Hashable {
    var sourceCurrencyCode: String
    var destinationCurrencyCode: String
    var billAmount: Decimal
    var tipAmount: Decimal
    var totalAmount: Decimal
    var convertedBillAmount: Decimal
    var convertedTipAmount: Decimal
    var convertedTotalAmount: Decimal
    var rate: Decimal
    var rateDate: Date?
    var fetchedAt: Date
    var usedCachedRate: Bool
}

enum SavedCalculationRecordType: String, Codable, Hashable {
    case tipOnly, split, receiptOnly, converted
}

struct SavedCalculationRecord: Identifiable, Codable, Hashable {
    let id: UUID
    var recordType: SavedCalculationRecordType
    var tipResult: TipCalculationResult?
    var splitResult: SplitCalculationResult?
    var receiptID: UUID?
    var merchantName: String?
    var notes: String
    var currencyConversion: CurrencyConversionSnapshot?
    var shareSummary: String?
    let createdAt: Date
    var updatedAt: Date
}

enum ReceiptChargeKind: String, Codable, Hashable {
    case includedMandatoryCharge
    case suggestedTip
    case deliveryFee
    case unknownCharge
    case includedGratuity
    case automaticGratuity
    case serviceCharge
    case hospitalityCharge
    case administrativeFee
    case suggestedGratuity
    case unknown
}

enum ReceiptChargeClassification: String, Codable, CaseIterable, Identifiable, Hashable {
    case includedGratuity
    case serviceChargeUnsure
    case deliveryFee
    case suggestedGratuityOnly
    case notRelevant
    case otherOrUnclear

    var id: String { rawValue }
    var title: String {
        switch self {
        case .includedGratuity: return "Included gratuity"
        case .serviceChargeUnsure: return "Service charge / unsure"
        case .deliveryFee: return "Delivery fee"
        case .suggestedGratuityOnly: return "Suggested only"
        case .notRelevant: return "Not relevant"
        case .otherOrUnclear: return "Other or unclear"
        }
    }
}

struct DetectedReceiptCharge: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var label: String
    var amount: Decimal?
    var percentage: Decimal? = nil
    var kind: ReceiptChargeKind
    var confidence: Decimal
    var userClassification: ReceiptChargeClassification? = nil
}

enum ReceiptConfirmationStatus: String, Codable, Hashable {
    case imported
    case needsReview
    case userConfirmed
}

struct ReceiptRecord: Identifiable, Codable, Hashable {
    let id: UUID
    var merchantName: String?
    var receiptDate: Date?
    var currencyCode: String
    var subtotal: Decimal?
    var tax: Decimal?
    var total: Decimal?
    var detectedCharges: [DetectedReceiptCharge]
    var imageFilename: String?
    var thumbnailFilename: String?
    var recognizedText: String?
    var notes: String
    var confirmationStatus: ReceiptConfirmationStatus
    let createdAt: Date
    var updatedAt: Date

    var displayName: String { merchantName?.isEmpty == false ? merchantName! : "Receipt" }

    init(id: UUID, merchantName: String?, receiptDate: Date?, currencyCode: String = "USD", subtotal: Decimal?, tax: Decimal?, total: Decimal?, detectedCharges: [DetectedReceiptCharge], imageFilename: String?, thumbnailFilename: String?, recognizedText: String? = nil, notes: String, confirmationStatus: ReceiptConfirmationStatus = .imported, createdAt: Date, updatedAt: Date) {
        self.id = id; self.merchantName = merchantName; self.receiptDate = receiptDate; self.currencyCode = currencyCode; self.subtotal = subtotal; self.tax = tax; self.total = total; self.detectedCharges = detectedCharges; self.imageFilename = imageFilename; self.thumbnailFilename = thumbnailFilename; self.recognizedText = recognizedText; self.notes = notes; self.confirmationStatus = confirmationStatus; self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey { case id, merchantName, receiptDate, currencyCode, subtotal, tax, total, detectedCharges, imageFilename, thumbnailFilename, recognizedText, notes, confirmationStatus, createdAt, updatedAt }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); merchantName = try c.decodeIfPresent(String.self, forKey: .merchantName); receiptDate = try c.decodeIfPresent(Date.self, forKey: .receiptDate); currencyCode = try c.decodeIfPresent(String.self, forKey: .currencyCode) ?? "USD"; subtotal = try c.decodeIfPresent(Decimal.self, forKey: .subtotal); tax = try c.decodeIfPresent(Decimal.self, forKey: .tax); total = try c.decodeIfPresent(Decimal.self, forKey: .total); detectedCharges = try c.decodeIfPresent([DetectedReceiptCharge].self, forKey: .detectedCharges) ?? []; imageFilename = try c.decodeIfPresent(String.self, forKey: .imageFilename); thumbnailFilename = try c.decodeIfPresent(String.self, forKey: .thumbnailFilename); recognizedText = try c.decodeIfPresent(String.self, forKey: .recognizedText); notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""; confirmationStatus = try c.decodeIfPresent(ReceiptConfirmationStatus.self, forKey: .confirmationStatus) ?? .imported; createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(); updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }
}

struct SplitCalculatorContext: Hashable, Codable {
    var sourceCalculationID: UUID?
    var receiptID: UUID?
    var currencyCode: String
    var subtotal: Decimal?
    var tax: Decimal?
    var tipAmount: Decimal?
    var total: Decimal?
    var suggestedPeopleCount: Int?

    static let manual = SplitCalculatorContext(sourceCalculationID: nil, receiptID: nil, currencyCode: "USD", subtotal: nil, tax: nil, tipAmount: nil, total: nil, suggestedPeopleCount: nil)

    static func tipResult(_ result: TipCalculationResult, sourceCalculationID: UUID? = nil) -> SplitCalculatorContext {
        SplitCalculatorContext(sourceCalculationID: sourceCalculationID ?? result.id, receiptID: nil, currencyCode: result.input.currencyCode, subtotal: result.input.subtotal ?? result.baseBillAmount, tax: result.input.tax, tipAmount: result.suggestedAdditionalTip, total: result.finalTotal, suggestedPeopleCount: result.input.peopleCount)
    }

    static func receipt(_ receipt: ReceiptRecord) -> SplitCalculatorContext {
        let included = receipt.detectedCharges.filter { [.includedGratuity, .automaticGratuity].contains($0.kind) || $0.userClassification == .includedGratuity }.compactMap(\.amount).reduce(Decimal(0), +)
        return SplitCalculatorContext(sourceCalculationID: nil, receiptID: receipt.id, currencyCode: receipt.currencyCode, subtotal: receipt.subtotal, tax: receipt.tax, tipAmount: included == 0 ? nil : included, total: receipt.total, suggestedPeopleCount: nil)
    }
}

enum SplitMode: String, CaseIterable, Identifiable, Codable, Hashable {
    case equal, customAmount, percentage, itemized
    var id: String { rawValue }
    var title: String { switch self { case .equal: return "Equal Split"; case .customAmount: return "Custom Amount"; case .percentage: return "Percentage"; case .itemized: return "Itemized" } }
}

enum ChargeAllocationMode: String, CaseIterable, Identifiable, Codable, Hashable {
    case proportional, equal, custom
    var id: String { rawValue }
    var title: String { switch self { case .proportional: return "Proportional"; case .equal: return "Equal"; case .custom: return "Custom" } }
}

enum SplitRoundingRule: String, CaseIterable, Identifiable, Codable, Hashable {
    case exactCents, nearestDollar, roundUpToDollar
    var id: String { rawValue }
    var title: String { switch self { case .exactCents: return "Exact cents"; case .nearestDollar: return "Nearest dollar"; case .roundUpToDollar: return "Round up" } }
    init(preference: RoundingPreference) { switch preference { case .exactCents: self = .exactCents; case .roundEachPaymentUpToDollar: self = .roundUpToDollar; case .roundToNearestDollar: self = .nearestDollar } }
}

struct SplitParticipant: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var percentage: Decimal?
    var customAmount: Decimal?
    var customTaxAmount: Decimal?
    var customTipAmount: Decimal?
    var isPaid: Bool

    init(id: UUID = UUID(), name: String, percentage: Decimal? = nil, customAmount: Decimal? = nil, customTaxAmount: Decimal? = nil, customTipAmount: Decimal? = nil, isPaid: Bool = false) {
        self.id = id; self.name = name; self.percentage = percentage; self.customAmount = customAmount; self.customTaxAmount = customTaxAmount; self.customTipAmount = customTipAmount; self.isPaid = isPaid
    }
}

struct SplitItemAssignment: Identifiable, Codable, Hashable {
    let id: UUID
    let participantID: UUID
    var share: Decimal
    init(id: UUID = UUID(), participantID: UUID, share: Decimal) { self.id = id; self.participantID = participantID; self.share = share }
}

enum SplitItemSharingRule: String, Codable, Hashable { case assigned, sharedBySelected, sharedByEveryone, customShares }

struct SplitItem: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var price: Decimal
    var assignments: [SplitItemAssignment]
    var sharingRule: SplitItemSharingRule
    init(id: UUID = UUID(), name: String, price: Decimal = 0, assignments: [SplitItemAssignment] = [], sharingRule: SplitItemSharingRule = .assigned) {
        self.id = id; self.name = name; self.price = price; self.assignments = assignments; self.sharingRule = sharingRule
    }
}

struct SplitSession: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var mode: SplitMode
    var currencyCode: String
    var subtotal: Decimal
    var tax: Decimal
    var tipAmount: Decimal
    var total: Decimal
    var participants: [SplitParticipant]
    var items: [SplitItem]
    var taxAllocationMode: ChargeAllocationMode
    var tipAllocationMode: ChargeAllocationMode
    var roundingRule: SplitRoundingRule
    var sourceCalculationID: UUID?
    var receiptID: UUID?
    let createdAt: Date
    var updatedAt: Date
}

struct ParticipantItemBreakdown: Identifiable, Codable, Hashable { let id: UUID; let itemID: UUID; let itemName: String; let amount: Decimal }
struct ParticipantSplitResult: Identifiable, Codable, Hashable { let id: UUID; let participantID: UUID; let participantName: String; let baseAmount: Decimal; let taxAmount: Decimal; let tipAmount: Decimal; let roundingAdjustment: Decimal; let finalAmount: Decimal; let isPaid: Bool; let itemBreakdown: [ParticipantItemBreakdown] }

struct SplitCalculationResult: Identifiable, Codable, Hashable {
    let id: UUID
    let sessionID: UUID
    let session: SplitSession
    let participantResults: [ParticipantSplitResult]
    let originalTotal: Decimal
    let roundedCollectedTotal: Decimal
    let roundingDifference: Decimal
    let unallocatedAmount: Decimal
    let createdAt: Date
}

struct UserPreferences: Codable, Hashable {
    var homeCurrencyCode: String
    var defaultTipPercentage: Decimal
    var tipCalculationBasis: TipCalculationBasis
    var defaultPeopleCount: Int
    var roundingPreference: RoundingPreference
    var showTippingExplanations: Bool
    var hapticsEnabled: Bool
    var soundsEnabled: Bool
    var appearancePreference: AppearancePreference
    var hasCompletedOnboarding: Bool

    static let defaults = UserPreferences(homeCurrencyCode: "USD", defaultTipPercentage: 20, tipCalculationBasis: .subtotalBeforeTax, defaultPeopleCount: 1, roundingPreference: .exactCents, showTippingExplanations: true, hapticsEnabled: true, soundsEnabled: true, appearancePreference: .dark, hasCompletedOnboarding: false)
}

// MARK: - V2 Phase 5 Connected Experience Models

enum HistoryRecordType: String, Codable, CaseIterable, Identifiable, Hashable {
    case tipCalculation
    case receipt
    case split
    var id: String { rawValue }
    var title: String { switch self { case .tipCalculation: return "Tip Calculations"; case .receipt: return "Receipts"; case .split: return "Splits" } }
}

struct HistoryEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let recordType: HistoryRecordType
    let linkedRecordID: UUID
    var title: String
    var subtitle: String?
    var serviceID: String?
    var merchantName: String?
    var currencyCode: String
    var totalAmount: Decimal?
    let createdAt: Date
    var updatedAt: Date
    var participantNames: [String] = []
    var notes: String = ""
    var receiptThumbnailFilename: String? = nil
    var paidSummary: String? = nil
}

enum HistorySortOption: String, CaseIterable, Identifiable, Hashable {
    case newestFirst, oldestFirst, highestTotal, lowestTotal, title
    var id: String { rawValue }
    var title: String { switch self { case .newestFirst: return "Newest first"; case .oldestFirst: return "Oldest first"; case .highestTotal: return "Highest total"; case .lowestTotal: return "Lowest total"; case .title: return "Title A–Z" } }
}

struct HistoryFilter: Hashable {
    var recordType: HistoryRecordType? = nil
    var serviceID: String? = nil
    var currencyCode: String? = nil
    var dateRange: ClosedRange<Date>? = nil
    var paidOnly: Bool? = nil
    static let all = HistoryFilter()
}

struct HistoryViewState: Hashable {
    var entries: [HistoryEntry]
    var query: String = ""
    var filter: HistoryFilter = .all
    var sort: HistorySortOption = .newestFirst

    var filteredAndSorted: [HistoryEntry] {
        let normalizedQuery = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = entries.filter { entry in
            if let type = filter.recordType, entry.recordType != type { return false }
            if let serviceID = filter.serviceID, entry.serviceID != serviceID { return false }
            if let code = filter.currencyCode, entry.currencyCode != code { return false }
            if let range = filter.dateRange, !range.contains(entry.createdAt) { return false }
            if let paidOnly = filter.paidOnly {
                let isPaid = entry.paidSummary?.localizedCaseInsensitiveContains("all paid") == true
                if paidOnly != isPaid { return false }
            }
            guard !normalizedQuery.isEmpty else { return true }
            let haystack = ([entry.title, entry.subtitle, entry.serviceID, entry.merchantName, entry.currencyCode, entry.notes, entry.paidSummary] + entry.participantNames).compactMap { $0 }.joined(separator: " ") + " " + entry.createdAt.formatted(date: .abbreviated, time: .omitted)
            return haystack.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(normalizedQuery)
        }
        return filtered.sorted { a, b in
            switch sort {
            case .newestFirst: return a.createdAt == b.createdAt ? a.title < b.title : a.createdAt > b.createdAt
            case .oldestFirst: return a.createdAt == b.createdAt ? a.title < b.title : a.createdAt < b.createdAt
            case .highestTotal: return compareTotals(a, b, descending: true)
            case .lowestTotal: return compareTotals(a, b, descending: false)
            case .title: return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
        }
    }

    private func compareTotals(_ a: HistoryEntry, _ b: HistoryEntry, descending: Bool) -> Bool {
        switch (a.totalAmount, b.totalAmount) {
        case let (lhs?, rhs?) where lhs != rhs: return descending ? lhs > rhs : lhs < rhs
        case (_?, nil): return true
        case (nil, _?): return false
        default: return a.createdAt > b.createdAt
        }
    }
}

struct ConvertibleAmount: Identifiable, Hashable, Codable { let id: String; let label: String; let amount: Decimal }
struct CurrencyConversionContext: Hashable, Codable { var sourceCurrencyCode: String; var values: [ConvertibleAmount]; var sourceRecordID: UUID? }
struct MultiValueConversionLine: Identifiable, Hashable { let id: String; let label: String; let sourceAmount: Decimal; let convertedAmount: Decimal }
struct CurrencyPair: Identifiable, Codable, Hashable { var sourceCode: String; var destinationCode: String; var id: String { "\(sourceCode)-\(destinationCode)" } }
struct StoredExchangeRate: Identifiable, Codable, Hashable { var sourceCode: String; var destinationCode: String; var rate: Decimal; var rateDate: Date?; var fetchedAt: Date; var id: String { "\(sourceCode)-\(destinationCode)" } }

struct GuideBookmark: Identifiable, Codable, Hashable { var id: String; var createdAt: Date }
struct RecentGuideItem: Identifiable, Codable, Hashable { var id: String; var title: String; var viewedAt: Date }
