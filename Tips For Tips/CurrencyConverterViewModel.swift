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
        Array(conversionRates.keys)
    }

    init() {
        fetchConversionRates()
    }

    func fetchConversionRates() {
        guard let url = URL(string: "\(baseURL)\(apiKey)/latest/USD") else { return }

        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data else {
                print("No data in response: \(error?.localizedDescription ?? "Unknown error")")
                return
            }

            do {
                let result = try JSONDecoder().decode(CurrencyResponse.self, from: data)
                DispatchQueue.main.async {
                    self.conversionRates = result.conversionRates
                }
            } catch {
                print("Error decoding JSON: \(error.localizedDescription)")
            }
        }.resume()
    }

    func convert() {
        guard let amount = Double(amount) else { return }
        let fromCurrency = currencyList[fromCurrencyIndex]
        let toCurrency = currencyList[toCurrencyIndex]

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
