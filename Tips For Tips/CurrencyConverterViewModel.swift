//
//  CurrencyConverterViewModel.swift
//  Tips For Tips
//
//  Created by Aditi Abrol on 19/4/24.
//

import Foundation

class CurrencyConverterViewModel: ObservableObject {
    @Published var amount: String = ""
    @Published var fromCurrencyIndex: Int = 0
    @Published var toCurrencyIndex: Int = 0
    @Published var convertedAmount: String = ""

    private let apiKey = "a875c3d6fa9b411b59a140a9"
    private let baseURL = "https://v6.exchangerate-api.com/v6/"

    private var conversionRates: [String: Double] = [:]
    var currencyList: [String] {
        Array(conversionRates.keys).sorted()
    }

    init() {
        fetchConversionRates()
    }

    func fetchConversionRates() {
        guard let url = URL(string: "\(baseURL)\(apiKey)/latest/USD") else { return }

        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data else {
                return
            }

            do {
                let result = try JSONDecoder().decode(CurrencyResponse.self, from: data)
                DispatchQueue.main.async {
                    self.conversionRates = result.conversionRates
                }
            } catch {
                return
            }
        }.resume()
    }

    func convert() {
        let currencies = currencyList
        guard let amount = Double(amount), amount >= 0,
              currencies.indices.contains(fromCurrencyIndex),
              currencies.indices.contains(toCurrencyIndex) else { return }

        let toCurrency = currencies[toCurrencyIndex]
        guard let rate = conversionRates[toCurrency] else { return }
        let convertedAmount = amount * rate
        self.convertedAmount = "\(convertedAmount) \(toCurrency)"
    }
}

struct CurrencyResponse: Codable {
    let conversionRates: [String: Double]

    enum CodingKeys: String, CodingKey {
        case conversionRates = "conversion_rates"
    }
}
