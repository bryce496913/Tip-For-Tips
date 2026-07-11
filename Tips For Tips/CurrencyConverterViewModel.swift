import Foundation
import SwiftUI

struct Currency: Identifiable, Hashable {
    let code: String
    let name: String
    let symbol: String
    let flag: String?
    var id: String { code }

    static let supported: [Currency] = [
        .init(code: "USD", name: "US Dollar", symbol: "$", flag: "🇺🇸"), .init(code: "EUR", name: "Euro", symbol: "€", flag: "🇪🇺"), .init(code: "GBP", name: "British Pound", symbol: "£", flag: "🇬🇧"), .init(code: "JPY", name: "Japanese Yen", symbol: "¥", flag: "🇯🇵"), .init(code: "AUD", name: "Australian Dollar", symbol: "$", flag: "🇦🇺"), .init(code: "CAD", name: "Canadian Dollar", symbol: "$", flag: "🇨🇦"), .init(code: "CHF", name: "Swiss Franc", symbol: "CHF", flag: "🇨🇭"), .init(code: "CNY", name: "Chinese Yuan", symbol: "¥", flag: "🇨🇳"), .init(code: "INR", name: "Indian Rupee", symbol: "₹", flag: "🇮🇳"), .init(code: "MXN", name: "Mexican Peso", symbol: "$", flag: "🇲🇽"), .init(code: "BRL", name: "Brazilian Real", symbol: "R$", flag: "🇧🇷"), .init(code: "KRW", name: "South Korean Won", symbol: "₩", flag: "🇰🇷"), .init(code: "NZD", name: "New Zealand Dollar", symbol: "$", flag: "🇳🇿"), .init(code: "SEK", name: "Swedish Krona", symbol: "kr", flag: "🇸🇪"), .init(code: "NOK", name: "Norwegian Krone", symbol: "kr", flag: "🇳🇴"), .init(code: "SGD", name: "Singapore Dollar", symbol: "$", flag: "🇸🇬"), .init(code: "HKD", name: "Hong Kong Dollar", symbol: "$", flag: "🇭🇰"), .init(code: "ZAR", name: "South African Rand", symbol: "R", flag: "🇿🇦")
    ]

    static func currency(for code: String) -> Currency { supported.first { $0.code == code } ?? supported[0] }
}

enum ConverterLoadingState: Equatable { case idle, loading, success, failure(String) }

struct ConversionResult: Equatable {
    let enteredAmount: Decimal
    let convertedAmount: Decimal
    let rate: Decimal
    let from: Currency
    let to: Currency
    let timestamp: Date
    let isCached: Bool
}

enum CurrencyConverterError: LocalizedError, Equatable {
    case invalidAmount, unsupportedCurrency, invalidResponse, missingRate, authentication, network, decoding
    var errorDescription: String? {
        switch self {
        case .invalidAmount:
            return "Enter a positive amount to convert."
        case .unsupportedCurrency:
            return "That currency is not supported by the exchange-rate provider."
        case .invalidResponse, .missingRate, .decoding:
            return "Unable to load the latest exchange rate. Check your connection and try again."
        case .authentication:
            return "The exchange-rate provider rejected this request."
        case .network:
            return "Unable to load the latest exchange rate. Check your connection and try again."
        }
    }
}

struct ExchangeRateResponse: Decodable { let amount: Double; let base: String; let date: String; let rates: [String: Double] }

struct ExchangeRateService {
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    // Frankfurter is a public, keyless API backed by European Central Bank reference rates: https://www.frankfurter.app/docs/
    func rate(from: Currency, to: Currency) async throws -> (Decimal, Date?) {
        guard from.code != to.code else { return (1, Date()) }
        var components = URLComponents(string: "https://api.frankfurter.app/latest")
        components?.queryItems = [URLQueryItem(name: "from", value: from.code), URLQueryItem(name: "to", value: to.code)]
        guard let url = components?.url else { throw CurrencyConverterError.invalidResponse }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse else { throw CurrencyConverterError.invalidResponse }
            guard (200...299).contains(http.statusCode) else { throw http.statusCode == 401 || http.statusCode == 403 ? CurrencyConverterError.authentication : CurrencyConverterError.invalidResponse }
            let decoded: ExchangeRateResponse
            do { decoded = try JSONDecoder().decode(ExchangeRateResponse.self, from: data) } catch { throw CurrencyConverterError.decoding }
            guard let rate = decoded.rates[to.code], rate.isFinite, rate > 0 else { throw CurrencyConverterError.missingRate }
            let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.locale = Locale(identifier: "en_US_POSIX")
            return (Decimal(rate), formatter.date(from: decoded.date))
        } catch let error as CurrencyConverterError { throw error }
        catch { throw CurrencyConverterError.network }
    }
}

@MainActor
final class CurrencyConverterViewModel: ObservableObject {
    @Published var amountText = ""
    @Published var sourceCurrency = Currency.currency(for: "USD") { didSet { clearResultIfPairChanged(oldFrom: oldValue, oldTo: destinationCurrency) } }
    @Published var destinationCurrency = Currency.currency(for: "EUR") { didSet { clearResultIfPairChanged(oldFrom: sourceCurrency, oldTo: oldValue) } }
    @Published private(set) var result: ConversionResult?
    @Published private(set) var state: ConverterLoadingState = .idle

    let currencies = Currency.supported
    private let service: ExchangeRateService
    private var conversionTask: Task<Void, Never>?
    private var cache: [String: (rate: Decimal, timestamp: Date)] = [:]

    init(service: ExchangeRateService = ExchangeRateService()) { self.service = service }

    var parsedAmount: Decimal? { Self.parseAmount(amountText) }
    var canConvert: Bool { if case .loading = state { return false }; guard let amount = parsedAmount else { return false }; return amount > 0 }

    static func parseAmount(_ text: String, locale: Locale = .current) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("-") else { return nil }
        let formatter = NumberFormatter(); formatter.locale = locale; formatter.numberStyle = .decimal; formatter.generatesDecimalNumbers = true
        if let decimal = formatter.number(from: trimmed) as? NSDecimalNumber, decimal.decimalValue >= 0 { return decimal.decimalValue }
        let fallback = trimmed.replacingOccurrences(of: locale.decimalSeparator ?? ".", with: ".")
        guard let value = Decimal(string: fallback), value >= 0 else { return nil }
        return value
    }

    func swapCurrencies() { let old = sourceCurrency; sourceCurrency = destinationCurrency; destinationCurrency = old; result = nil; state = .idle }

    func convert() {
        guard let amount = parsedAmount, amount > 0 else { state = .failure(CurrencyConverterError.invalidAmount.localizedDescription); result = nil; return }
        conversionTask?.cancel()
        let from = sourceCurrency, to = destinationCurrency, key = "\(from.code)-\(to.code)"
        state = .loading; result = nil
        conversionTask = Task { [service] in
            do {
                let rate: Decimal; let timestamp: Date; let cached: Bool
                if from.code == to.code { rate = 1; timestamp = Date(); cached = false }
                else if let cachedRate = cache[key], Date().timeIntervalSince(cachedRate.timestamp) < 600 { rate = cachedRate.rate; timestamp = cachedRate.timestamp; cached = true }
                else { let fresh = try await service.rate(from: from, to: to); rate = fresh.0; timestamp = fresh.1 ?? Date(); cached = false }
                guard !Task.isCancelled else { return }
                if !cached && from.code != to.code { cache[key] = (rate, timestamp) }
                result = ConversionResult(enteredAmount: amount, convertedAmount: amount * rate, rate: rate, from: from, to: to, timestamp: timestamp, isCached: cached)
                state = .success
            } catch {
                guard !Task.isCancelled else { return }
                result = nil
                state = .failure((error as? CurrencyConverterError)?.localizedDescription ?? CurrencyConverterError.network.localizedDescription)
            }
        }
    }

    func formattedCurrency(_ value: Decimal, code: String) -> String {
        let formatter = NumberFormatter(); formatter.numberStyle = .currency; formatter.currencyCode = code; formatter.maximumFractionDigits = 2; formatter.minimumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value) \(code)"
    }

    func formattedRate(_ rate: Decimal) -> String {
        let formatter = NumberFormatter(); formatter.numberStyle = .decimal; formatter.maximumFractionDigits = 6; formatter.minimumFractionDigits = 2
        return formatter.string(from: rate as NSDecimalNumber) ?? "\(rate)"
    }

    private func clearResultIfPairChanged(oldFrom: Currency, oldTo: Currency) { if result != nil && (oldFrom != sourceCurrency || oldTo != destinationCurrency) { result = nil; state = .idle } }
}
