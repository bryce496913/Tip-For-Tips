import SwiftUI

struct EvenSplitView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var totalBill = ""
    @State private var numberOfPeople = ""
    @State private var tipAmount = ""
    @State private var splitAmount: Double?

    private var validBill: Double? { positiveDouble(totalBill, allowZero: true) }
    private var validPeople: Double? { positiveDouble(numberOfPeople, allowZero: false) }
    private var validTip: Double? { positiveDouble(tipAmount, allowZero: true) }
    private var canSplit: Bool { validBill != nil && validPeople != nil && validTip != nil }

    var body: some View {
        NavigationStack {
            AppScreen {
                ScrollView {
                    VStack(spacing: 18) {
                        ScreenTitle(text: "Even Split")
                        ThemedCard {
                            Text("Split Details") .appFont(.h2)
                            TextField("Total Bill", text: $totalBill).keyboardType(.decimalPad).textFieldStyle(AppTextFieldStyle()).multilineTextAlignment(.center)
                            TextField("Number of People", text: $numberOfPeople).keyboardType(.numberPad).textFieldStyle(AppTextFieldStyle()).multilineTextAlignment(.center)
                            TextField("Tip Amount", text: $tipAmount).keyboardType(.decimalPad).textFieldStyle(AppTextFieldStyle()).multilineTextAlignment(.center)
                            PrimaryButton(title: "Split", isDisabled: !canSplit) { calculateSplit() }
                        }
                        ThemedCard {
                            Text("Total with Tip: \(((validBill ?? 0) + (validTip ?? 0)), format: .currency(code: "USD"))")
                                .appFont(.h2)
                                .foregroundStyle(AppTheme.highlight)
                            Text("Amount per Person: \((splitAmount ?? 0), format: .currency(code: "USD"))")
                                .appFont(.h2)
                                .foregroundStyle(AppTheme.highlight)
                                .accessibilityLabel("Amount per person \((splitAmount ?? 0), format: .currency(code: "USD"))")
                            if !canSplit {
                                Text("Enter a non-negative bill, at least one person, and a non-negative tip amount.")
                                    .appFont(.paragraph)
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Even Split")
            .toolbar { Button("Close") { dismiss() } }
        }
        .hideKeyboardToolbar()
    }

    private func calculateSplit() {
        guard let bill = validBill, let people = validPeople, let tip = validTip else { return }
        splitAmount = (bill + tip) / people
    }

    private func positiveDouble(_ value: String, allowZero: Bool) -> Double? {
        let formatter = NumberFormatter(); formatter.numberStyle = .decimal; formatter.locale = .current
        let parsed = formatter.number(from: value)?.doubleValue ?? Double(value)
        guard let number = parsed, number >= 0, allowZero || number > 0 else { return nil }
        return number
    }
}

#Preview { EvenSplitView() }
