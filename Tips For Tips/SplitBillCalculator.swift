import SwiftUI

@MainActor
final class SplitBillViewModel: ObservableObject {
    @Published var session: SplitSession
    @Published var result: SplitCalculationResult?
    @Published var validationMessage: String?
    @Published var saveMessage: String?
    @Published var isSaving = false
    @Published var hasUnsavedChanges = true
    private let engine = SplitCalculationEngine()
    private let repository: CalculationRepository

    init(context: SplitCalculatorContext = .manual, preferences: UserPreferences = .defaults, repository: CalculationRepository = FileCalculationRepository()) {
        self.repository = repository
        let count = max(1, context.suggestedPeopleCount ?? preferences.defaultPeopleCount)
        let subtotal = context.subtotal ?? max(0, (context.total ?? 0) - (context.tax ?? 0) - (context.tipAmount ?? 0))
        let calculatedTotal = subtotal + (context.tax ?? 0) + (context.tipAmount ?? 0)
        session = SplitSession(id: UUID(), name: "Bill Split", mode: .equal, currencyCode: context.currencyCode, subtotal: subtotal, tax: context.tax ?? 0, tipAmount: context.tipAmount ?? 0, total: calculatedTotal, participants: (1...count).map { SplitParticipant(name: "Person \($0)") }, items: [SplitItem(name: "Item", price: subtotal)], taxAllocationMode: .proportional, tipAllocationMode: .proportional, roundingRule: SplitRoundingRule(preference: preferences.roundingPreference), sourceCalculationID: context.sourceCalculationID, receiptID: context.receiptID, createdAt: Date(), updatedAt: Date())
        recalculate()
    }

    func recalculate() { saveMessage = nil; hasUnsavedChanges = true; do { session.total = session.subtotal + session.tax + session.tipAmount; session.updatedAt = Date(); result = try engine.calculate(session: session); validationMessage = nil } catch { result = nil; validationMessage = error.localizedDescription } }
    func setMode(_ mode: SplitMode) { session.mode = mode; if mode == .percentage { splitEvenlyPercentages() }; recalculate() }
    func addParticipant() { session.participants.append(SplitParticipant(name: "Person \(session.participants.count + 1)")); if session.mode == .percentage { splitEvenlyPercentages() }; recalculate() }
    func deleteParticipant(_ id: UUID) { guard session.participants.count > 1 else { validationMessage = "Keep at least one participant."; return }; session.participants.removeAll { $0.id == id }; session.items = session.items.map { item in var i = item; i.assignments.removeAll { $0.participantID == id }; return i }; if session.mode == .percentage { splitEvenlyPercentages() }; recalculate() }
    func mark(_ id: UUID, paid: Bool) { guard let i = session.participants.firstIndex(where: { $0.id == id }) else { return }; session.participants[i].isPaid = paid; recalculate() }
    func markAllPaid() { for i in session.participants.indices { session.participants[i].isPaid = true }; recalculate() }
    func resetPaid() { for i in session.participants.indices { session.participants[i].isPaid = false }; recalculate() }
    func assignRemaining(to id: UUID) { let assigned = session.participants.reduce(Decimal(0)) { $0 + ($1.customAmount ?? 0) }; if let i = session.participants.firstIndex(where: { $0.id == id }) { session.participants[i].customAmount = max(0, session.subtotal - assigned + (session.participants[i].customAmount ?? 0)) }; recalculate() }
    func splitEvenlyPercentages() { let ids = session.participants.map(\.id); let allocations = SplitCalculationEngine().calculatePercentForUI(count: ids.count); for i in session.participants.indices { session.participants[i].percentage = allocations[i] } }
    func addItem() { session.items.append(SplitItem(name: "Item", price: 0)); recalculate() }
    func deleteItem(_ id: UUID) { session.items.removeAll { $0.id == id }; if session.items.isEmpty { addItem() }; recalculate() }
    func shareItemWithEveryone(_ itemID: UUID) { guard let i = session.items.firstIndex(where: { $0.id == itemID }), !session.participants.isEmpty else { return }; let share = Decimal(1) / Decimal(session.participants.count); session.items[i].assignments = session.participants.map { SplitItemAssignment(participantID: $0.id, share: share) }; session.items[i].sharingRule = .sharedByEveryone; recalculate() }
    func save() async { guard !isSaving else { return }; guard let result else { validationMessage = "Complete the split before saving."; return }; isSaving = true; defer { isSaving = false }; do { let record = SavedCalculationRecord(id: session.id, recordType: .split, tipResult: nil, splitResult: result, receiptID: session.receiptID, merchantName: nil, notes: session.name, currencyConversion: nil, shareSummary: shareSummary, createdAt: session.createdAt, updatedAt: Date()); try await repository.saveCalculation(record); saveMessage = "Split saved."; hasUnsavedChanges = false } catch { saveMessage = "Could not save split." } }
    var shareSummary: String { guard let result else { return "" }; return (["Tips for Tips — Bill Split", "", "Restaurant total: \(money(result.originalTotal))", "Rounded payments: \(money(result.roundedCollectedTotal))", "Rounding difference: \(money(result.roundingDifference))", ""] + result.participantResults.map { "\($0.participantName): \(money($0.finalAmount)) — \($0.isPaid ? "Paid" : "Unpaid")" } + ["", "Tax included: \(money(session.tax))", "Tip included: \(money(session.tipAmount))"]).joined(separator: "\n") }
    var canSave: Bool { result != nil && !isSaving }
    var canShare: Bool { result != nil }
    var canMarkAllPaid: Bool { result != nil && session.participants.contains { !$0.isPaid } }
    var canResetPaid: Bool { session.participants.contains { $0.isPaid } }
    func money(_ value: Decimal) -> String { formatMoney(value, code: session.currencyCode) }
}

extension SplitCalculationEngine { func calculatePercentForUI(count: Int) -> [Decimal] { guard count > 0 else { return [] }; let base = Decimal(100) / Decimal(count); return Array(repeating: base, count: count) } }

enum BillSummaryField: Hashable { case subtotal, tax, tip }

enum BillSummaryParser {
    static func parseRequired(_ text: String, locale: Locale = .current) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = LocalizedDecimalParser.parse(trimmed, locale: locale), value >= 0 else { return nil }
        return value
    }

    static func parseOptional(_ text: String, locale: Locale = .current) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        guard let value = LocalizedDecimalParser.parse(trimmed, locale: locale), value >= 0 else { return nil }
        return value
    }
}

struct SplitBillCalculator: View {
    @StateObject private var model: SplitBillViewModel
    @State private var subtotalText: String
    @State private var taxText: String
    @State private var tipText: String
    @State private var attemptedBillEdit = false
    @FocusState private var focusedField: BillSummaryField?

    init(context: SplitCalculatorContext = .manual) {
        let vm = SplitBillViewModel(context: context)
        _model = StateObject(wrappedValue: vm)
        _subtotalText = State(initialValue: vm.session.subtotal == 0 ? "" : "\(vm.session.subtotal)")
        _taxText = State(initialValue: vm.session.tax == 0 ? "" : "\(vm.session.tax)")
        _tipText = State(initialValue: vm.session.tipAmount == 0 ? "" : "\(vm.session.tipAmount)")
    }

    var body: some View {
        AppScreen { ScrollView { LazyVStack(spacing: AppSpacing.section) { ScreenTitle(text: "How would you like to split it?", subtitle: "Equal, custom amount, percentage and itemized splitting with transparent tax, tip and rounding."); billCard; modeSelector; modeBody; allocationCard; if let message = model.validationMessage { validation(message) }; if let result = model.result { SplitResultCard(model: model, result: result) } }.padding(AppSpacing.screen) } }
            .navigationTitle("Split Bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Button("Previous") { moveFocus(-1) }.disabled(focusedField == .subtotal || focusedField == nil); Button("Next") { moveFocus(1) }.disabled(focusedField == .tip || focusedField == nil); Spacer(); Button("Done") { focusedField = nil } } }
    }

    private var billCard: some View {
        ThemedCard {
            Text("Bill Summary").appFont(.title2)
            Text("Enter the receipt subtotal, tax, and tip. The final total is calculated automatically.").appFont(.body).foregroundStyle(AppTheme.secondaryText)
            LabeledCurrencyField(title: "Subtotal", text: $subtotalText, currencyCode: model.session.currencyCode, isRequired: true, errorMessage: subtotalError, focusedField: $focusedField, field: .subtotal) { applyBillInputs() }
            LabeledCurrencyField(title: "Tax", text: $taxText, currencyCode: model.session.currencyCode, helpText: "Optional; leave blank for zero.", errorMessage: taxError, focusedField: $focusedField, field: .tax) { applyBillInputs() }
            LabeledCurrencyField(title: "Tip", text: $tipText, currencyCode: model.session.currencyCode, helpText: "Optional; leave blank for zero.", errorMessage: tipError, focusedField: $focusedField, field: .tip) { applyBillInputs() }
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text("Calculated final total").appFont(.subheadline).foregroundStyle(AppTheme.secondaryText)
                Text(calculatedTotalText).font(.system(.title2, design: .rounded, weight: .bold)).monospacedDigit().foregroundStyle(AppTheme.text)
                Text("Final total is calculated from subtotal, tax, and tip.").appFont(.footnote).foregroundStyle(AppTheme.secondaryText)
            }.padding(AppSpacing.standard).frame(maxWidth: .infinity, alignment: .leading).background(AppTheme.background.opacity(0.35)).clipShape(RoundedRectangle(cornerRadius: AppRadius.medium)).accessibilityElement(children: .combine).accessibilityLabel("Calculated final total").accessibilityValue(calculatedTotalText)
        }
    }

    private var subtotalError: String? { attemptedBillEdit && BillSummaryParser.parseRequired(subtotalText) == nil ? (subtotalText.contains("-") ? "Subtotal cannot be negative." : "Enter a valid subtotal.") : nil }
    private var taxError: String? { attemptedBillEdit && BillSummaryParser.parseOptional(taxText) == nil ? "Tax cannot be negative." : nil }
    private var tipError: String? { attemptedBillEdit && BillSummaryParser.parseOptional(tipText) == nil ? "Tip cannot be negative." : nil }
    private var calculatedTotalText: String { guard let subtotal = BillSummaryParser.parseRequired(subtotalText), let tax = BillSummaryParser.parseOptional(taxText), let tip = BillSummaryParser.parseOptional(tipText) else { return "—" }; return model.money(subtotal + tax + tip) }

    private func applyBillInputs() { attemptedBillEdit = true; guard let subtotal = BillSummaryParser.parseRequired(subtotalText), let tax = BillSummaryParser.parseOptional(taxText), let tip = BillSummaryParser.parseOptional(tipText) else { model.result = nil; return }; model.session.subtotal = subtotal; model.session.tax = tax; model.session.tipAmount = tip; model.recalculate() }
    private func moveFocus(_ delta: Int) { let fields: [BillSummaryField] = [.subtotal, .tax, .tip]; guard let current = focusedField, let index = fields.firstIndex(of: current) else { return }; focusedField = fields[min(max(index + delta, 0), fields.count - 1)] }
    private var modeSelector: some View { ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(SplitMode.allCases) { mode in Button { model.setMode(mode) } label: { Label(mode.title, systemImage: model.session.mode == mode ? "checkmark.circle.fill" : "circle").padding(12).background(model.session.mode == mode ? AppTheme.accent : AppTheme.surface).clipShape(RoundedRectangle(cornerRadius: 14)) }.accessibilityLabel("\(mode.title) mode").accessibilityValue(model.session.mode == mode ? "Selected" : "Not selected") } } } }
    @ViewBuilder private var modeBody: some View { ParticipantsCard(model: model); switch model.session.mode { case .equal: ThemedCard { Text("Equal split stays simple: enter the total and participant count. Remainder cents are distributed deterministically so totals are preserved.").appFont(.body) }; case .customAmount: CustomAmountCard(model: model); case .percentage: PercentageCard(model: model); case .itemized: ItemizedCard(model: model) } }
    private var allocationCard: some View { ThemedCard { Text("Tax, tip and rounding").appFont(.title2); Picker("Tax allocation", selection: $model.session.taxAllocationMode) { ForEach(ChargeAllocationMode.allCases) { Text($0.title).tag($0) } }.onChange(of: model.session.taxAllocationMode) { _ in model.recalculate() }; Picker("Tip allocation", selection: $model.session.tipAllocationMode) { ForEach(ChargeAllocationMode.allCases) { Text($0.title).tag($0) } }.onChange(of: model.session.tipAllocationMode) { _ in model.recalculate() }; Picker("Rounding", selection: $model.session.roundingRule) { ForEach(SplitRoundingRule.allCases) { Text($0.title).tag($0) } }.onChange(of: model.session.roundingRule) { _ in model.recalculate() } } }
    private func validation(_ message: String) -> some View { ThemedCard { Text(message).appFont(.body).foregroundStyle(AppTheme.highlight).accessibilityLabel("Validation: \(message)") } }
}

struct LabeledCurrencyField: View {
    let title: String; @Binding var text: String; let currencyCode: String; var helpText: String? = nil; var isRequired = false; var errorMessage: String? = nil; var focusedField: FocusState<BillSummaryField?>.Binding; let field: BillSummaryField; let onChange: () -> Void
    var body: some View { VStack(alignment: .leading, spacing: AppSpacing.small) { HStack { Text(title).appFont(.headline); if isRequired { Text("Required").appFont(.caption).foregroundStyle(AppTheme.secondaryText) } }; if let helpText { Text(helpText).appFont(.footnote).foregroundStyle(AppTheme.secondaryText) }; HStack { Text(currencyCode).appFont(.callout).foregroundStyle(AppTheme.secondaryText); TextField("0.00", text: $text).keyboardType(.decimalPad).focused(focusedField, equals: field).appFont(.body).monospacedDigit().accessibilityLabel(title) }.padding(.horizontal, 14).frame(minHeight: 50).background(AppTheme.background.opacity(0.25)).clipShape(RoundedRectangle(cornerRadius: AppRadius.medium)).overlay(RoundedRectangle(cornerRadius: AppRadius.medium).stroke(errorMessage == nil ? (focusedField.wrappedValue == field ? AppTheme.accent : AppTheme.border) : AppTheme.error, lineWidth: focusedField.wrappedValue == field ? 2 : 1)).contentShape(Rectangle()).onTapGesture { focusedField.wrappedValue = field }.onChange(of: focusedField.wrappedValue) { newValue in if newValue == field && text.trimmingCharacters(in: .whitespacesAndNewlines) == "0" { text = "" } }.onChange(of: text) { _ in onChange() }; if let errorMessage { InlineErrorView(message: errorMessage).appFont(.footnote) } } }
}

struct DecimalValueField: View { let title: String; @Binding var value: Decimal; let onChange: () -> Void; @State private var text = ""; var body: some View { TextField(title, text: $text).keyboardType(.decimalPad).textFieldStyle(AppTextFieldStyle()).onAppear { if text.isEmpty { text = value == 0 ? "" : "\(value)" } }.onChange(of: text) { newValue in if let parsed = LocalizedDecimalParser.parse(newValue), parsed >= 0 { value = parsed }; onChange() }.accessibilityLabel(title) } }

struct ParticipantsCard: View { @ObservedObject var model: SplitBillViewModel; var body: some View { ThemedCard { Text("Participants").appFont(.title2); ForEach($model.session.participants) { $p in HStack { TextField("Name", text: $p.name).textFieldStyle(AppTextFieldStyle()).onChange(of: p.name) { _ in model.recalculate() }; Button(p.isPaid ? "Mark Unpaid" : "Mark Paid") { model.mark(p.id, paid: !p.isPaid) }; Button(role: .destructive) { model.deleteParticipant(p.id) } label: { Label("Delete", systemImage: "trash") }.accessibilityLabel("Delete participant \(p.name)") } }; PrimaryButton(title: "Add Participant", systemImage: "plus") { model.addParticipant() } } } }
struct CustomAmountCard: View { @ObservedObject var model: SplitBillViewModel; var body: some View { ThemedCard { Text("Custom amounts").appFont(.title2); ForEach($model.session.participants) { $p in VStack(alignment: .leading) { Text(p.name).appFont(.headline); DecimalValueField(title: "Assigned amount", value: Binding(get: { p.customAmount ?? 0 }, set: { p.customAmount = $0 })) { model.recalculate() }; HStack { SecondaryButton(title: "Assign Remaining") { model.assignRemaining(to: p.id) } } } }; let assigned = model.session.participants.reduce(Decimal(0)) { $0 + ($1.customAmount ?? 0) }; ResultSummaryRow(label: "Remaining", value: model.money(model.session.subtotal - assigned)) } } }
struct PercentageCard: View { @ObservedObject var model: SplitBillViewModel; var body: some View { ThemedCard { Text("Percentages").appFont(.title2); ForEach($model.session.participants) { $p in DecimalValueField(title: "\(p.name) percent", value: Binding(get: { p.percentage ?? 0 }, set: { p.percentage = $0 })) { model.recalculate() } }; let total = model.session.participants.reduce(Decimal(0)) { $0 + ($1.percentage ?? 0) }; ResultSummaryRow(label: "Total percentage", value: "\(total)%"); SecondaryButton(title: "Split Evenly") { model.splitEvenlyPercentages(); model.recalculate() } } } }
struct ItemizedCard: View { @ObservedObject var model: SplitBillViewModel; var body: some View { ThemedCard { Text("Items").appFont(.title2); ForEach($model.session.items) { $item in VStack(alignment: .leading) { TextField("Item name", text: $item.name).textFieldStyle(AppTextFieldStyle()).onChange(of: item.name) { _ in model.recalculate() }; DecimalValueField(title: "Price", value: $item.price) { model.recalculate() }; Text("Assigned to: \(assignedNames(item))").appFont(.body); HStack { Menu("Assign") { ForEach(model.session.participants) { p in Button(p.name) { item.assignments = [SplitItemAssignment(participantID: p.id, share: 1)]; model.recalculate() } }; Button("Everyone equally") { model.shareItemWithEveryone(item.id) } }; Button(role: .destructive) { model.deleteItem(item.id) } label: { Label("Delete item", systemImage: "trash") } } } }; PrimaryButton(title: "Add Item", systemImage: "plus") { model.addItem() }; let itemTotal = model.session.items.reduce(Decimal(0)) { $0 + $1.price }; ResultSummaryRow(label: "Item subtotal", value: model.money(itemTotal)); ResultSummaryRow(label: "Difference", value: model.money(model.session.subtotal - itemTotal)) } }
    private func assignedNames(_ item: SplitItem) -> String { let ids = Set(item.assignments.map(\.participantID)); let names = model.session.participants.filter { ids.contains($0.id) }.map(\.name); return names.isEmpty ? "Unassigned" : names.joined(separator: ", ") }
}
struct SplitResultCard: View {
    @ObservedObject var model: SplitBillViewModel
    let result: SplitCalculationResult
    var body: some View {
        ThemedCard {
            Text("Bill Split").appFont(.title2)
            ResultSummaryRow(label: "Original bill", value: model.money(result.originalTotal))
            ResultSummaryRow(label: "Rounded payments", value: model.money(result.roundedCollectedTotal))
            ResultSummaryRow(label: "Difference", value: model.money(result.roundingDifference))
            let paid = result.participantResults.filter(\.isPaid).reduce(Decimal(0)) { $0 + $1.finalAmount }
            ResultSummaryRow(label: "Paid", value: model.money(paid))
            ResultSummaryRow(label: "Outstanding", value: model.money(result.roundedCollectedTotal - paid))
            ForEach(result.participantResults) { p in
                DisclosureGroup {
                    ResultSummaryRow(label: "Assigned bill", value: model.money(p.baseAmount)); ResultSummaryRow(label: "Tax", value: model.money(p.taxAmount)); ResultSummaryRow(label: "Tip", value: model.money(p.tipAmount)); ResultSummaryRow(label: "Rounding", value: model.money(p.roundingAdjustment)); ForEach(p.itemBreakdown) { item in ResultSummaryRow(label: item.itemName, value: model.money(item.amount)) }
                } label: {
                    ViewThatFits(in: .horizontal) {
                        HStack { Text(p.participantName).appFont(.headline); Spacer(); Text(model.money(p.finalAmount)).appFont(.headline).monospacedDigit(); Label(p.isPaid ? "Paid" : "Unpaid", systemImage: p.isPaid ? "checkmark.circle.fill" : "circle") }
                        VStack(alignment: .leading) { Text(p.participantName).appFont(.headline); Text(model.money(p.finalAmount)).appFont(.headline).monospacedDigit(); Label(p.isPaid ? "Paid" : "Unpaid", systemImage: p.isPaid ? "checkmark.circle.fill" : "circle") }
                    }
                }.accessibilityLabel("\(p.participantName), \(model.money(p.finalAmount)), \(p.isPaid ? "Paid" : "Unpaid")")
            }
            VStack(spacing: AppSpacing.medium) {
                if let msg = model.saveMessage {
                    Label(msg, systemImage: msg.contains("saved") ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .appFont(.body).foregroundStyle(msg.contains("saved") ? AppTheme.success : AppTheme.error).padding(AppSpacing.standard).frame(maxWidth: .infinity, alignment: .leading).background(AppTheme.background.opacity(0.35)).clipShape(RoundedRectangle(cornerRadius: AppRadius.medium))
                }
                ViewThatFits(in: .horizontal) {
                    HStack { saveButton; shareButton }
                    VStack { saveButton; shareButton }
                }
                ViewThatFits(in: .horizontal) {
                    HStack { paidButton; resetButton }
                    VStack { paidButton; resetButton }
                }
            }
        }
    }
    private var saveButton: some View { PrimaryButton(title: model.hasUnsavedChanges ? "Save Split" : "Save Changes", systemImage: model.isSaving ? nil : "tray.and.arrow.down", isDisabled: !model.canSave) { Task { await model.save() } }.overlay { if model.isSaving { ProgressView().tint(AppTheme.text) } }.accessibilityLabel(model.hasUnsavedChanges ? "Save Split" : "Save Changes") }
    private var shareButton: some View { ShareLink(item: model.shareSummary) { Label("Share Summary", systemImage: "square.and.arrow.up").appFont(.headline).frame(maxWidth: .infinity, minHeight: 50) }.buttonStyle(AppButtonStylePublic.secondary).disabled(!model.canShare).opacity(model.canShare ? 1 : 0.55).accessibilityLabel("Share Summary") }
    private var paidButton: some View { SecondaryButton(title: "Mark Everyone Paid", systemImage: "checkmark.circle", isDisabled: !model.canMarkAllPaid) { model.markAllPaid() }.accessibilityLabel("Mark Everyone Paid") }
    private var resetButton: some View { SecondaryButton(title: "Reset Paid Status", systemImage: "arrow.counterclockwise", isDisabled: !model.canResetPaid) { model.resetPaid() }.accessibilityLabel("Reset Paid Status") }
}

#Preview { NavigationStack { SplitBillCalculator() } }
