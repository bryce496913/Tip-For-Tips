//
//  CurrencyConverter.swift
//  Tips For Tips
//
//  Created by Aditi Abrol on 7/4/24.
//

import SwiftUI

struct CurrencyConverter: View {
    @State private var baseCurrency = "USD"
    @State private var amount = ""
    @State private var selectedCurrency = "USD"
    @State private var convertedAmount = ""
    @State private var conversionRate = 1.0
    @State private var currencyList: [String] = []
    @State private var isShowingBaseCurrencySelection = false
    @State private var isShowingSelectedCurrencySelection = false

    //private let apiKey = "a875c3d6fa9b411b59a140a9"
    private let apiURL = "https://v6.exchangerate-api.com/v6/a875c3d6fa9b411b59a140a9/latest/"

    var body: some View {
        ZStack {
            Color.appBlack.edgesIgnoringSafeArea(.all)
            
            VStack {
                VStack {
                    Image("CurrencyConverter")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 250, height: 250)
                    
                    HStack(spacing: 0) {
                        Text("Currency ").foregroundColor(Color.appBlue)
                        Text("Converter").foregroundColor(Color.appGold)
                    }
                    .font(.largeTitle)
                }
                
                TextField("Enter Amount", text: $amount)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .overlay(
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(Color.appBlue, lineWidth: 5)
                    )
                    .padding(.horizontal, 50)
                    .font(.title)
                    .multilineTextAlignment(.center)
                    .toolbar {
                        ToolbarItem(placement: .keyboard) {
                            Button("Done") {
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            }
                        }
                    }
                
                Spacer()
                
                Button(action: {
                    isShowingBaseCurrencySelection = true
                }) {
                    Text("Starting Currency: \(baseCurrency)")
                        .font(.title)
                        .foregroundColor(Color.appBlue)
                }
                .padding()
                .popover(isPresented: $isShowingBaseCurrencySelection, content: {
                    baseCurrencyPicker()
                })
                
                Button(action: {
                    isShowingSelectedCurrencySelection = true
                }) {
                    Text("Convert To: \(selectedCurrency)")
                        .font(.title)
                        .foregroundColor(Color.appGold)
                }
                .padding()
                .popover(isPresented: $isShowingSelectedCurrencySelection, content: {
                    selectedCurrencyPicker()
                })
                
                Spacer()
                
                Button("Convert") {
                    fetchConversionRate()
                }
                .padding()
                .background(Color.appDarkBlue)
                .foregroundColor(.white)
                .cornerRadius(15)
                .font(.title)
                
                Spacer()
                
                Text("\(amount) \(baseCurrency) = \(convertedAmount) \(selectedCurrency)")
                    .padding()
                    .font(.title)
                    .foregroundColor(Color.appGreen)
            }
            .onAppear {
                fetchCurrencyList()
            }
        }
    }

    private func baseCurrencyPicker() -> some View {
        VStack {
            Picker("Base Currency", selection: $baseCurrency) {
                ForEach(currencyList, id: \.self) { currency in
                    Text(currency)
                }
            }
            .pickerStyle(WheelPickerStyle())
            .labelsHidden()

            Button("Done") {
                isShowingBaseCurrencySelection = false
            }
            .padding()
        }
        .frame(height: UIScreen.main.bounds.height / 2)
        .padding()
    }

    private func selectedCurrencyPicker() -> some View {
        VStack {
            Picker("Convert To", selection: $selectedCurrency) {
                ForEach(currencyList, id: \.self) { currency in
                    Text(currency)
                }
            }
            .pickerStyle(WheelPickerStyle())
            .labelsHidden()

            Button("Done") {
                isShowingSelectedCurrencySelection = false
            }
            .padding()
        }
        .frame(height: UIScreen.main.bounds.height / 2)
        .padding()
    }

    private func fetchCurrencyList() {
        guard let url = URL(string: apiURL + baseCurrency) else { return }

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let data = data {
                do {
                    let result = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                    if let conversionRates = result?["conversion_rates"] as? [String: Double] {
                        currencyList = conversionRates.keys.sorted()
                        selectedCurrency = currencyList.first ?? ""
                    }
                } catch {
                    print("Failed to decode: \(error.localizedDescription)")
                }
            }
        }.resume()
    }

    private func fetchConversionRate() {
        guard let url = URL(string: apiURL + baseCurrency) else { return }

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let data = data {
                do {
                    let result = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                    if let conversionRates = result?["conversion_rates"] as? [String: Double] {
                        if let rate = conversionRates[selectedCurrency] {
                            conversionRate = rate
                            if let amountValue = Double(amount) {
                                let converted = amountValue * conversionRate
                                convertedAmount = String(format: "%.2f", converted)
                            }
                        }
                    }
                } catch {
                    print("Failed to decode: \(error.localizedDescription)")
                }
            }
        }.resume()
    }
}

struct CurrencyConverter_Previews: PreviewProvider {
    static var previews: some View {
        CurrencyConverter()
    }
}
