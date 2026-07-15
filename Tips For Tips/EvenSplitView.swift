import SwiftUI

struct EvenSplitView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var totalBill = ""
    @State private var peopleInput = "2"
    @State private var tipInput = "0"
    @State private var tipInputMode: TipInputMode = .percentage
    @State private var attemptedCalculation = false
    @State private var touchedFields = Set<InputField>()
    @State private var result: EvenSplitResult?
    @FocusState private var focusedField: InputField?

    private enum InputField: Hashable {
        case bill, tip, people
    }

    private struct EvenSplitResult {
        let billAmount: Decimal
        let tipValue: Decimal
        let tipMode: TipInputMode
        let tipAmount: Decimal
        let totalAmount: Decimal
        let peopleCount: Int
        let amountPerPerson: Decimal
    }

    private var parsedBillAmount: Decimal? { parseDecimal(totalBill, allowZero: true) }
    private var parsedTipValue: Decimal? { parseDecimal(tipInput, allowZero: true) }

    private var validPeopleCount: Int? {
        let trimmed = peopleInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.allSatisfy({ $0.isNumber }), let people = Int(trimmed), people > 0 else { return nil }
        return people
    }

    private var canSplit: Bool {
        parsedBillAmount != nil && parsedTipValue != nil && validPeopleCount != nil
    }

    private var billError: String? {
        guard shouldShowError(for: .bill) else { return nil }
        if totalBill.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter a valid bill amount." }
        if totalBill.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("-") { return "Bill cannot be negative." }
        return parsedBillAmount == nil ? "Enter a valid bill amount." : nil
    }

    private var tipError: String? {
        guard shouldShowError(for: .tip) else { return nil }
        if tipInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter a valid tip value." }
        if tipInput.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("-") { return "Tip cannot be negative." }
        return parsedTipValue == nil ? "Enter a valid tip value." : nil
    }

    private var peopleError: String? {
        guard shouldShowError(for: .people), validPeopleCount == nil else { return nil }
        let trimmed = peopleInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Enter a whole number of people." }
        if trimmed.hasPrefix("-") { return "The number of people must be at least 1." }
        if let people = Int(trimmed), people <= 0 { return "The number of people must be at least 1." }
        return "Enter a whole number of people."
    }

    var body: some View {
        NavigationStack {
            AppScreen {
                ScrollView {
                    VStack(spacing: 18) {
                        ScreenTitle(text: "Even Split")

                        ThemedCard {
                            labeledInput(title: "Bill Amount", text: $totalBill, field: .bill, keyboard: .decimalPad, prefix: currencySymbol, error: billError)
                        }

                        tipModeSelector

                        ThemedCard {
                            labeledInput(title: tipInputMode == .percentage ? "Tip Percentage" : "Tip Amount", text: $tipInput, field: .tip, keyboard: .decimalPad, prefix: tipInputMode == .fixedAmount ? currencySymbol : nil, suffix: tipInputMode == .percentage ? "%" : nil, error: tipError)
                                .accessibilityHint(tipInputMode == .percentage ? "Enter 20 for twenty percent." : "Enter a fixed tip amount in dollars.")
                        }

                        ThemedCard {
                            labeledInput(title: "Number of People", text: $peopleInput, field: .people, keyboard: .numberPad, error: peopleError)
                                .accessibilityHint("Enter a whole number of people, minimum one.")
                        }

                        PrimaryButton(title: "Split", systemImage: "equal.circle", isDisabled: !canSplit) { calculateSplit(markAllFields: true) }
                        SecondaryButton(title: "Reset", systemImage: "arrow.counterclockwise") { reset() }

                        if let result {
                            resultCard(result)
                        } else {
                            ThemedCard { Text(canSplit ? "Tap Split to calculate each person's share." : "Enter a bill amount, tip, and whole number of people.").appFont(.body) }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Even Split")
            .toolbar { Button("Close") { dismiss() } }
        }
        .hideKeyboardToolbar()
        .onChange(of: totalBill) { _ in inputChanged(.bill) }
        .onChange(of: tipInput) { _ in inputChanged(.tip) }
        .onChange(of: peopleInput) { _ in inputChanged(.people) }
        .onChange(of: tipInputMode) { _ in inputChanged(.tip) }
    }

    private var tipModeSelector: some View {
        ThemedCard {
            Text("Tip Type").appFont(.title2)
            HStack(spacing: AppSpacing.standard) {
                ForEach(TipInputMode.allCases) { mode in
                    Button { tipInputMode = mode } label: {
                        Label(mode.shortTitle, systemImage: tipInputMode == mode ? "checkmark.circle.fill" : "circle")
                            .appFont(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .foregroundStyle(tipInputMode == mode ? AppTheme.text : AppTheme.accent)
                    .background(tipInputMode == mode ? AppTheme.accent : AppTheme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.accent, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .accessibilityLabel(mode.title)
                    .accessibilityValue(tipInputMode == mode ? "Selected" : "Not selected")
                    .accessibilityHint("Sets whether the tip value is a percentage or a fixed dollar amount.")
                }
            }
            Text("Selected: \(tipInputMode.title)").appFont(.body).foregroundStyle(AppTheme.text.opacity(0.85))
        }
    }

    private func labeledInput(title: String, text: Binding<String>, field: InputField, keyboard: UIKeyboardType, prefix: String? = nil, suffix: String? = nil, error: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text(title).appFont(.title2)
            HStack {
                if let prefix { Text(prefix).appFont(.headline).accessibilityHidden(true) }
                TextField(title, text: text)
                    .keyboardType(keyboard)
                    .textFieldStyle(AppTextFieldStyle())
                    .multilineTextAlignment(.center)
                    .focused($focusedField, equals: field)
                    .accessibilityLabel(title)
                if let suffix { Text(suffix).appFont(.headline).accessibilityHidden(true) }
            }
            if let error { Text(error).appFont(.body).foregroundStyle(AppTheme.highlight).accessibilityLabel("Error: \(error)") }
        }
    }

    private func resultCard(_ result: EvenSplitResult) -> some View {
        ThemedCard {
            Text("Each Person Pays").appFont(.title2)
            Text(formatCurrency(result.amountPerPerson)).appFont(.title).foregroundStyle(AppTheme.highlight).frame(maxWidth: .infinity, alignment: .center).accessibilityLabel("Each person pays \(formatCurrency(result.amountPerPerson))")
            Divider().overlay(AppTheme.accent.opacity(0.4))
            resultRow("Bill", formatCurrency(result.billAmount))
            resultRow("Tip", tipDescription(for: result))
            resultRow("Tip Amount", formatCurrency(result.tipAmount))
            resultRow("Total", formatCurrency(result.totalAmount))
            resultRow("People", "\(result.peopleCount)")
        }
    }

    private func resultRow(_ label: String, _ value: String) -> some View {
        HStack { Text(label).appFont(.body); Spacer(); Text(value).appFont(.body).foregroundStyle(AppTheme.text) }
    }

    private func inputChanged(_ field: InputField) {
        touchedFields.insert(field)
        result = nil
        attemptedCalculation = false
    }

    private func calculateSplit(markAllFields: Bool) {
        if markAllFields { attemptedCalculation = true; touchedFields = [.bill, .tip, .people] }
        guard let bill = parsedBillAmount, let tipValue = parsedTipValue, let people = validPeopleCount else { result = nil; return }
        let tipAmount = tipInputMode == .percentage ? bill * tipValue / 100 : tipValue
        let total = bill + tipAmount
        result = EvenSplitResult(billAmount: bill, tipValue: tipValue, tipMode: tipInputMode, tipAmount: tipAmount, totalAmount: total, peopleCount: people, amountPerPerson: total / Decimal(people))
    }

    private func reset() {
        totalBill = ""; tipInputMode = .percentage; tipInput = "0"; peopleInput = "2"; attemptedCalculation = false; touchedFields.removeAll(); result = nil; focusedField = nil
    }

    private func shouldShowError(for field: InputField) -> Bool { attemptedCalculation || touchedFields.contains(field) }

    private func parseDecimal(_ text: String, allowZero: Bool) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let formatter = NumberFormatter(); formatter.numberStyle = .decimal; formatter.locale = .current; formatter.generatesDecimalNumbers = true
        let parsed = (formatter.number(from: trimmed) as? NSDecimalNumber)?.decimalValue ?? Decimal(string: trimmed.replacingOccurrences(of: Locale.current.decimalSeparator ?? ".", with: "."))
        guard let value = parsed, value >= 0, allowZero || value > 0, !value.isNaN else { return nil }
        return value
    }

    private var currencySymbol: String { Locale.current.currencySymbol ?? "$" }

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter(); formatter.numberStyle = .currency; formatter.currencyCode = "USD"; formatter.locale = .current; formatter.maximumFractionDigits = 2; formatter.minimumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "$0.00"
    }

    private func formatDecimal(_ value: Decimal) -> String {
        let formatter = NumberFormatter(); formatter.numberStyle = .decimal; formatter.maximumFractionDigits = 2; formatter.minimumFractionDigits = 0
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    private func tipDescription(for result: EvenSplitResult) -> String {
        switch result.tipMode {
        case .percentage: return "\(formatDecimal(result.tipValue))% (\(formatCurrency(result.tipAmount)))"
        case .fixedAmount: return formatCurrency(result.tipAmount)
        }
    }
}

#Preview { EvenSplitView() }
