import Foundation
import SwiftUI

struct Currency: Identifiable, Hashable {
    let code: String
    let name: String
    let symbol: String
    let flag: String?
    var id: String { code }

    /// Curated app list filtered to Frankfurter-supported symbols documented by the provider.
    static let supported: [Currency] = curated.filter { FrankfurterSupportedCurrencies.codes.contains($0.code) }
    static let unsupportedCuratedCodes: [String] = curated.map(\.code).filter { !FrankfurterSupportedCurrencies.codes.contains($0) }

    private static let curated: [Currency] = [
        .init(code: "USD", name: "US Dollar", symbol: "$", flag: "🇺🇸"), .init(code: "EUR", name: "Euro", symbol: "€", flag: "🇪🇺"), .init(code: "GBP", name: "British Pound", symbol: "£", flag: "🇬🇧"), .init(code: "JPY", name: "Japanese Yen", symbol: "¥", flag: "🇯🇵"), .init(code: "AUD", name: "Australian Dollar", symbol: "$", flag: "🇦🇺"), .init(code: "CAD", name: "Canadian Dollar", symbol: "$", flag: "🇨🇦"), .init(code: "CHF", name: "Swiss Franc", symbol: "CHF", flag: "🇨🇭"), .init(code: "CNY", name: "Chinese Yuan", symbol: "¥", flag: "🇨🇳"), .init(code: "INR", name: "Indian Rupee", symbol: "₹", flag: "🇮🇳"), .init(code: "MXN", name: "Mexican Peso", symbol: "$", flag: "🇲🇽"), .init(code: "BRL", name: "Brazilian Real", symbol: "R$", flag: "🇧🇷"), .init(code: "KRW", name: "South Korean Won", symbol: "₩", flag: "🇰🇷"), .init(code: "NZD", name: "New Zealand Dollar", symbol: "$", flag: "🇳🇿"), .init(code: "SEK", name: "Swedish Krona", symbol: "kr", flag: "🇸🇪"), .init(code: "NOK", name: "Norwegian Krone", symbol: "kr", flag: "🇳🇴"), .init(code: "SGD", name: "Singapore Dollar", symbol: "$", flag: "🇸🇬"), .init(code: "HKD", name: "Hong Kong Dollar", symbol: "$", flag: "🇭🇰"), .init(code: "ZAR", name: "South African Rand", symbol: "R", flag: "🇿🇦")
    ]

    static func currency(for code: String) -> Currency { supported.first { $0.code == code } ?? supported[0] }
}

enum FrankfurterSupportedCurrencies { static let codes: Set<String> = ["AUD","BGN","BRL","CAD","CHF","CNY","CZK","DKK","EUR","GBP","HKD","HUF","IDR","ILS","INR","ISK","JPY","KRW","MXN","MYR","NOK","NZD","PHP","PLN","RON","SEK","SGD","THB","TRY","USD","ZAR"] }

enum ConverterLoadingState: Equatable { case idle, loading, success, failure(String) }

struct ConversionResult: Equatable {
    let enteredAmount: Decimal
    let convertedAmount: Decimal
    let rate: Decimal
    let from: Currency
    let to: Currency
    let rateDate: Date?
    let fetchedAt: Date
    let isCached: Bool
}

struct CachedExchangeRate: Equatable { let rate: Decimal; let rateDate: Date?; let fetchedAt: Date }

enum CurrencyConverterError: LocalizedError, Equatable {
    case invalidAmount, unsupportedCurrency, invalidResponse, missingRate, authentication, network, decoding
    var errorDescription: String? {
        switch self {
        case .invalidAmount: return "Enter a positive amount to convert."
        case .unsupportedCurrency: return "That currency is not supported by the exchange-rate provider."
        case .invalidResponse, .missingRate, .decoding, .network: return "Unable to load the latest exchange rate. Check your connection and try again."
        case .authentication: return "The exchange-rate provider rejected this request."
        }
    }
}

struct ExchangeRateResponse: Decodable { let amount: Double; let base: String; let date: String; let rates: [String: Double] }

protocol CurrencyRateProviding { func rate(from: Currency, to: Currency) async throws -> (Decimal, Date?) }

struct ExchangeRateService: CurrencyRateProviding {
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }
    func rate(from: Currency, to: Currency) async throws -> (Decimal, Date?) {
        guard Currency.supported.contains(from), Currency.supported.contains(to) else { throw CurrencyConverterError.unsupportedCurrency }
        guard from.code != to.code else { return (1, nil) }
        var components = URLComponents(string: "https://api.frankfurter.app/latest")
        components?.queryItems = [URLQueryItem(name: "from", value: from.code), URLQueryItem(name: "to", value: to.code)]
        guard let url = components?.url else { throw CurrencyConverterError.invalidResponse }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse else { throw CurrencyConverterError.invalidResponse }
            guard (200...299).contains(http.statusCode) else { throw http.statusCode == 401 || http.statusCode == 403 ? CurrencyConverterError.authentication : CurrencyConverterError.invalidResponse }
            let decoded = try JSONDecoder().decode(ExchangeRateResponse.self, from: data)
            guard let rate = decoded.rates[to.code], rate.isFinite, rate > 0 else { throw CurrencyConverterError.missingRate }
            let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.locale = Locale(identifier: "en_US_POSIX")
            return (Decimal(rate), formatter.date(from: decoded.date))
        } catch let error as CurrencyConverterError { throw error }
        catch is DecodingError { throw CurrencyConverterError.decoding }
        catch { throw CurrencyConverterError.network }
    }
}

@MainActor
final class CurrencyConverterViewModel: ObservableObject {
    static let cacheFreshnessInterval: TimeInterval = 600
    @Published var amountText = "" { didSet { if amountText != oldValue { invalidateConversionResult() } } }
    @Published var sourceCurrency = Currency.currency(for: "USD") { didSet { if sourceCurrency != oldValue { invalidateConversionResult() } } }
    @Published var destinationCurrency = Currency.currency(for: "EUR") { didSet { if destinationCurrency != oldValue { invalidateConversionResult() } } }
    @Published private(set) var result: ConversionResult?
    @Published private(set) var state: ConverterLoadingState = .idle
    @Published var contextValues: [ConvertibleAmount] = []
    @Published private(set) var multiValueLines: [MultiValueConversionLine] = []

    var currencies: [Currency] { sortedCurrencies() }
    private let service: CurrencyRateProviding
    private var conversionTask: Task<Void, Never>?
    private var activeRequestID = UUID()
    private var cache: [String: CachedExchangeRate] = [:]

    init(service: CurrencyRateProviding = ExchangeRateService(), context: CurrencyConversionContext? = nil) { self.service = service; if let context { sourceCurrency = Currency.currency(for: context.sourceCurrencyCode); contextValues = context.values; amountText = context.values.first.map { "\($0.amount)" } ?? "" } }
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

    func swapCurrencies() { let old = sourceCurrency; sourceCurrency = destinationCurrency; destinationCurrency = old; invalidateConversionResult() }
    var favoriteCodes: [String] { (UserDefaults.standard.string(forKey: "currency.favoriteCodes") ?? "USD").split(separator: ",").map(String.init).filter { FrankfurterSupportedCurrencies.codes.contains($0) } }
    var recentPairs: [CurrencyPair] { (UserDefaults.standard.string(forKey: "currency.recentPairs") ?? "").split(separator: ",").compactMap { item in let parts = item.split(separator: "-").map(String.init); guard parts.count == 2, FrankfurterSupportedCurrencies.codes.contains(parts[0]), FrankfurterSupportedCurrencies.codes.contains(parts[1]) else { return nil }; return CurrencyPair(sourceCode: parts[0], destinationCode: parts[1]) } }
    func isFavorite(_ currency: Currency) -> Bool { favoriteCodes.contains(currency.code) }
    func toggleFavorite(_ currency: Currency) { guard FrankfurterSupportedCurrencies.codes.contains(currency.code) else { return }; var codes = favoriteCodes.filter { $0 != currency.code }; if !isFavorite(currency) { codes.append(currency.code) }; if !codes.contains("USD") { codes.insert("USD", at: 0) }; UserDefaults.standard.set(codes.joined(separator: ","), forKey: "currency.favoriteCodes"); objectWillChange.send() }
    func usePair(_ pair: CurrencyPair) { sourceCurrency = Currency.currency(for: pair.sourceCode); destinationCurrency = Currency.currency(for: pair.destinationCode) }
    func clearRecentPairs() { UserDefaults.standard.set("", forKey: "currency.recentPairs"); objectWillChange.send() }

    func convert() {
        guard let amount = parsedAmount, amount > 0 else { state = .failure(CurrencyConverterError.invalidAmount.localizedDescription); result = nil; return }
        guard Currency.supported.contains(sourceCurrency), Currency.supported.contains(destinationCurrency) else { state = .failure(CurrencyConverterError.unsupportedCurrency.localizedDescription); result = nil; return }
        conversionTask?.cancel()
        let requestID = UUID(); activeRequestID = requestID
        let from = sourceCurrency, to = destinationCurrency, key = "\(from.code)-\(to.code)", amountSnapshot = amountText
        state = .loading; result = nil
        conversionTask = Task { [service] in
            do {
                let cachedEntry = cache[key]
                let rate: Decimal; let rateDate: Date?; let fetchedAt: Date; let cached: Bool
                if from.code == to.code { rate = 1; rateDate = nil; fetchedAt = Date(); cached = false }
                else if let c = cachedEntry, Date().timeIntervalSince(c.fetchedAt) < Self.cacheFreshnessInterval { rate = c.rate; rateDate = c.rateDate; fetchedAt = c.fetchedAt; cached = true }
                else { let fresh = try await service.rate(from: from, to: to); rate = fresh.0; rateDate = fresh.1; fetchedAt = Date(); cached = false }
                guard !Task.isCancelled, requestID == activeRequestID, amountText == amountSnapshot, sourceCurrency == from, destinationCurrency == to else { return }
                if !cached && from.code != to.code { cache[key] = CachedExchangeRate(rate: rate, rateDate: rateDate, fetchedAt: fetchedAt) }
                let values = contextValues.isEmpty ? [ConvertibleAmount(id: "amount", label: "Amount", amount: amount)] : contextValues
                multiValueLines = values.map { MultiValueConversionLine(id: $0.id, label: $0.label, sourceAmount: $0.amount, convertedAmount: $0.amount * rate) }
                result = ConversionResult(enteredAmount: amount, convertedAmount: amount * rate, rate: rate, from: from, to: to, rateDate: rateDate, fetchedAt: fetchedAt, isCached: cached)
                rememberSuccessfulPair(from: from, to: to)
                state = .success
            } catch {
                guard !Task.isCancelled, requestID == activeRequestID else { return }
                result = nil; state = .failure((error as? CurrencyConverterError)?.localizedDescription ?? CurrencyConverterError.network.localizedDescription)
            }
        }
    }

    func formattedCurrency(_ value: Decimal, code: String) -> String { let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = code; f.maximumFractionDigits = 2; f.minimumFractionDigits = 2; return f.string(from: value as NSDecimalNumber) ?? "\(value) \(code)" }
    func formattedRate(_ rate: Decimal) -> String { let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 6; f.minimumFractionDigits = 2; return f.string(from: rate as NSDecimalNumber) ?? "\(rate)" }

    private func invalidateConversionResult() { conversionTask?.cancel(); activeRequestID = UUID(); result = nil; multiValueLines = []; state = .idle }
    private func sortedCurrencies() -> [Currency] { let favs = Set(favoriteCodes); return Currency.supported.sorted { a, b in let af = favs.contains(a.code), bf = favs.contains(b.code); if af != bf { return af }; return a.code < b.code } }
    private func rememberSuccessfulPair(from: Currency, to: Currency) { guard from.code != to.code else { return }; let pair = "\(from.code)-\(to.code)"; var pairs = (UserDefaults.standard.string(forKey: "currency.recentPairs") ?? "").split(separator: ",").map(String.init).filter { $0 != pair }; pairs.insert(pair, at: 0); UserDefaults.standard.set(pairs.prefix(20).joined(separator: ","), forKey: "currency.recentPairs") }
}
