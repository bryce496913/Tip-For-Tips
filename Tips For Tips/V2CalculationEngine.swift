import Foundation

enum TipCalculationError: LocalizedError, Equatable {
    case missingService
    case missingBillAmount
    case invalidPeopleCount
    case negativeAmount(String)
    case missingServiceDetail(String)
    case invalidReceiptTotal(String)

    var errorDescription: String? {
        switch self {
        case .missingService: return "Choose the service you received."
        case .missingBillAmount: return "Enter a bill amount."
        case .invalidPeopleCount: return "Enter at least one person."
        case .negativeAmount(let field): return "\(field) cannot be negative."
        case .missingServiceDetail(let field): return "Enter \(field)."
        case .invalidReceiptTotal(let message): return message
        }
    }
}

struct TipRecommendationEngine {
    var services: [TippingService] = TippingGuidance.services

    func calculate(input: TipCalculationInput, preferences: UserPreferences = .defaults, now: Date = Date()) throws -> TipCalculationResult {
        guard let service = services.first(where: { $0.id == input.serviceID }) else { throw TipCalculationError.missingService }
        guard input.peopleCount > 0 else { throw TipCalculationError.invalidPeopleCount }
        try validateNonNegative(input)
        let baseAmount = try calculationBaseAmount(input)
        let receiptTotal = currentReceiptTotal(input: input, baseAmount: baseAmount)

        if service.id == "bar", input.bartenderTipMode == .perDrink {
            let amount = try fixedAmount(for: service, input: input, minimum: 1, standard: 2, maximum: 3)
            return result(service: service, input: input, now: now, percentage: nil, range: nil, guidance: "$1–$3 per drink", base: baseAmount, normalTip: amount, included: 0, additional: amount, combined: amount, receiptTotal: receiptTotal, lower: nil, higher: nil, explanation: "For individual drinks, a fixed amount per drink can be clearer than a percentage of the tab.")
        }

        switch service.recommendation {
        case let .percentage(minimum, standard, maximum):
            var recommended = recommendedPercentage(minimum: minimum, standard: standard, maximum: maximum, quality: input.serviceQuality)
            var extraReason = ""
            if service.id == "food-delivery" {
                let count = input.foodDeliveryDifficulty.rawValue.nonzeroBitCount
                if count > 0 { recommended = min(maximum + 5, recommended + Decimal(count)); extraReason = " Difficulty factors selected: \(count)." }
            }
            let normalTip = roundedCurrency(baseAmount * recommended / 100)
            let included = roundedCurrency(includedAmount(input: input, baseAmount: baseAmount))
            let additional = additionalTip(normalTip: normalTip, included: included, input: input, quality: input.serviceQuality, maximumTip: roundedCurrency(baseAmount * maximum / 100))
            let combined = roundedCurrency(included + additional)
            let lower = TipAlternative(label: "Lower option", percentage: minimum, amount: roundedCurrency(baseAmount * minimum / 100), explanation: "Lower end of the customary range for this service.")
            let higherPercent = max(maximum, standard + 2)
            let higher = TipAlternative(label: "Higher option", percentage: higherPercent, amount: roundedCurrency(baseAmount * higherPercent / 100), explanation: "Higher option for exceptional service or extra effort.")
            return result(service: service, input: input, now: now, percentage: recommended, range: DecimalRange(minimum: minimum, maximum: maximum), guidance: service.recommendationSummary, base: baseAmount, normalTip: normalTip, included: included, additional: additional, combined: combined, receiptTotal: receiptTotal, lower: lower, higher: higher, explanation: explanation(for: service, input: input, included: included, baseAmount: baseAmount, range: "\(minimum)–\(maximum)%", extra: extraReason))
        case let .fixedAmount(minimum, standard, maximum, unitDescription):
            let amount = try fixedAmount(for: service, input: input, minimum: minimum, standard: standard, maximum: maximum)
            let lower = meaningfulAlternative(label: "Lower option", amount: minimum, standard: amount, explanation: unitDescription)
            let higher = meaningfulAlternative(label: "Higher option", amount: maximum, standard: amount, explanation: unitDescription)
            return result(service: service, input: input, now: now, percentage: nil, range: nil, guidance: service.recommendationSummary, base: baseAmount, normalTip: amount, included: 0, additional: amount, combined: amount, receiptTotal: receiptTotal, lower: lower, higher: higher, explanation: "\(service.explanation) \(unitDescription).")
        case let .optional(suggestedPercentage, optionalExplanation):
            let percent = optionalPercentage(suggestedPercentage ?? preferences.defaultTipPercentage, quality: input.serviceQuality)
            let amount = roundedCurrency(baseAmount * percent / 100)
            return result(service: service, input: input, now: now, percentage: percent, range: nil, guidance: service.recommendationSummary, base: baseAmount, normalTip: amount, included: 0, additional: amount, combined: amount, receiptTotal: receiptTotal, lower: nil, higher: nil, explanation: optionalExplanation)
        case let .informational(info):
            return result(service: service, input: input, now: now, percentage: nil, range: nil, guidance: info, base: baseAmount, normalTip: 0, included: 0, additional: 0, combined: 0, receiptTotal: receiptTotal, lower: nil, higher: nil, explanation: service.explanation)
        }
    }

    private func result(service: TippingService, input: TipCalculationInput, now: Date, percentage: Decimal?, range: DecimalRange?, guidance: String, base: Decimal, normalTip: Decimal, included: Decimal, additional: Decimal, combined: Decimal, receiptTotal: Decimal, lower: TipAlternative?, higher: TipAlternative?, explanation: String) -> TipCalculationResult {
        TipCalculationResult(id: UUID(), createdAt: now, input: input, recommendedPercentage: percentage, normalRange: range, service: service, baseBillAmount: base, customaryGuidance: guidance, includedGratuityAmount: included, suggestedAdditionalTip: additional, combinedGratuity: combined, recommendedTipAmount: additional, finalTotal: roundedCurrency(receiptTotal + additional), lowerAlternative: lower, higherAlternative: higher, explanation: explanation)
    }

    private func validateNonNegative(_ input: TipCalculationInput) throws { for (name, value) in [("Subtotal", input.subtotal), ("Tax", input.tax), ("Final total", input.finalTotal), ("Included gratuity", input.includedGratuityAmount), ("Included gratuity percentage", input.includedGratuityPercentage)] { if let value, value < 0 { throw TipCalculationError.negativeAmount(name) } } }
    private func calculationBaseAmount(_ input: TipCalculationInput) throws -> Decimal {
        switch input.calculationBasis {
        case .subtotalBeforeTax:
            if let subtotal = input.subtotal { return subtotal }
            if let enteredFinalTotal = input.finalTotal {
                let taxIncludedInEnteredTotal = input.tax ?? 0
                let gratuityIncludedInEnteredTotal = input.finalTotalIncludesIncludedGratuity ? includedAmount(input: input, baseAmount: enteredFinalTotal) : 0
                let derivedSubtotal = enteredFinalTotal - taxIncludedInEnteredTotal - gratuityIncludedInEnteredTotal
                guard derivedSubtotal >= 0 else { throw TipCalculationError.invalidReceiptTotal("The entered final total is less than the tax or included gratuity already in that total.") }
                return derivedSubtotal
            }
        case .finalTotalAfterTax:
            if let total = input.finalTotal { return total }
            if let subtotal = input.subtotal { return subtotal + (input.tax ?? 0) }
        }
        throw TipCalculationError.missingBillAmount
    }
    private func currentReceiptTotal(input: TipCalculationInput, baseAmount: Decimal) -> Decimal {
        let subtotal = input.subtotal ?? baseAmount
        let tax = input.tax ?? 0
        let includedGratuity = includedAmount(input: input, baseAmount: baseAmount)
        if let enteredFinalTotal = input.finalTotal {
            return input.finalTotalIncludesIncludedGratuity ? enteredFinalTotal : enteredFinalTotal + includedGratuity
        }
        return subtotal + tax + includedGratuity
    }
    private func includedAmount(input: TipCalculationInput, baseAmount: Decimal) -> Decimal { if input.gratuityStatus != .yes { return 0 }; if input.includedGratuityEntryMode == .percentage, let p = input.includedGratuityPercentage { return baseAmount * p / 100 }; return input.includedGratuityAmount ?? 0 }
    private func additionalTip(normalTip: Decimal, included: Decimal, input: TipCalculationInput, quality: ServiceQuality, maximumTip: Decimal) -> Decimal { guard input.gratuityStatus == .yes else { return normalTip }; if quality == .exceptional, included >= maximumTip { return max(0, normalTip - included) }; return max(0, normalTip - included) }
    private func recommendedPercentage(minimum: Decimal, standard: Decimal, maximum: Decimal, quality: ServiceQuality) -> Decimal { switch quality { case .poor: return max(0, minimum - 3); case .standard: return minimum; case .good: return standard; case .exceptional: return maximum } }
    private func optionalPercentage(_ suggested: Decimal, quality: ServiceQuality) -> Decimal { switch quality { case .poor, .standard: return 0; case .good: return suggested; case .exceptional: return suggested + 5 } }
    private func fixedAmount(for service: TippingService, input: TipCalculationInput, minimum: Decimal?, standard: Decimal?, maximum: Decimal?) throws -> Decimal { let base: Decimal; switch service.id { case "bell-staff": guard let bags = input.numberOfBags, bags > 0 else { throw TipCalculationError.missingServiceDetail("the number of bags") }; return Decimal(2 + max(0, bags - 1)); case "housekeeping": guard let days = input.numberOfHousekeepingDays, days > 0 else { throw TipCalculationError.missingServiceDetail("the number of days") }; base = standard ?? minimum ?? maximum ?? 0; return base * Decimal(days); case "bar" where input.bartenderTipMode == .perDrink: guard let drinks = input.numberOfDrinks, drinks > 0 else { throw TipCalculationError.missingServiceDetail("the number of drinks") }; return Decimal(drinks * 2); default: base = standard ?? minimum ?? maximum ?? 0 }; switch input.serviceQuality { case .poor: return minimum ?? 0; case .standard: return base; case .good: return maximum ?? base; case .exceptional: return (maximum ?? base) + 2 } }
    private func meaningfulAlternative(label: String, amount: Decimal?, standard: Decimal, explanation: String) -> TipAlternative? { guard let amount, amount != standard else { return nil }; return TipAlternative(label: label, percentage: nil, amount: amount, explanation: explanation) }
    private func explanation(for service: TippingService, input: TipCalculationInput, included: Decimal, baseAmount: Decimal, range: String, extra: String) -> String { var parts = [service.explanation, "A \(input.serviceQuality.rawValue) service selection was matched to the customary \(range) guidance.", input.calculationBasis == .subtotalBeforeTax ? "This uses the pre-tax subtotal; tax remains in the payable total." : "This uses the final total after tax."]; if input.gratuityStatus == .yes { parts.append("Included gratuity of \(included) was credited so it is not double counted.") } else if input.gratuityStatus == .unsure { parts.append("You chose an unsure gratuity flow; review receipt terms before adding more.") } else { parts.append("This assumes no gratuity is included.") }; if !extra.isEmpty { parts.append(extra) }; parts.append("Calculation base: \(baseAmount) \(input.currencyCode)."); return parts.joined(separator: " ") }
    private func roundedCurrency(_ value: Decimal) -> Decimal { var value = value; var rounded = Decimal(); NSDecimalRound(&rounded, &value, 2, .plain); return rounded }
}

enum LocalizedDecimalParser { static func parse(_ text: String, locale: Locale = .current) -> Decimal? { let formatter = NumberFormatter(); formatter.numberStyle = .decimal; formatter.locale = locale; if let number = formatter.number(from: text) { return number.decimalValue }; let normalized = text.replacingOccurrences(of: ",", with: "."); return Decimal(string: normalized) } }

// MARK: - Split Calculation

enum SplitCalculationError: LocalizedError, Equatable {
    case invalidBill(String), noParticipants, negativeAmount(String), allocationMismatch(String), unassignedItem(String), invalidShare(String), danglingParticipant
    var errorDescription: String? { switch self { case .invalidBill(let m), .negativeAmount(let m), .allocationMismatch(let m), .unassignedItem(let m), .invalidShare(let m): return m; case .noParticipants: return "Add at least one participant."; case .danglingParticipant: return "This split contains an item assignment for a deleted participant." } }
}

struct SplitCalculationEngine {
    func calculate(session: SplitSession, now: Date = Date()) throws -> SplitCalculationResult {
        guard !session.participants.isEmpty else { throw SplitCalculationError.noParticipants }
        guard session.subtotal >= 0, session.tax >= 0, session.tipAmount >= 0, session.total >= 0 else { throw SplitCalculationError.invalidBill("Bill, tax, tip and total must be zero or positive.") }
        let calculatedTotal = session.subtotal + session.tax + session.tipAmount
        try require(calculatedTotal, equals: session.total, message: "Final total must equal subtotal plus tax plus tip before splitting.")
        guard session.total >= session.tax + session.tipAmount else { throw SplitCalculationError.invalidBill("Final total cannot be less than tax plus tip.") }
        let ids = Set(session.participants.map(\.id))
        var bases = Dictionary(uniqueKeysWithValues: session.participants.map { ($0.id, Decimal(0)) })
        var itemBreakdowns = Dictionary(uniqueKeysWithValues: session.participants.map { ($0.id, [ParticipantItemBreakdown]()) })
        switch session.mode {
        case .equal:
            bases = allocate(session.total - session.tax - session.tipAmount, among: session.participants.map(\.id))
        case .customAmount:
            for p in session.participants { guard (p.customAmount ?? 0) >= 0 else { throw SplitCalculationError.negativeAmount("Custom amounts cannot be negative.") }; bases[p.id] = p.customAmount ?? 0 }
            try require(sum(bases.values), equals: session.subtotal, message: "Custom amounts must equal the subtotal before tax and tip.")
        case .percentage:
            let percentTotal = session.participants.reduce(Decimal(0)) { $0 + ($1.percentage ?? 0) }
            for p in session.participants { guard (p.percentage ?? 0) >= 0 else { throw SplitCalculationError.negativeAmount("Percentages cannot be negative.") }; bases[p.id] = session.subtotal * (p.percentage ?? 0) / 100 }
            try require(percentTotal, equals: 100, message: "Percentages must total 100%.")
        case .itemized:
            for item in session.items {
                guard item.price >= 0 else { throw SplitCalculationError.negativeAmount("Item prices cannot be negative.") }
                guard !item.assignments.isEmpty || item.price == 0 else { throw SplitCalculationError.unassignedItem("Assign \(item.name.isEmpty ? "each item" : item.name) to at least one participant.") }
                let shareTotal = item.assignments.reduce(Decimal(0)) { $0 + $1.share }
                guard shareTotal == 0 || absDecimal(shareTotal - 1) <= Decimal(string: "0.0001")! else { throw SplitCalculationError.invalidShare("Item shares must total 100%.") }
                for a in item.assignments { guard ids.contains(a.participantID) else { throw SplitCalculationError.danglingParticipant }; guard a.share >= 0 else { throw SplitCalculationError.negativeAmount("Item shares cannot be negative.") }; let amount = item.price * a.share; bases[a.participantID, default: 0] += amount; itemBreakdowns[a.participantID, default: []].append(ParticipantItemBreakdown(id: UUID(), itemID: item.id, itemName: item.name.isEmpty ? "Item" : item.name, amount: amount)) }
            }
            try require(sum(bases.values), equals: session.subtotal, message: "Item totals must match the receipt subtotal before continuing.")
        }
        let taxes = try chargeAllocation(total: session.tax, mode: session.taxAllocationMode, participants: session.participants, bases: bases, keyPath: \.customTaxAmount, label: "tax")
        let tips = try chargeAllocation(total: session.tipAmount, mode: session.tipAllocationMode, participants: session.participants, bases: bases, keyPath: \.customTipAmount, label: "tip")
        let pre = session.participants.map { p in (p, (bases[p.id] ?? 0) + (taxes[p.id] ?? 0) + (tips[p.id] ?? 0)) }
        let rounded: [UUID: Decimal]
        switch session.roundingRule { case .exactCents: rounded = allocate(sum(pre.map(\.1)), weights: pre.map { ($0.0.id, $0.1) }); case .nearestDollar: rounded = Dictionary(uniqueKeysWithValues: pre.map { ($0.0.id, round($0.1, scale: 0, mode: .plain)) }); case .roundUpToDollar: rounded = Dictionary(uniqueKeysWithValues: pre.map { ($0.0.id, round($0.1, scale: 0, mode: .up)) }) }
        let results = pre.map { p, amount in ParticipantSplitResult(id: UUID(), participantID: p.id, participantName: p.name.isEmpty ? "Person" : p.name, baseAmount: round(bases[p.id] ?? 0), taxAmount: round(taxes[p.id] ?? 0), tipAmount: round(tips[p.id] ?? 0), roundingAdjustment: round((rounded[p.id] ?? amount) - amount), finalAmount: round(rounded[p.id] ?? amount), isPaid: p.isPaid, itemBreakdown: itemBreakdowns[p.id] ?? []) }
        let collected = sum(results.map(\.finalAmount))
        try require(collected, equals: session.total, message: "Split allocations must preserve the full collected total.")
        return SplitCalculationResult(id: UUID(), sessionID: session.id, session: session, participantResults: results, originalTotal: session.total, roundedCollectedTotal: collected, roundingDifference: round(collected - session.total), unallocatedAmount: round(session.subtotal - sum(bases.values)), createdAt: now)
    }
    private func chargeAllocation(total: Decimal, mode: ChargeAllocationMode, participants: [SplitParticipant], bases: [UUID: Decimal], keyPath: KeyPath<SplitParticipant, Decimal?>, label: String) throws -> [UUID: Decimal] { switch mode { case .proportional: let weights = participants.map { ($0.id, bases[$0.id] ?? 0) }; return sum(weights.map(\.1)) == 0 && total > 0 ? allocate(total, among: participants.map(\.id)) : allocate(total, weights: weights); case .equal: return allocate(total, among: participants.map(\.id)); case .custom: let vals = Dictionary(uniqueKeysWithValues: participants.map { ($0.id, $0[keyPath: keyPath] ?? 0) }); try require(sum(vals.values), equals: total, message: "Custom \(label) allocations must equal the full \(label) amount."); return vals } }
    private func allocate(_ total: Decimal, among ids: [UUID]) -> [UUID: Decimal] { allocate(total, weights: ids.map { ($0, 1) }) }
    private func allocate(_ total: Decimal, weights: [(UUID, Decimal)]) -> [UUID: Decimal] { let totalCents = cents(total); let weightSum = sum(weights.map(\.1)); guard weightSum > 0, !weights.isEmpty else { return Dictionary(uniqueKeysWithValues: weights.map { ($0.0, 0) }) }; var result: [UUID: Int] = [:]; var remainders: [(UUID, Decimal)] = []; var used = 0; for (id,w) in weights { let exact = Decimal(totalCents) * w / weightSum; let floorCents = NSDecimalNumber(decimal: exact).rounding(accordingToBehavior: NSDecimalNumberHandler(roundingMode: .down, scale: 0, raiseOnExactness: false, raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false)).intValue; result[id] = floorCents; used += floorCents; remainders.append((id, exact - Decimal(floorCents))) }; for (id,_) in remainders.sorted(by: { $0.1 == $1.1 ? $0.0.uuidString < $1.0.uuidString : $0.1 > $1.1 }).prefix(max(0,totalCents-used)) { result[id, default: 0] += 1 }; return Dictionary(uniqueKeysWithValues: result.map { ($0.key, Decimal($0.value) / 100) }) }
    private func cents(_ d: Decimal) -> Int { NSDecimalNumber(decimal: round(d)).multiplying(byPowerOf10: 2).intValue }
    private func round(_ v: Decimal, scale: Int = 2, mode: NSDecimalNumber.RoundingMode = .plain) -> Decimal { var value = v; var r = Decimal(); NSDecimalRound(&r, &value, scale, mode); return r }
    private func sum<S: Sequence>(_ values: S) -> Decimal where S.Element == Decimal { values.reduce(0,+) }
    private func require(_ lhs: Decimal, equals rhs: Decimal, message: String) throws { if absDecimal(lhs-rhs) > Decimal(string: "0.01")! { throw SplitCalculationError.allocationMismatch(message) } }
    private func absDecimal(_ d: Decimal) -> Decimal { d < 0 ? -d : d }
}
