import SwiftUI

enum AppRoute: Hashable {
    case guidedTipAssistant(TipCalculationInput? = nil, linkedReceiptID: UUID? = nil)
    case receiptScanner(ReceiptScannerContext = .newReceipt)
    case splitCalculator(SplitCalculatorContext = .manual)
    case currencyConverter(CurrencyConversionContext? = nil)
    case history
    case tippingGuide
    case settings
    case receiptDetail(UUID)
    case calculationDetail(UUID)
    case guideSection(String)
    case quickCalculator
    case receipts
    case notePad
}

struct MainMenu: View {
    @EnvironmentObject private var appEnvironment: AppEnvironment
    private var preferences: UserPreferences { appEnvironment.preferences }

    var body: some View {
        NavigationStack {
            AppScreen {
                ScrollView {
                    VStack(spacing: AppSpacing.large) {
                        Image("MainLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 160, height: 160)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: AppSpacing.small) { Text("Tips for Tips").appFont(.largeTitle).accessibilityAddTraits(.isHeader); Text("From bill to tip, split, save and conversion for travelers in the United States.").appFont(.body).foregroundStyle(AppTheme.secondaryText).fixedSize(horizontal: false, vertical: true) }.frame(maxWidth: .infinity, alignment: .leading)

                        ThemedCard {
                            Text("I have a bill").appFont(.title2)
                            Text("Get contextual tipping guidance, calculate the total and continue directly into splitting, saving or converting.")
                                .appFont(.body)
                                .foregroundStyle(AppTheme.secondaryText)
                            NavigationLink(value: AppRoute.guidedTipAssistant()) {
                                Label("Calculate a Tip", systemImage: "sparkles")
                                    .appFont(.headline)
                                    .frame(maxWidth: .infinity, minHeight: 52)
                            }
                            .buttonStyle(AppButtonStylePublic.primary)
                        }

                        DashboardQuickActions()

                        ThemedCard {
                            Text("Current travel defaults").appFont(.title2)
                            ResultSummaryRow(label: "Home currency", value: preferences.homeCurrencyCode)
                            ResultSummaryRow(label: "Tip basis", value: preferences.tipCalculationBasis.title)
                            ResultSummaryRow(label: "People", value: "\(preferences.defaultPeopleCount)")
                            NavigationLink("Open Settings", value: AppRoute.settings)
                                .appFont(.body)
                                .foregroundStyle(AppTheme.accent)
                        }

                        RecentActivityCard(calculationRepository: appEnvironment.calculationRepository, receiptRepository: appEnvironment.receiptRepository)

                    }
                    .padding(AppSpacing.screen)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: AppRoute.self) { route in destination(for: route) }
        }
    }

    @ViewBuilder private func destination(for route: AppRoute) -> some View {
        switch route {
        case let .guidedTipAssistant(input, linkedReceiptID): GuidedTipAssistantView(preferences: preferences, prefilledInput: input, linkedReceiptID: linkedReceiptID, repository: appEnvironment.calculationRepository)
        case let .receiptScanner(context): ReceiptScannerView(context: context, preferences: preferences, repository: appEnvironment.receiptRepository, calculationRepository: appEnvironment.calculationRepository)
        case .receipts: Receipts(repository: appEnvironment.receiptRepository, calculationRepository: appEnvironment.calculationRepository, currencyRateRepository: appEnvironment.currencyRateRepository, preferences: preferences)
        case let .splitCalculator(context): SplitBillCalculator(context: context, preferences: preferences, repository: appEnvironment.calculationRepository)
        case let .currencyConverter(context): CurrencyConverter(context: context, preferences: preferences, repository: appEnvironment.currencyRateRepository)
        case .history: HistoryView(calculationRepository: appEnvironment.calculationRepository, receiptRepository: appEnvironment.receiptRepository)
        case .tippingGuide: HelpfulTips()
        case .settings: SettingsView(initialPreferences: preferences, repository: appEnvironment.preferencesRepository)
        case let .receiptDetail(id): ReceiptDetailView(receiptID: id, preferences: preferences, repository: appEnvironment.receiptRepository, calculationRepository: appEnvironment.calculationRepository, currencyRateRepository: appEnvironment.currencyRateRepository)
        case let .calculationDetail(id): CalculationDetailView(calculationID: id, repository: appEnvironment.calculationRepository)
        case let .guideSection(sectionID): HelpfulTips(initialSectionID: sectionID)
        case .quickCalculator: TipCalculator(preferences: preferences)
        case .notePad: NotePad()
        }
    }
}

struct DashboardQuickActions: View {
    @Environment(\.sizeCategory) private var sizeCategory

    private let actions: [DashboardAction] = [
        DashboardAction(id: "receipts", title: "Receipts", systemImage: "receipt", route: .receipts),
        DashboardAction(id: "split", title: "Split a Bill", systemImage: "person.2", route: .splitCalculator()),
        DashboardAction(id: "currency", title: "Convert Currency", systemImage: "arrow.left.arrow.right", route: .currencyConverter()),
        DashboardAction(id: "guide", title: "What Should I Tip?", systemImage: "book", route: .tippingGuide),
        DashboardAction(id: "quick-calculator", title: "Quick Calculate", systemImage: "percent", route: .quickCalculator),
        DashboardAction(id: "notepad", title: "Note Pad", systemImage: "note.text", route: .notePad)
    ]
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: AppSpacing.standard, alignment: .top), count: sizeCategory.isAccessibilityCategory ? 1 : 2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.standard) {
            Text("Quick actions").appFont(.title2)
            LazyVGrid(columns: columns, spacing: AppSpacing.standard) {
                ForEach(actions) { action in
                    NavigationLink(value: action.route) {
                        ThemedCard {
                            Label(action.title, systemImage: action.systemImage)
                                .appFont(.headline)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(action.title)
                }
            }
        }
    }
}

private struct DashboardAction: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let route: AppRoute
}


@MainActor
final class GuidedTipAssistantViewModel: ObservableObject {
    @Published var input: TipCalculationInput
    @Published var currentStep: GuidedTipStep = .service
    @Published var result: TipCalculationResult?
    @Published var validationMessage: String?
    @Published var searchText = ""
    @Published var selectedCategory: TippingServiceCategory?
    @Published var saveConfirmation: String?
    @Published private(set) var savedCalculationID: UUID?

    let services = TippingGuidance.services
    private let engine = TipRecommendationEngine()
    private let repository: CalculationRepository
    private let linkedReceiptID: UUID?
    let preferences: UserPreferences

    init(preferences: UserPreferences = .defaults, prefilledInput: TipCalculationInput? = nil, linkedReceiptID: UUID? = nil, repository: CalculationRepository = FileCalculationRepository()) {
        input = prefilledInput ?? .defaults(preferences: preferences)
        self.preferences = preferences
        self.linkedReceiptID = linkedReceiptID
        self.repository = repository
        if prefilledInput != nil { currentStep = .service }
    }

    var selectedService: TippingService? { services.first { $0.id == input.serviceID } }
    var filteredServices: [TippingService] { services.filter { service in (selectedCategory == nil || service.category == selectedCategory) && (searchText.isEmpty || service.name.localizedCaseInsensitiveContains(searchText) || service.recommendationSummary.localizedCaseInsensitiveContains(searchText)) } }

    func selectService(_ service: TippingService) { input.serviceID = service.id; invalidate() }
    func setQuality(_ quality: ServiceQuality) { input.serviceQuality = quality; invalidate() }
    func setGratuity(_ status: GratuityStatus) { input.gratuityStatus = status; invalidate() }
    func updateAmounts() { invalidate() }
    func back() { validationMessage = nil; currentStep = GuidedTipStep(rawValue: max(0, currentStep.rawValue - 1)) ?? .service }
    func restart() { input = .defaults(preferences: preferences); currentStep = .service; result = nil; validationMessage = nil; savedCalculationID = nil }

    func advance() {
        validationMessage = validate(step: currentStep)
        guard validationMessage == nil else { return }
        if currentStep == .people { calculate() } else { currentStep = GuidedTipStep(rawValue: currentStep.rawValue + 1) ?? .result }
    }

    func calculate() {
        do { result = try engine.calculate(input: input, preferences: preferences); currentStep = .result; validationMessage = nil }
        catch { validationMessage = error.localizedDescription }
    }

    func saveResult() async {
        guard let result else { return }
        do {
            let id = savedCalculationID ?? UUID()
            let record = SavedCalculationRecord(id: id, recordType: .tipOnly, tipResult: result, splitResult: nil, receiptID: linkedReceiptID, merchantName: nil, notes: linkedReceiptID == nil ? "Guided Tip Assistant" : "Receipt-linked tip calculation", currencyConversion: nil, shareSummary: shareSummary, createdAt: result.createdAt, updatedAt: Date())
            try await repository.saveCalculation(record)
            savedCalculationID = id
            saveConfirmation = "Calculation saved."
        } catch { saveConfirmation = "Could not save calculation. Please try again." }
    }

    var shareSummary: String { guard let result else { return "" }; return "Tip for \(result.service.name): \(formatMoney(result.suggestedAdditionalTip, code: result.input.currencyCode)); final total \(formatMoney(result.finalTotal, code: result.input.currencyCode))." }
    func guideRoute() -> AppRoute { .guideSection(selectedService?.guideSectionID ?? input.serviceID) }
    func splitRoute() -> AppRoute { guard let result else { return .splitCalculator() }; return .splitCalculator(.tipResult(result)) }
    func convertRoute() -> AppRoute {
        guard let result else { return .currencyConverter() }
        return .currencyConverter(CurrencyConversionContext(sourceCurrencyCode: result.input.currencyCode, values: [
            ConvertibleAmount(id: "bill", label: "Bill", amount: result.baseBillAmount),
            ConvertibleAmount(id: "tip", label: "Tip", amount: result.suggestedAdditionalTip),
            ConvertibleAmount(id: "total", label: "Final total", amount: result.finalTotal)
        ], sourceRecordID: result.id))
    }

    private func invalidate() { result = nil; validationMessage = nil; savedCalculationID = nil; saveConfirmation = nil }
    private func validate(step: GuidedTipStep) -> String? {
        switch step {
        case .service: return selectedService == nil ? "Select a service." : nil
        case .quality: return nil
        case .gratuity: if input.gratuityStatus == .yes, input.includedGratuityEntryMode != .unknown, (input.includedGratuityAmount ?? input.includedGratuityPercentage ?? 0) < 0 { return "Included gratuity cannot be negative." }; return nil
        case .bill: do { _ = try engine.calculate(input: input); return nil } catch TipCalculationError.missingBillAmount { return "Enter a valid subtotal or final total." } catch TipCalculationError.missingServiceDetail { return nil } catch { return error.localizedDescription }
        case .people: return input.peopleCount < 1 ? "Enter a whole number of people." : nil
        case .result: return nil
        }
    }
}

enum GuidedTipStep: Int, CaseIterable { case service, quality, gratuity, bill, people, result
    var title: String { ["Service", "Service quality", "Gratuity", "Bill details", "People", "Recommendation"][rawValue] }
}

struct GuidedTipAssistantView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: GuidedTipAssistantViewModel
    init(preferences: UserPreferences = .defaults, prefilledInput: TipCalculationInput? = nil, linkedReceiptID: UUID? = nil, repository: CalculationRepository = FileCalculationRepository()) { _model = StateObject(wrappedValue: GuidedTipAssistantViewModel(preferences: preferences, prefilledInput: prefilledInput, linkedReceiptID: linkedReceiptID, repository: repository)) }
    var body: some View { AppScreen { ScrollView { VStack(spacing: AppSpacing.section) { progress; content; if let message = model.validationMessage { InlineErrorView(message: message) }; controls }.padding(AppSpacing.screen) } }.navigationTitle("Guided Tip Assistant").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }.hideKeyboardToolbar().alert("Guided Tip Assistant", isPresented: Binding(get: { model.saveConfirmation != nil }, set: { if !$0 { model.saveConfirmation = nil } })) { Button("OK", role: .cancel) {} } message: { Text(model.saveConfirmation ?? "") } }
    private var progress: some View { VStack(alignment: .leading) { Text("Step \(min(model.currentStep.rawValue + 1, 6)) of 6: \(model.currentStep.title)").appFont(.headline); ProgressView(value: Double(model.currentStep.rawValue + 1), total: 6).accessibilityValue("Step \(model.currentStep.rawValue + 1) of 6") } }
    @ViewBuilder private var content: some View { switch model.currentStep { case .service: serviceStep; case .quality: qualityStep; case .gratuity: gratuityStep; case .bill: billStep; case .people: peopleStep; case .result: resultStep } }
    private var controls: some View { HStack { if model.currentStep != .service { SecondaryButton(title: "Back", systemImage: "chevron.left") { model.back() } }; if model.currentStep != .result { PrimaryButton(title: "Continue", systemImage: "chevron.right") { model.advance() } } } }
    private var serviceStep: some View { ThemedCard { Text("What service did you receive?").appFont(.title2); TextField("Search services", text: $model.searchText).textFieldStyle(AppTextFieldStyle()); ScrollView(.horizontal, showsIndicators: false) { HStack { FilterChip(title: "All", isSelected: model.selectedCategory == nil) { model.selectedCategory = nil }; ForEach(TippingServiceCategory.allCases) { cat in FilterChip(title: cat.title, isSelected: model.selectedCategory == cat) { model.selectedCategory = cat } } } }; ForEach(model.filteredServices) { service in Button { model.selectService(service) } label: { HStack { Image(systemName: service.symbolName); VStack(alignment: .leading) { Text(service.name).appFont(.headline); Text(service.recommendationSummary).appFont(.body).foregroundStyle(AppTheme.secondaryText) }; Spacer(); Image(systemName: model.input.serviceID == service.id ? "checkmark.circle.fill" : "circle") } }.buttonStyle(.plain).padding(.vertical, 8).accessibilityValue(model.input.serviceID == service.id ? "Selected" : "Not selected") } } }
    private var qualityStep: some View { ThemedCard { Text("How was the service?").appFont(.title2); ForEach(ServiceQuality.allCases) { q in RadioButton(title: q.label, isSelected: model.input.serviceQuality == q) { model.setQuality(q) }; Text(q.guidance).appFont(.body).foregroundStyle(AppTheme.secondaryText) } } }
    private var gratuityStep: some View { ThemedCard { Text("Is gratuity already included?").appFont(.title2); HStack { ForEach(GratuityStatus.allCases) { status in RadioButton(title: status.rawValue.capitalized, isSelected: model.input.gratuityStatus == status) { model.setGratuity(status) } } }; if model.input.gratuityStatus == .yes { Picker("Included charge", selection: $model.input.includedGratuityEntryMode) { Text("Unknown").tag(IncludedGratuityEntryMode.unknown); Text("Percent").tag(IncludedGratuityEntryMode.percentage); Text("Dollars").tag(IncludedGratuityEntryMode.amount) }.pickerStyle(.segmented); if model.input.includedGratuityEntryMode == .percentage { DecimalField(title: "Included percent", value: $model.input.includedGratuityPercentage) { model.updateAmounts() } }; if model.input.includedGratuityEntryMode == .amount { DecimalField(title: "Included amount", value: $model.input.includedGratuityAmount) { model.updateAmounts() } }; Toggle("Receipt total already includes this charge", isOn: $model.input.finalTotalIncludesIncludedGratuity).appFont(.body) }; if model.input.gratuityStatus == .unsure { Text("Look for gratuity, automatic gratuity, service charge, hospitality charge, administrative fee, delivery fee, and suggested gratuity. Suggested gratuity is not included; delivery fees are not automatically driver tips.").appFont(.body) } } }
    private var billStep: some View { ThemedCard { Text("Bill details").appFont(.title2); DecimalField(title: "Subtotal", value: $model.input.subtotal) { model.updateAmounts() }; DecimalField(title: "Tax", value: $model.input.tax) { model.updateAmounts() }; DecimalField(title: "Final total", value: $model.input.finalTotal) { model.updateAmounts() }; TextField("Currency code", text: $model.input.currencyCode).textFieldStyle(AppTextFieldStyle()).textInputAutocapitalization(.characters); Picker("Calculation basis", selection: $model.input.calculationBasis) { ForEach(TipCalculationBasis.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented); Text(model.input.calculationBasis == .subtotalBeforeTax ? "Traditionally, restaurant tips may be calculated using the pre-tax subtotal." : "Many payment terminals calculate suggested tips using the final total.").appFont(.body); serviceSpecificFields } }
    @ViewBuilder private var serviceSpecificFields: some View { if model.input.serviceID == "bell-staff" { WholeNumberField(title: "Number of bags", value: $model.input.numberOfBags) }; if model.input.serviceID == "housekeeping" { WholeNumberField(title: "Number of days", value: $model.input.numberOfHousekeepingDays) }; if model.input.serviceID == "bar" { Picker("Bar tip mode", selection: $model.input.bartenderTipMode) { Text("Percentage of tab").tag(BartenderTipMode.percentageOfTab); Text("Per drink").tag(BartenderTipMode.perDrink) }.pickerStyle(.segmented); if model.input.bartenderTipMode == .perDrink { WholeNumberField(title: "Number of drinks", value: $model.input.numberOfDrinks) } }; if model.input.serviceID == "food-delivery" { Text("Delivery difficulty").appFont(.headline); DifficultyToggle(title: "Bad weather", flag: .badWeather, selection: $model.input.foodDeliveryDifficulty); DifficultyToggle(title: "Long distance", flag: .longDistance, selection: $model.input.foodDeliveryDifficulty); DifficultyToggle(title: "Difficult entrance or stairs", flag: .difficultEntrance, selection: $model.input.foodDeliveryDifficulty); DifficultyToggle(title: "Large order", flag: .largeOrder, selection: $model.input.foodDeliveryDifficulty); DifficultyToggle(title: "Late-night delivery", flag: .lateNight, selection: $model.input.foodDeliveryDifficulty) } }
    private var peopleStep: some View { ThemedCard { Text("How many people are paying?").appFont(.title2); Stepper(value: $model.input.peopleCount, in: 1...99) { Text("\(model.input.peopleCount) people").appFont(.title2) }; Text("This creates a simple even per-person amount. Advanced allocation comes later.").appFont(.body) } }
    private var resultStep: some View { VStack(spacing: AppSpacing.section) { if let r = model.result { ResultSummary(result: r, showExplanation: model.preferences.showTippingExplanations); ResultActions(model: model) } else { EmptyStateView(systemImage: "exclamationmark.triangle", title: "No result", message: "Go back and calculate again.") }; SecondaryButton(title: "Start Over", systemImage: "arrow.counterclockwise") { model.restart() } } }
}

extension ServiceQuality { var label: String { rawValue.capitalized }; var guidance: String { switch self { case .poor: return "Important problems directly related to the service."; case .standard: return "Service met normal expectations."; case .good: return "Attentive and helpful service."; case .exceptional: return "Unusually thoughtful or difficult service." } } }

struct DecimalField: View { let title: String; @Binding var value: Decimal?; let onChange: () -> Void; @State private var text = ""; var body: some View { TextField(title, text: $text).keyboardType(.decimalPad).textFieldStyle(AppTextFieldStyle()).onAppear { if let value { text = "\(value)" } }.onChange(of: text) { newValue in value = LocalizedDecimalParser.parse(newValue); onChange() }.accessibilityLabel(title) } }
struct WholeNumberField: View { let title: String; @Binding var value: Int?; @State private var text = ""; var body: some View { TextField(title, text: $text).keyboardType(.numberPad).textFieldStyle(AppTextFieldStyle()).onAppear { if let value { text = "\(value)" } }.onChange(of: text) { newValue in if let int = Int(newValue), String(int) == newValue, int > 0 { value = int } else { value = nil } }.accessibilityLabel(title) } }
struct DifficultyToggle: View { let title: String; let flag: FoodDeliveryDifficulty; @Binding var selection: FoodDeliveryDifficulty; var body: some View { Toggle(title, isOn: Binding(get: { selection.contains(flag) }, set: { isSelected in if isSelected { selection.insert(flag) } else { selection.remove(flag) } })).appFont(.body) } }
struct ResultSummary: View { let result: TipCalculationResult; var showExplanation = true; var body: some View { ThemedCard { Text("Recommended Tip").appFont(.title2); Text(result.recommendedPercentage.map { "\($0)% — \(formatMoney(result.suggestedAdditionalTip, code: result.input.currencyCode))" } ?? formatMoney(result.suggestedAdditionalTip, code: result.input.currencyCode)).font(.appMoneyPrimary).monospacedDigit().foregroundStyle(AppTheme.highlight).minimumScaleFactor(0.75).accessibilityLabel("Recommended tip"); ResultSummaryRow(label: "Final total", value: formatMoney(result.finalTotal, code: result.input.currencyCode)); ResultSummaryRow(label: "Split between \(result.input.peopleCount) people", value: "\(formatMoney(result.amountPerPerson, code: result.input.currencyCode)) each"); ResultSummaryRow(label: result.normalRange == nil ? "Customary guidance" : "Customary range", value: result.customaryGuidance); if result.input.gratuityStatus == .yes { ResultSummaryRow(label: "Included gratuity", value: formatMoney(result.includedGratuityAmount, code: result.input.currencyCode)); ResultSummaryRow(label: "Suggested additional", value: formatMoney(result.suggestedAdditionalTip, code: result.input.currencyCode)); ResultSummaryRow(label: "Combined gratuity", value: formatMoney(result.combinedGratuity, code: result.input.currencyCode)) }; if showExplanation { Text(result.explanation).appFont(.body) }; if result.input.gratuityStatus == .unsure { Text("The receipt charge is uncertain. Confirm whether it is gratuity before adding more; zero additional tip is allowed.").appFont(.body).foregroundStyle(AppTheme.highlight) }; if let lower = result.lowerAlternative { ResultSummaryRow(label: lower.label, value: alternativeText(lower, code: result.input.currencyCode)) }; if let higher = result.higherAlternative { ResultSummaryRow(label: higher.label, value: alternativeText(higher, code: result.input.currencyCode)) } }.accessibilityElement(children: .contain) } }
struct ResultActions: View { @ObservedObject var model: GuidedTipAssistantViewModel; var body: some View { ThemedCard { Text("Next actions").appFont(.title2); NavigationLink("Split This Bill", value: model.splitRoute()); Button("Save Calculation") { Task { await model.saveResult() } }; NavigationLink("Convert Total", value: model.convertRoute()); if let id = model.savedCalculationID { NavigationLink("Add Receipt", value: AppRoute.receiptScanner(.attachToCalculation(id))) } else { Button("Save Before Adding Receipt") { Task { await model.saveResult() } } }; ShareLink(item: model.shareSummary) { Text("Share Summary") }; NavigationLink("Read Service Guide", value: model.guideRoute()) }.appFont(.body).foregroundStyle(AppTheme.accent) } }
func formatMoney(_ value: Decimal, code: String) -> String { (value as NSDecimalNumber).doubleValue.formatted(.currency(code: code)) }
func alternativeText(_ alt: TipAlternative, code: String) -> String { if let p = alt.percentage { return "\(p)% — \(formatMoney(alt.amount, code: code))" }; return formatMoney(alt.amount, code: code) }

struct HistoryView: View {
    @StateObject private var model: HistoryViewModel
    @State private var confirmDeleteAll = false
    init(calculationRepository: CalculationRepository = FileCalculationRepository(), receiptRepository: ReceiptRepository = FileReceiptRepository()) { _model = StateObject(wrappedValue: HistoryViewModel(calculationRepository: calculationRepository, receiptRepository: receiptRepository)) }
    var body: some View {
        AppScreen {
            Group {
                if model.isLoading && model.state.entries.isEmpty { ProgressView("Loading history…").tint(AppTheme.accent) }
                else if model.state.entries.isEmpty { EmptyStateView(systemImage: "clock.arrow.circlepath", title: "No saved activity", message: "Saved tips, receipts and splits will appear here together.") }
                else { historyList }
            }
            .padding(.horizontal, AppSpacing.screen)
        }
        .navigationTitle("History")
        .searchable(text: $model.state.query, prompt: "Search history")
        .accessibilityLabel("Search history")
        .toolbar { ToolbarItemGroup(placement: .topBarTrailing) { sortMenu; filterMenu; Button(role: .destructive) { confirmDeleteAll = true } label: { Image(systemName: "trash") }.accessibilityLabel("Delete all history") } }
        .confirmationDialog("Delete all saved activity?", isPresented: $confirmDeleteAll, titleVisibility: .visible) { Button("Delete saved activity only", role: .destructive) { Task { await model.deleteAllActivity() } }; Button("Cancel", role: .cancel) {} } message: { Text("This deletes saved tip calculations, receipts and splits. Settings and onboarding preferences are kept.") }
        .task { await model.load() }
        .refreshable { await model.load() }
        .alert("History", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(model.errorMessage ?? "") }
    }
    private var historyList: some View { List { if model.state.filteredAndSorted.isEmpty { EmptySearchHistoryRow(clear: { model.state.query = ""; model.state.filter = .all }) } else { ForEach(model.state.filteredAndSorted) { entry in NavigationLink(value: route(for: entry)) { HistoryRow(entry: entry) }.swipeActions { Button(role: .destructive) { Task { await model.delete(entry) } } label: { Label("Delete", systemImage: "trash") } } } } }.scrollContentBackground(.hidden).listStyle(.plain) }
    private var sortMenu: some View { Menu { ForEach(HistorySortOption.allCases) { option in Button { model.state.sort = option } label: { Label(option.title, systemImage: model.state.sort == option ? "checkmark" : "") } } } label: { Label("Sort", systemImage: "arrow.up.arrow.down") }.accessibilityLabel("Sort history") }
    private var filterMenu: some View { Menu { Button("All") { model.state.filter.recordType = nil }; ForEach(HistoryRecordType.allCases) { type in Button(type.title) { model.state.filter.recordType = type } }; Divider(); Button("Reset Filters") { model.state.filter = .all } } label: { Label("Filter", systemImage: model.state.filter == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill") }.accessibilityLabel("Filter history") }
    private func route(for entry: HistoryEntry) -> AppRoute { switch entry.recordType { case .receipt: return .receiptDetail(entry.linkedRecordID); case .tipCalculation, .split: return .calculationDetail(entry.linkedRecordID) } }
}

struct HistoryRow: View { let entry: HistoryEntry; var body: some View { HStack(spacing: AppSpacing.standard) { Image(systemName: icon).foregroundStyle(AppTheme.accent).frame(width: 32).accessibilityLabel(entry.recordType == .receipt ? "Receipt thumbnail" : entry.recordType.title); VStack(alignment: .leading, spacing: 4) { Text(entry.title).appFont(.headline); Text(entry.subtitle ?? entry.recordType.title).appFont(.body).foregroundStyle(AppTheme.secondaryText); Text(entry.createdAt.formatted(date: .abbreviated, time: .omitted)).appFont(.body).foregroundStyle(AppTheme.tertiaryText); if let paid = entry.paidSummary { Text(paid).appFont(.body).foregroundStyle(AppTheme.highlight) } }; Spacer(); if let total = entry.totalAmount { Text(formatMoney(total, code: entry.currencyCode)).appFont(.headline) } }.accessibilityElement(children: .combine).accessibilityLabel("\(entry.title), \(entry.recordType.title), \(entry.createdAt.formatted(date: .abbreviated, time: .omitted)), \(entry.totalAmount.map { formatMoney($0, code: entry.currencyCode) } ?? "No total")") }
    private var icon: String { switch entry.recordType { case .tipCalculation: return "percent"; case .receipt: return "doc.text.image"; case .split: return "person.2" } }
}
struct EmptySearchHistoryRow: View { let clear: () -> Void; var body: some View { VStack(alignment: .leading, spacing: AppSpacing.standard) { Text("No matching history").appFont(.title2); Text("Try clearing search or resetting filters.").appFont(.body); Button("Clear Search", action: clear) }.listRowBackground(AppTheme.surface) } }
struct RecentActivityCard: View { @StateObject private var model: HistoryViewModel; init(calculationRepository: CalculationRepository = FileCalculationRepository(), receiptRepository: ReceiptRepository = FileReceiptRepository()) { _model = StateObject(wrappedValue: HistoryViewModel(calculationRepository: calculationRepository, receiptRepository: receiptRepository)) }; var body: some View { ThemedCard { Text("Recent Activity").appFont(.title2); if model.state.entries.isEmpty { Text("Your recent calculations will appear here.").appFont(.body).foregroundStyle(AppTheme.secondaryText) } else { ForEach(Array(model.state.filteredAndSorted.prefix(3))) { entry in NavigationLink(value: entry.recordType == .receipt ? AppRoute.receiptDetail(entry.linkedRecordID) : AppRoute.calculationDetail(entry.linkedRecordID)) { HStack { Image(systemName: entry.recordType == .split ? "person.2" : entry.recordType == .receipt ? "doc.text.image" : "percent"); VStack(alignment: .leading) { Text(entry.title).appFont(.headline); Text(entry.subtitle ?? entry.recordType.title).appFont(.body).foregroundStyle(AppTheme.tertiaryText) }; Spacer() } } } } }.task { await model.load() } }
}

struct CalculationDetailView: View {
    let calculationID: UUID
    @State private var record: SavedCalculationRecord?
    @State private var error: String?
    @EnvironmentObject private var appEnvironment: AppEnvironment
    private let repository: CalculationRepository
    init(calculationID: UUID, repository: CalculationRepository = FileCalculationRepository()) { self.calculationID = calculationID; self.repository = repository }
    var body: some View { AppScreen { ScrollView { VStack(spacing: AppSpacing.section) { if let record, let tip = record.tipResult { ResultSummary(result: tip, showExplanation: appEnvironment.preferences.showTippingExplanations); ThemedCard { Text("Saved Details").appFont(.title2); ResultSummaryRow(label: "Service", value: tip.service.name); ResultSummaryRow(label: "Basis", value: tip.input.calculationBasis.title); ResultSummaryRow(label: "Currency", value: tip.input.currencyCode); ResultSummaryRow(label: "Date", value: record.createdAt.formatted(date: .abbreviated, time: .shortened)); if !record.notes.isEmpty { Text(record.notes).appFont(.body) }; NavigationLink("Split this bill", value: AppRoute.splitCalculator(.tipResult(tip, sourceCalculationID: record.id))); NavigationLink("Convert", value: AppRoute.currencyConverter(CurrencyConversionContext(sourceCurrencyCode: tip.input.currencyCode, values: [ConvertibleAmount(id: "bill", label: "Bill", amount: tip.baseBillAmount), ConvertibleAmount(id: "tip", label: "Tip", amount: tip.suggestedAdditionalTip), ConvertibleAmount(id: "total", label: "Final total", amount: tip.finalTotal)], sourceRecordID: record.id))); NavigationLink("Open related guidance", value: AppRoute.guideSection(tip.service.guideSectionID ?? tip.service.id)); ShareLink(item: ShareSummaryBuilder().tipSummary(tip)) { Text("Share") } } } else if let record, let split = record.splitResult { SplitDetailSummary(result: split); ShareLink(item: ShareSummaryBuilder().splitSummary(split)) { Text("Share Split") } } else { EmptyStateView(systemImage: "exclamationmark.triangle", title: "Related record no longer available", message: error ?? "This saved calculation could not be found.") } }.padding(AppSpacing.screen) } }.navigationTitle("History Detail").task { await load() } }
    private func load() async { do { record = try await repository.fetchCalculations().first { $0.id == calculationID } } catch { self.error = "Saved calculation could not be loaded." } }
}
enum ReceiptImageState { case loading, metadataOnly, available(UIImage), missing, corrupt, failed(String) }

struct ReceiptDetailView: View {
    let receiptID: UUID
    let preferences: UserPreferences
    private let repository: ReceiptRepository
    private let calculationRepository: CalculationRepository
    private let currencyRateRepository: CurrencyRateRepository
    @State private var receipt: ReceiptRecord?
    @State private var imageState: ReceiptImageState = .loading

    init(receiptID: UUID, preferences: UserPreferences = .defaults, repository: ReceiptRepository = FileReceiptRepository(), calculationRepository: CalculationRepository = FileCalculationRepository(), currencyRateRepository: CurrencyRateRepository = FileCurrencyRateRepository()) {
        self.receiptID = receiptID; self.preferences = preferences; self.repository = repository; self.calculationRepository = calculationRepository; self.currencyRateRepository = currencyRateRepository
    }

    var body: some View {
        AppScreen { ScrollView { VStack(spacing: AppSpacing.section) {
            if let receipt {
                imageCard(receipt)
                ThemedCard {
                    Text(receipt.displayName).appFont(.title2)
                    ResultSummaryRow(label: "Currency", value: receipt.currencyCode.isEmpty ? preferences.homeCurrencyCode : receipt.currencyCode)
                    if let subtotal = receipt.subtotal { ResultSummaryRow(label: "Subtotal", value: formatMoney(subtotal, code: receipt.currencyCode)) }
                    if let tax = receipt.tax { ResultSummaryRow(label: "Tax", value: formatMoney(tax, code: receipt.currencyCode)) }
                    if let total = receipt.total { ResultSummaryRow(label: "Total", value: formatMoney(total, code: receipt.currencyCode)) }
                    if case let .amount(gratuity) = receipt.confirmedIncludedGratuity(), gratuity > 0 { ResultSummaryRow(label: "Included gratuity", value: formatMoney(gratuity, code: receipt.currencyCode)) }
                    if case .needsSubtotal = receipt.confirmedIncludedGratuity() { Text("Enter a subtotal to review percentage-based included gratuity.").foregroundStyle(AppTheme.highlight) }
                    Text(receipt.notes.isEmpty ? "No notes" : receipt.notes).appFont(.body)
                    ShareLink(item: ShareSummaryBuilder().receiptSummary(receipt)) { Text("Share summary only") }
                    NavigationLink { GuidedTipAssistantView(preferences: preferences, prefilledInput: receipt.tipCalculationInput(defaults: preferences), linkedReceiptID: receipt.id, repository: calculationRepository) } label: { Label("Calculate Tip", systemImage: "percent") }
                    NavigationLink { SplitBillCalculator(context: .receipt(receipt), preferences: preferences, repository: calculationRepository) } label: { Label("Split Bill", systemImage: "person.2") }
                    NavigationLink { CurrencyConverter(context: CurrencyConversionContext(sourceCurrencyCode: receipt.currencyCode.isEmpty ? preferences.homeCurrencyCode : receipt.currencyCode, values: receipt.convertibleAmounts, sourceRecordID: receipt.id), preferences: preferences, repository: currencyRateRepository) } label: { Label("Convert Currency", systemImage: "arrow.left.arrow.right") }
                }
            } else { EmptyStateView(systemImage: "doc.text.magnifyingglass", title: "Related record no longer available", message: "This receipt could not be found.") }
        }.padding(AppSpacing.screen) } }.navigationTitle("Receipt").task { await reload() }
    }

    @ViewBuilder private func imageCard(_ receipt: ReceiptRecord) -> some View {
        ThemedCard {
            switch imageState {
            case .loading: ProgressView("Loading receipt image…")
            case .metadataOnly:
                Label("Manual entry", systemImage: "doc.text"); Text("This receipt does not have an image.")
                replacementLink("Add Receipt Image", receipt)
            case let .available(image):
                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220).accessibilityLabel("Receipt image preview")
                NavigationLink { ReceiptFullImageView(image: image, title: receipt.displayName) } label: { Label("View Image", systemImage: "photo") }
                replacementLink("Replace Image", receipt)
            case .missing:
                Label("Receipt image is missing", systemImage: "photo.badge.exclamationmark"); Text("The saved receipt details are still available. Add a replacement image to repair this receipt.")
                replacementLink("Add Replacement Image", receipt)
            case .corrupt:
                Label("Receipt image could not be opened", systemImage: "exclamationmark.triangle"); Text("The saved receipt details remain available. Replace the damaged image to repair this receipt.")
                replacementLink("Replace Damaged Image", receipt)
            case let .failed(message): Text(message); replacementLink("Try a Replacement Image", receipt)
            }
        }
    }

    private func replacementLink(_ title: String, _ receipt: ReceiptRecord) -> some View {
        NavigationLink { ReceiptScannerView(context: .replaceImage(receiptID: receipt.id), preferences: preferences, repository: repository, calculationRepository: calculationRepository) } label: { Label(title, systemImage: "camera") }
    }

    private func reload() async {
        do {
            guard let loaded = try await repository.receipt(id: receiptID) else { receipt = nil; return }
            receipt = loaded
            guard let filename = loaded.imageFilename else { imageState = .metadataOnly; return }
            do { imageState = .available(try await repository.loadImage(filename: filename)) }
            catch let error as ReceiptStorageError { imageState = error == .imageMissing ? .missing : (error == .imageCorrupt ? .corrupt : .failed(error.localizedDescription)) }
            catch { imageState = .failed("The receipt image could not be loaded. Try again or add a replacement.") }
        } catch { receipt = nil; imageState = .failed(error.localizedDescription) }
    }
}

struct ReceiptFullImageView: View {
    let image: UIImage; let title: String
    @State private var scale: CGFloat = 1
    var body: some View { AppScreen { ScrollView([.horizontal, .vertical]) { Image(uiImage: image).resizable().scaledToFit().scaleEffect(scale).padding().gesture(MagnificationGesture().onChanged { scale = min(max($0, 1), 5) }) } }.navigationTitle(title).navigationBarTitleDisplayMode(.inline) }
}
struct SplitDetailSummary: View { let result: SplitCalculationResult; var body: some View { ThemedCard { Text(result.session.name).appFont(.title2); ResultSummaryRow(label: "Original total", value: formatMoney(result.originalTotal, code: result.session.currencyCode)); ResultSummaryRow(label: "Rounded total", value: formatMoney(result.roundedCollectedTotal, code: result.session.currencyCode)); ResultSummaryRow(label: "Difference", value: formatMoney(result.roundingDifference, code: result.session.currencyCode)); ForEach(result.participantResults) { p in ResultSummaryRow(label: p.participantName + (p.isPaid ? " (paid)" : " (unpaid)"), value: formatMoney(p.finalAmount, code: result.session.currencyCode)) } } } }

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var preferences: UserPreferences
    @Published var statusMessage: String?
    private let repository: UserPreferencesRepository

    init(preferences: UserPreferences = .defaults, repository: UserPreferencesRepository = FileUserPreferencesRepository()) {
        self.preferences = preferences.validated
        self.repository = repository
    }

    func load() async { if let loaded = try? await repository.loadPreferences() { preferences = loaded.validated } }
    func update(_ change: (inout UserPreferences) -> Void) { change(&preferences); preferences = preferences.validated; Task { await persist() } }
    private func persist() async { do { try await repository.savePreferences(preferences); statusMessage = "Settings updated." } catch { statusMessage = "Settings could not be saved." } }
}

enum AppLinks {
    // These must be configured with the publisher's verified public destinations
    // before App Review. Keeping them nil makes the release blocker visible.
    static let privacyPolicy: URL? = nil
    static let support: URL? = nil
}

enum SettingsSheet: Identifiable { case currency, tip, basis, people; var id: String { "\(self)" } }

struct SettingsView: View {
    @EnvironmentObject private var appEnvironment: AppEnvironment
    @StateObject private var model: SettingsViewModel
    @State private var activeSheet: SettingsSheet?
    init(initialPreferences: UserPreferences = .defaults, repository: UserPreferencesRepository = FileUserPreferencesRepository()) { _model = StateObject(wrappedValue: SettingsViewModel(preferences: initialPreferences, repository: repository)) }
    var body: some View { AppScreen { ScrollView { VStack(spacing: AppSpacing.section) { ScreenTitle(text: "Preferences", subtitle: "Choose your default currency, tipping preferences, and local data options."); defaultsCard; privacyCard; aboutCard }.padding(AppSpacing.screen) } }.navigationTitle("Settings").navigationBarTitleDisplayMode(.inline).onReceive(appEnvironment.$preferences) { model.preferences = $0 }.sheet(item: $activeSheet) { sheet in NavigationStack { sheetContent(sheet) } } }
    private var defaultsCard: some View { ThemedCard { Text("Defaults").appFont(.title2); SettingsButtonRow(title: "Home currency", subtitle: "Used as your default conversion currency", value: "\(currencyName(model.preferences.homeCurrencyCode)) (\(model.preferences.homeCurrencyCode))") { activeSheet = .currency }; SettingsButtonRow(title: "Default tip", subtitle: "Suggested starting percentage", value: "\(model.preferences.defaultTipPercentage)%") { activeSheet = .tip }; SettingsButtonRow(title: "Tip basis", subtitle: "How new tip calculations start", value: model.preferences.tipCalculationBasis.title) { activeSheet = .basis }; SettingsButtonRow(title: "Default people", subtitle: "Used for new guided tips and splits", value: "\(model.preferences.defaultPeopleCount)") { activeSheet = .people }; Picker("Default rounding", selection: Binding(get: { model.preferences.roundingPreference }, set: { value in updateLive { $0.roundingPreference = value } })) { ForEach(RoundingPreference.allCases) { Text($0.title).tag($0) } }; Toggle("Haptic feedback", isOn: Binding(get: { model.preferences.hapticsEnabled }, set: { value in updateLive { $0.hapticsEnabled = value } })).tint(AppTheme.accent); Picker("Appearance", selection: Binding(get: { model.preferences.appearancePreference }, set: { value in updateLive { $0.appearancePreference = value } })) { ForEach(AppearancePreference.allCases) { Text($0.title).tag($0) } }; Toggle(isOn: Binding(get: { model.preferences.showTippingExplanations }, set: { value in updateLive { $0.showTippingExplanations = value } })) { VStack(alignment: .leading, spacing: AppSpacing.xSmall) { Text("Show explanations").appFont(.body); Text("Hide optional guidance when off; warnings and validation remain visible.").appFont(.footnote).foregroundStyle(AppTheme.secondaryText) } }.tint(AppTheme.accent).accessibilityValue(model.preferences.showTippingExplanations ? "On" : "Off"); Button("Restart Onboarding") { updateLive { $0.hasCompletedOnboarding = false } }; if let status = model.statusMessage { Text(status).appFont(.footnote).foregroundStyle(AppTheme.secondaryText) } } }
    @ViewBuilder private var privacyCard: some View { ThemedCard { Text("Privacy and local data").appFont(.title2); Text("Saved calculations, receipts, notes, and preferences are stored locally on this device. Receipt text recognition uses on-device Apple Vision when scanning is available.").appFont(.body); if let url = AppLinks.privacyPolicy { Link("Privacy Policy", destination: url) } else { Label("Privacy Policy URL required before App Review", systemImage: "exclamationmark.triangle").foregroundStyle(AppTheme.highlight) }; if let url = AppLinks.support { Link("Support and Feedback", destination: url) } else { Label("Support URL required before App Review", systemImage: "exclamationmark.triangle").foregroundStyle(AppTheme.highlight) }; Text("Data export and deletion are not available in this build.").appFont(.footnote).foregroundStyle(AppTheme.highlight) } }
    private var aboutCard: some View { ThemedCard { Text("About").appFont(.title2); ResultSummaryRow(label: "App", value: "Tips for Tips"); ResultSummaryRow(label: "Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1"); ResultSummaryRow(label: "Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1") } }
    @ViewBuilder private func sheetContent(_ sheet: SettingsSheet) -> some View { switch sheet { case .currency: CurrencySelectionView(selectedCode: model.preferences.homeCurrencyCode) { code in updateLive { $0.homeCurrencyCode = code }; activeSheet = nil }; case .tip: DefaultTipEditor(value: model.preferences.defaultTipPercentage) { tip in updateLive { $0.defaultTipPercentage = tip }; activeSheet = nil }; case .basis: TipBasisEditor(value: model.preferences.tipCalculationBasis) { basis in updateLive { $0.tipCalculationBasis = basis }; activeSheet = nil }; case .people: DefaultPeopleEditor(value: model.preferences.defaultPeopleCount) { count in updateLive { $0.defaultPeopleCount = count }; activeSheet = nil } } }
    private func updateLive(_ change: @escaping (inout UserPreferences) -> Void) { Task { do { try await appEnvironment.updatePreferences(change); model.preferences = appEnvironment.preferences; model.statusMessage = "Settings updated." } catch { model.preferences = appEnvironment.preferences; model.statusMessage = "Settings could not be saved. Try again." } } }
}

struct SettingsButtonRow: View { let title: String; let subtitle: String; let value: String; let action: () -> Void; var body: some View { Button(action: action) { ViewThatFits(in: .horizontal) { HStack { labels; Spacer(minLength: AppSpacing.standard); trailing }; VStack(alignment: .leading, spacing: AppSpacing.small) { labels; trailing } } }.buttonStyle(.plain).padding(.vertical, AppSpacing.small).contentShape(Rectangle()).accessibilityLabel(title).accessibilityValue(value).accessibilityAddTraits(.isButton) }
    private var labels: some View { VStack(alignment: .leading, spacing: AppSpacing.xSmall) { Text(title).appFont(.body); Text(subtitle).appFont(.footnote).foregroundStyle(AppTheme.secondaryText) } }
    private var trailing: some View { HStack { Text(value).appFont(.body).fontWeight(.semibold).multilineTextAlignment(.leading); Image(systemName: "chevron.right").foregroundStyle(AppTheme.tertiaryText) } }
}

struct CurrencySelectionView: View { let selectedCode: String; let onSelect: (String) -> Void; @Environment(\.dismiss) private var dismiss; @State private var searchText = ""; private var currencies: [Currency] { Currency.supported.filter { currency in searchText.isEmpty || currency.code.localizedCaseInsensitiveContains(searchText) || currency.name.localizedCaseInsensitiveContains(searchText) }.sorted { $0.code < $1.code } }; var body: some View { List { if !FrankfurterSupportedCurrencies.codes.contains(selectedCode) { Section { VStack(alignment: .leading) { Text("\(selectedCode) is unsupported").font(.headline); Text("Select a supported currency for new conversions.").font(.subheadline) } } }; Section { ForEach(currencies) { currency in Button { onSelect(currency.code) } label: { HStack { VStack(alignment: .leading) { Text(currency.code).font(.headline); Text(currency.name).font(.subheadline) }; Spacer(); if currency.code == selectedCode { Image(systemName: "checkmark") } } }.accessibilityLabel("\(currency.name), \(currency.code)").accessibilityValue(currency.code == selectedCode ? "Selected" : "Not selected") } } }.navigationTitle("Home Currency").searchable(text: $searchText, prompt: "Search currencies").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } } } }
struct DefaultTipEditor: View { let value: Decimal; let onSave: (Decimal) -> Void; @Environment(\.dismiss) private var dismiss; @State private var customText = ""; private let options: [Decimal] = [15, 18, 20, 22]; var body: some View { Form { Section("Common values") { ForEach(options, id: \.self) { option in Button { onSave(option) } label: { Text(verbatim: "\(option)%") } } }; Section("Custom") { TextField("Percent", text: $customText).keyboardType(.decimalPad); Button("Done") { if let parsed = LocalizedDecimalParser.parse(customText), parsed >= 0, parsed <= 100 { onSave(parsed) } } } }.navigationTitle("Default Tip").onAppear { customText = "\(value)" }.toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } } } }
struct TipBasisEditor: View { let value: TipCalculationBasis; let onSave: (TipCalculationBasis) -> Void; @Environment(\.dismiss) private var dismiss; var body: some View { List(TipCalculationBasis.allCases) { basis in Button { onSave(basis) } label: { HStack { VStack(alignment: .leading) { Text(basis.title); Text(basis == .subtotalBeforeTax ? "Tips are based on the pre-tax subtotal." : "Tips are based on the after-tax final total.").font(.footnote) }; Spacer(); if basis == value { Image(systemName: "checkmark") } } } }.navigationTitle("Tip Basis").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } } } }
struct DefaultPeopleEditor: View { let value: Int; let onSave: (Int) -> Void; @Environment(\.dismiss) private var dismiss; @State private var count = 1; var body: some View { Form { Stepper(value: $count, in: 1...99) { Text("\(count) people") }; Button("Done") { onSave(count) } }.navigationTitle("Default People").onAppear { count = min(max(value, 1), 99) }.toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } } } }
func currencyName(_ code: String) -> String { Locale.current.localizedString(forCurrencyCode: code) ?? code }

#Preview { MainMenu() }
