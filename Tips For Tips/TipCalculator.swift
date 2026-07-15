import SwiftUI

struct TipCalculator: View {
    @State private var selectedServiceIndex = 0
    @State private var totalBill = ""
    @State private var tipAmount = ""
    @State private var isPercentageSelected = true
    @State private var isServicePickerPresented = false
    @State private var didCalculate = false

    private let services = ["Restaurant with table service", "Bars", "Yellow Taxi", "Uber/Lyft driver", "Food delivery", "Shuttle driver", "Doorman", "Porter", "Housekeeping", "Room Service", "Tour Guides", "Tour Bus Drivers", "Spa", "Hairdressers/Barbers", "Nail Salon"]
    private func decimalValue(_ text: String) -> Double? {
        let formatter = NumberFormatter(); formatter.numberStyle = .decimal; formatter.locale = .current
        if let n = formatter.number(from: text), n.doubleValue >= 0 { return n.doubleValue }
        if let n = Double(text), n >= 0 { return n }
        return nil
    }

    private func reset() { totalBill = ""; tipAmount = ""; isPercentageSelected = true; didCalculate = false }

    private let recommendedTips: [String: String] = ["Restaurant with table service": "15-20%", "Bars": "15-20% or $1-$2 per drink", "Yellow Taxi": "10-20%", "Uber/Lyft driver": "10-20%", "Food delivery": "15-20%", "Shuttle driver": "$2-$5 per person", "Doorman": "$1-$5", "Porter": "$1-$2 per bag", "Housekeeping": "$2-$5 per night", "Room Service": "15-20%", "Tour Guides": "$2-$5 per participating person for local tours. 15-20% of the ticket price for a day trip", "Tour Bus Drivers": "$2-$5 per person", "Spa": "15-20%", "Hairdressers/Barbers": "15-20%", "Nail Salon": "15-20%"]

    private var selectedService: String { services.indices.contains(selectedServiceIndex) ? services[selectedServiceIndex] : services[0] }
    private var recommendedTip: String { recommendedTips[selectedService] ?? "" }
    private var billValue: Double { max(decimalValue(totalBill) ?? 0, 0) }
    private var tipValue: Double { max(decimalValue(tipAmount) ?? 0, 0) }
    private var canCalculate: Bool { decimalValue(totalBill) != nil && decimalValue(tipAmount) != nil }
    private var calculatedTip: Double { isPercentageSelected ? billValue * tipValue / 100 : tipValue }
    private var totalAmount: Double { billValue + calculatedTip }

    var body: some View {
        AppScreen {
            ScrollView {
                VStack(spacing: 18) {
                    Image("TipCalculator")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 190, height: 190)
                        .accessibilityHidden(true)
                    ScreenTitle(text: "Tip Calculator")

                    ThemedCard {
                        Text("Service") .appFont(.h2)
                        SecondaryButton(title: selectedService) { isServicePickerPresented = true }
                        Text("Recommended Tip: \(recommendedTip)")
                            .appFont(.paragraph)
                            .foregroundStyle(AppTheme.text)
                    }

                    ThemedCard {
                        Text("Bill") .appFont(.h2)
                        TextField("Bill Amount", text: $totalBill)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(AppTextFieldStyle())
                            .multilineTextAlignment(.center)
                            .accessibilityLabel("Bill amount")
                        HStack {
                            RadioButton(title: "Percent", isSelected: isPercentageSelected) { isPercentageSelected = true }
                            RadioButton(title: "Dollars", isSelected: !isPercentageSelected) { isPercentageSelected = false }
                        }
                        TextField(isPercentageSelected ? "Tip percent" : "Tip dollars", text: $tipAmount)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(AppTextFieldStyle())
                            .multilineTextAlignment(.center)
                    }

                    PrimaryButton(title: "Calculate", systemImage: "equal.circle", isDisabled: !canCalculate) { didCalculate = true }
                    SecondaryButton(title: "Reset", systemImage: "arrow.counterclockwise") { reset() }

                    ThemedCard {
                        Text("Calculation Result").appFont(.h2)
                        if didCalculate {
                            Text("Tip Amount: \(calculatedTip, format: .currency(code: "USD"))")
                                .appFont(.h2)
                                .foregroundStyle(AppTheme.highlight)
                            Text("Total Amount: \(totalAmount, format: .currency(code: "USD"))")
                                .appFont(.h2)
                                .foregroundStyle(AppTheme.highlight)
                        } else {
                            Text("Enter a bill and tip, then tap Calculate.").appFont(.paragraph)
                        }
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("Tip Calculator")
        .navigationBarTitleDisplayMode(.inline)
        .hideKeyboardToolbar()
        .sheet(isPresented: $isServicePickerPresented) {
            ServicePicker(selectedServiceIndex: $selectedServiceIndex, services: services)
        }
    }
}

struct RadioButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: isSelected ? "checkmark.circle.fill" : "circle")
                .appFont(.h3)
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(isSelected ? AppTheme.text : AppTheme.accent)
        }
        .background(isSelected ? AppTheme.accent : AppTheme.surface)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.accent, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

struct ServicePicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedServiceIndex: Int
    let services: [String]

    var body: some View {
        NavigationStack {
            AppScreen {
                Picker("Service", selection: $selectedServiceIndex) {
                    ForEach(services.indices, id: \.self) { index in
                        Text(services[index]).foregroundStyle(AppTheme.text)
                    }
                }
                .pickerStyle(.wheel)
            }
            .navigationTitle("Select Service")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview { TipCalculator() }
