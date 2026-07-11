import SwiftUI

struct CurrencyConverter: View {
    @State private var baseCurrency = "USD"
    @State private var amount = ""
    @State private var selectedCurrency = "USD"
    @State private var convertedAmount = ""
    @State private var currencyList: [String] = []
    @State private var isShowingBaseCurrencySelection = false
    @State private var isShowingSelectedCurrencySelection = false
    @State private var errorMessage: String?

    private let apiURL = "https://v6.exchangerate-api.com/v6/a875c3d6fa9b411b59a140a9/latest/"
    private var amountValue: Double? { guard let value = Double(amount), value >= 0 else { return nil }; return value }

    var body: some View {
        AppScreen {
            ScrollView {
                VStack(spacing: 18) {
                    Image("CurrencyConverter")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 190, height: 190)
                        .accessibilityHidden(true)
                    ScreenTitle(text: "Currency Converter")
                    ThemedCard {
                        Text("Amount") .appFont(.h2)
                        TextField("Enter Amount", text: $amount)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(AppTextFieldStyle())
                            .multilineTextAlignment(.center)
                    }
                    ThemedCard {
                        SecondaryButton(title: "Starting Currency: \(baseCurrency)") { isShowingBaseCurrencySelection = true }
                        SecondaryButton(title: "Convert To: \(selectedCurrency)") { isShowingSelectedCurrencySelection = true }
                        PrimaryButton(title: "Convert", isDisabled: amountValue == nil || currencyList.isEmpty) { fetchConversionRate() }
                    }
                    ThemedCard {
                        Text("\(amount) \(baseCurrency) = \(convertedAmount) \(selectedCurrency)")
                            .appFont(.h2)
                            .foregroundStyle(AppTheme.highlight)
                        if let errorMessage { Text(errorMessage).appFont(.paragraph).foregroundStyle(AppTheme.highlight) }
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("Currency Converter")
        .navigationBarTitleDisplayMode(.inline)
        .hideKeyboardToolbar()
        .task { fetchCurrencyList() }
        .sheet(isPresented: $isShowingBaseCurrencySelection) { CurrencyPicker(title: "Starting Currency", selection: $baseCurrency, currencies: currencyList) { fetchCurrencyList() } }
        .sheet(isPresented: $isShowingSelectedCurrencySelection) { CurrencyPicker(title: "Convert To", selection: $selectedCurrency, currencies: currencyList) }
    }

    private func fetchCurrencyList() {
        guard let url = URL(string: apiURL + baseCurrency) else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data,
                  let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let conversionRates = result["conversion_rates"] as? [String: Double] else {
                DispatchQueue.main.async { errorMessage = "Unable to load currencies." }
                return
            }
            DispatchQueue.main.async {
                currencyList = conversionRates.keys.sorted()
                if !currencyList.contains(selectedCurrency) { selectedCurrency = currencyList.first ?? "USD" }
                errorMessage = nil
            }
        }.resume()
    }

    private func fetchConversionRate() {
        guard let amountValue, let url = URL(string: apiURL + baseCurrency) else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data,
                  let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let conversionRates = result["conversion_rates"] as? [String: Double],
                  let rate = conversionRates[selectedCurrency] else {
                DispatchQueue.main.async { errorMessage = "Unable to convert right now." }
                return
            }
            DispatchQueue.main.async {
                convertedAmount = String(format: "%.2f", amountValue * rate)
                errorMessage = nil
            }
        }.resume()
    }
}

private struct CurrencyPicker: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @Binding var selection: String
    let currencies: [String]
    var onDone: (() -> Void)?

    var body: some View {
        NavigationStack {
            AppScreen {
                Picker(title, selection: $selection) {
                    ForEach(currencies, id: \.self) { Text($0).foregroundStyle(AppTheme.text) }
                }
                .pickerStyle(.wheel)
            }
            .navigationTitle(title)
            .toolbar { Button("Done") { onDone?(); dismiss() } }
        }
        .presentationDetents([.medium])
    }
}

#Preview { CurrencyConverter() }
