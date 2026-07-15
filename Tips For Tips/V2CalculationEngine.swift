import Foundation

enum TipCalculationError: LocalizedError, Equatable {
    case missingService
    case missingBillAmount
    case invalidPeopleCount
    case negativeAmount(String)
    case missingServiceDetail(String)

    var errorDescription: String? {
        switch self {
        case .missingService: return "Choose the service you received."
        case .missingBillAmount: return "Enter a bill amount."
        case .invalidPeopleCount: return "Enter at least one person."
        case .negativeAmount(let field): return "\(field) cannot be negative."
        case .missingServiceDetail(let field): return "Enter \(field)."
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
    private func calculationBaseAmount(_ input: TipCalculationInput) throws -> Decimal { switch input.calculationBasis { case .subtotalBeforeTax: if let subtotal = input.subtotal { return subtotal }; if let total = input.finalTotal, let tax = input.tax { return total - tax }; case .finalTotalAfterTax: if let total = input.finalTotal { return total }; if let subtotal = input.subtotal { return subtotal + (input.tax ?? 0) } }; throw TipCalculationError.missingBillAmount }
    private func currentReceiptTotal(input: TipCalculationInput, baseAmount: Decimal) -> Decimal { input.finalTotal ?? ((input.subtotal ?? baseAmount) + (input.tax ?? 0)) }
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
