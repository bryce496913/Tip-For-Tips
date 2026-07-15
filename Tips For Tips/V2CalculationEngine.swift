import Foundation

enum TipCalculationError: LocalizedError, Equatable {
    case missingService
    case missingBillAmount
    case invalidPeopleCount

    var errorDescription: String? {
        switch self {
        case .missingService: return "Choose the service you received."
        case .missingBillAmount: return "Enter a bill amount."
        case .invalidPeopleCount: return "Enter at least one person."
        }
    }
}

struct TipRecommendationEngine {
    var services: [TippingService] = TippingGuidance.services

    func calculate(input: TipCalculationInput, now: Date = Date()) throws -> TipCalculationResult {
        guard let service = services.first(where: { $0.id == input.serviceID }) else { throw TipCalculationError.missingService }
        guard input.peopleCount > 0 else { throw TipCalculationError.invalidPeopleCount }
        let baseAmount = try calculationBaseAmount(input)

        switch service.recommendation {
        case let .percentage(minimum, standard, maximum):
            let recommended = recommendedPercentage(minimum: minimum, standard: standard, maximum: maximum, quality: input.serviceQuality)
            let grossTip = roundedCurrency(baseAmount * recommended / 100)
            let included = input.gratuityStatus == .yes ? (input.includedGratuityAmount ?? 0) : 0
            let additionalTip = max(0, grossTip - included)
            let lower = TipAlternative(label: "Lower option", percentage: minimum, amount: roundedCurrency(baseAmount * minimum / 100), explanation: "Lower end of the customary range for this service.")
            let higherPercent = max(maximum, standard + 2)
            let higher = TipAlternative(label: "Higher option", percentage: higherPercent, amount: roundedCurrency(baseAmount * higherPercent / 100), explanation: "Higher option for exceptional service or extra effort.")
            return TipCalculationResult(id: UUID(), createdAt: now, input: input, recommendedPercentage: recommended, normalRange: DecimalRange(minimum: minimum, maximum: maximum), recommendedTipAmount: additionalTip, finalTotal: roundedCurrency((input.finalTotal ?? ((input.subtotal ?? baseAmount) + (input.tax ?? 0))) + additionalTip), lowerAlternative: lower, higherAlternative: higher, explanation: explanation(for: service, input: input, included: included, baseAmount: baseAmount))
        case let .fixedAmount(minimum, standard, maximum, unitDescription):
            let amount = standard ?? minimum ?? maximum ?? 0
            return TipCalculationResult(id: UUID(), createdAt: now, input: input, recommendedPercentage: nil, normalRange: nil, recommendedTipAmount: amount, finalTotal: roundedCurrency((input.finalTotal ?? ((input.subtotal ?? baseAmount) + (input.tax ?? 0))) + amount), lowerAlternative: minimum.map { TipAlternative(label: "Lower option", percentage: nil, amount: $0, explanation: unitDescription) }, higherAlternative: maximum.map { TipAlternative(label: "Higher option", percentage: nil, amount: $0, explanation: unitDescription) }, explanation: service.explanation)
        case let .optional(suggestedPercentage, explanation):
            let percent = suggestedPercentage ?? 0
            let amount = roundedCurrency(baseAmount * percent / 100)
            return TipCalculationResult(id: UUID(), createdAt: now, input: input, recommendedPercentage: suggestedPercentage, normalRange: nil, recommendedTipAmount: amount, finalTotal: roundedCurrency((input.finalTotal ?? ((input.subtotal ?? baseAmount) + (input.tax ?? 0))) + amount), lowerAlternative: nil, higherAlternative: nil, explanation: explanation)
        case let .informational(explanation):
            return TipCalculationResult(id: UUID(), createdAt: now, input: input, recommendedPercentage: nil, normalRange: nil, recommendedTipAmount: 0, finalTotal: input.finalTotal ?? input.subtotal ?? 0, lowerAlternative: nil, higherAlternative: nil, explanation: explanation)
        }
    }

    private func calculationBaseAmount(_ input: TipCalculationInput) throws -> Decimal {
        switch input.calculationBasis {
        case .subtotalBeforeTax:
            if let subtotal = input.subtotal { return subtotal }
            if let finalTotal = input.finalTotal, let tax = input.tax { return max(0, finalTotal - tax) }
        case .finalTotalAfterTax:
            if let finalTotal = input.finalTotal { return finalTotal }
            if let subtotal = input.subtotal { return subtotal + (input.tax ?? 0) }
        }
        throw TipCalculationError.missingBillAmount
    }

    private func recommendedPercentage(minimum: Decimal, standard: Decimal, maximum: Decimal, quality: ServiceQuality) -> Decimal {
        switch quality {
        case .poor: return minimum
        case .standard: return standard
        case .good: return maximum
        case .exceptional: return maximum + 2
        }
    }

    private func explanation(for service: TippingService, input: TipCalculationInput, included: Decimal, baseAmount: Decimal) -> String {
        var parts = [service.explanation]
        parts.append(input.calculationBasis == .subtotalBeforeTax ? "This uses the pre-tax subtotal, which is traditionally acceptable." : "This uses the final post-tax total, as many payment terminals do.")
        if input.gratuityStatus == .yes { parts.append("An included gratuity or charge of \(included) was considered before recommending any extra tip.") }
        if input.gratuityStatus == .unsure { parts.append("If the receipt lists gratuity, service charge, hospitality charge or administrative fee, review it before adding extra tip.") }
        parts.append("Calculation base: \(baseAmount) \(input.currencyCode).")
        return parts.joined(separator: " ")
    }

    private func roundedCurrency(_ value: Decimal) -> Decimal {
        var value = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 2, .plain)
        return rounded
    }
}
