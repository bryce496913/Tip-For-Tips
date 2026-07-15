import SwiftUI

struct TipCalculator: View {
    @State private var selectedServiceIndex = 0
    @State private var totalBill = ""
    @State private var tipAmount = ""
    @State private var tipInputMode: TipInputMode = .percentage
    @State private var isServicePickerPresented = false
    @State private var didCalculate = false

    private let services = TippingGuidance.services
    private func decimalValue(_ text: String) -> Double? {
        let formatter = NumberFormatter(); formatter.numberStyle = .decimal; formatter.locale = .current
        if let n = formatter.number(from: text), n.doubleValue >= 0 { return n.doubleValue }
        if let n = Double(text), n >= 0 { return n }
        return nil
    }

    private func reset() { totalBill = ""; tipAmount = ""; tipInputMode = .percentage; selectedServiceIndex = 0; didCalculate = false }

    private var selectedService: TippingService { services.indices.contains(selectedServiceIndex) ? services[selectedServiceIndex] : services[0] }
    private var recommendedTip: String { selectedService.recommendation }
    private var billValue: Double { max(decimalValue(totalBill) ?? 0, 0) }
    private var tipValue: Double { max(decimalValue(tipAmount) ?? 0, 0) }
    private var canCalculate: Bool { decimalValue(totalBill) != nil && decimalValue(tipAmount) != nil }
    private var calculatedTip: Double { tipInputMode == .percentage ? billValue * tipValue / 100 : tipValue }
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
                        SecondaryButton(title: selectedService.name) { isServicePickerPresented = true }
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
                            RadioButton(title: "Percent", isSelected: tipInputMode == .percentage) { tipInputMode = .percentage }
                            RadioButton(title: "Dollars", isSelected: tipInputMode == .fixedAmount) { tipInputMode = .fixedAmount }
                        }
                        TextField(tipInputMode == .percentage ? "Tip percent" : "Tip dollars", text: $tipAmount)
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
        .onChange(of: totalBill) { _ in didCalculate = false }
        .onChange(of: tipAmount) { _ in didCalculate = false }
        .onChange(of: tipInputMode) { _ in didCalculate = false }
        .onChange(of: selectedServiceIndex) { _ in didCalculate = false }
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
    let services: [TippingService]
    @State private var draftIndex: Int = 0

    var body: some View {
        NavigationStack {
            AppScreen {
                Picker("Service", selection: $draftIndex) {
                    ForEach(services.indices, id: \.self) { index in
                        Text(services[index].name).foregroundStyle(AppTheme.text)
                    }
                }
                .accessibilityValue(services.indices.contains(draftIndex) ? services[draftIndex].name : "")
                .pickerStyle(.wheel)
            }
            .navigationTitle("Select Service")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { selectedServiceIndex = draftIndex; dismiss() } }
            }
        }
        .presentationDetents([.medium])
        .onAppear { draftIndex = selectedServiceIndex }
    }
}

#Preview { TipCalculator() }
