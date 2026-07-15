import SwiftUI

enum AppRoute: Hashable {
    case guidedTipAssistant
    case receiptScanner(ReceiptScannerContext = .newReceipt)
    case splitCalculator(SplitCalculatorContext = .manual)
    case currencyConverter
    case history
    case tippingGuide
    case settings
    case receiptDetail(UUID)
    case calculationDetail(UUID)
    case guideSection(String)
    case legacyTipCalculator
    case legacyReceipts
    case legacyNotePad
}

struct MainMenu: View {
    @State private var migrationReport: V2MigrationReport?
    @State private var preferences = UserPreferences.defaults
    private let migrationCoordinator = V2MigrationCoordinator()
    private let preferencesRepository = FileUserPreferencesRepository()

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

                        ScreenTitle(text: "Tips for Tips", subtitle: "From bill to tip, split, save and conversion for travelers in the United States.")

                        ThemedCard {
                            Text("I have a bill").appFont(.h2)
                            Text("Get contextual tipping guidance, calculate the total and continue directly into splitting, saving or converting.")
                                .appFont(.paragraph)
                                .foregroundStyle(AppTheme.text.opacity(0.82))
                            NavigationLink(value: AppRoute.guidedTipAssistant) {
                                Label("Calculate a Tip", systemImage: "sparkles")
                                    .appFont(.h3)
                                    .frame(maxWidth: .infinity, minHeight: 52)
                            }
                            .buttonStyle(AppButtonStylePublic.primary)
                        }

                        DashboardQuickActions()

                        ThemedCard {
                            Text("Current travel defaults").appFont(.h2)
                            ResultSummaryRow(label: "Home currency", value: preferences.homeCurrencyCode)
                            ResultSummaryRow(label: "Tip basis", value: preferences.tipCalculationBasis.title)
                            ResultSummaryRow(label: "People", value: "\(preferences.defaultPeopleCount)")
                            NavigationLink("Open Settings", value: AppRoute.settings)
                                .appFont(.paragraph)
                                .foregroundStyle(AppTheme.accent)
                        }

                        if let migrationReport {
                            ThemedCard {
                                Text("V1 data migration").appFont(.h2)
                                Text(migrationReport.succeeded ? "Legacy notes and receipts were checked and backed up where present." : "Some legacy data needs review.")
                                    .appFont(.paragraph)
                                ResultSummaryRow(label: "Receipts imported", value: "\(migrationReport.migratedReceiptsCount)")
                                ResultSummaryRow(label: "Notes backed up", value: "\(migrationReport.migratedNotesCount)")
                            }
                        }

                        RecentActivityCard()

                        ThemedCard {
                            Text("V1 tools remain available").appFont(.h2)
                            VStack(alignment: .leading, spacing: AppSpacing.standard) {
                                NavigationLink("Quick Calculate", value: AppRoute.legacyTipCalculator)
                                NavigationLink("Receipts", value: AppRoute.legacyReceipts)
                                NavigationLink("Note Pad", value: AppRoute.legacyNotePad)
                            }
                            .appFont(.paragraph)
                            .foregroundStyle(AppTheme.accent)
                        }
                    }
                    .padding(AppSpacing.screen)
                }
            }
            .navigationTitle("Tips for Tips")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: AppRoute.self) { route in destination(for: route) }
        }
        .task {
            migrationReport = await migrationCoordinator.migrateIfNeeded()
            if let loaded = try? await preferencesRepository.loadPreferences() { preferences = loaded }
        }
    }

    @ViewBuilder private func destination(for route: AppRoute) -> some View {
        switch route {
        case .guidedTipAssistant: GuidedTipAssistantView()
        case let .receiptScanner(context): ReceiptScannerView(context: context)
        case .legacyReceipts: Receipts()
        case let .splitCalculator(context): SplitBillCalculator(context: context)
        case .currencyConverter: CurrencyConverter()
        case .history: HistoryView()
        case .tippingGuide: HelpfulTips()
        case .settings: SettingsPlaceholder(preferences: preferences)
        case let .receiptDetail(id): ReceiptDetailView(receiptID: id)
        case let .calculationDetail(id): CalculationDetailView(calculationID: id)
        case let .guideSection(sectionID): GuideSectionPlaceholder(sectionID: sectionID)
        case .legacyTipCalculator: TipCalculator()
        case .legacyNotePad: NotePad()
        }
    }
}

struct DashboardQuickActions: View {
    private let actions: [(String, String, AppRoute)] = [
        ("Scan Receipt", "doc.text.viewfinder", .receiptScanner()),
        ("Split a Bill", "person.2", .splitCalculator()),
        ("Convert Currency", "arrow.left.arrow.right", .currencyConverter),
        ("What Should I Tip?", "book", .tippingGuide)
    ]
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.standard) {
            Text("Quick actions").appFont(.h2)
            LazyVGrid(columns: columns, spacing: AppSpacing.standard) {
                ForEach(actions, id: \.0) { action in
                    NavigationLink(value: action.2) {
                        ThemedCard {
                            Label(action.0, systemImage: action.1)
                                .appFont(.h3)
                                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                        }
                    }
                    .accessibilityLabel(action.0)
                }
            }
        }
    }
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

    let services = TippingGuidance.services
    private let engine = TipRecommendationEngine()
    private let repository: CalculationRepository

    init(preferences: UserPreferences = .defaults, prefilledInput: TipCalculationInput? = nil, repository: CalculationRepository = FileCalculationRepository()) {
        input = prefilledInput ?? .defaults(preferences: preferences)
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
    func restart() { let currency = input.currencyCode; input = .defaults(); input.currencyCode = currency; currentStep = .service; result = nil; validationMessage = nil }

    func advance() {
        validationMessage = validate(step: currentStep)
        guard validationMessage == nil else { return }
        if currentStep == .people { calculate() } else { currentStep = GuidedTipStep(rawValue: currentStep.rawValue + 1) ?? .result }
    }

    func calculate() {
        do { result = try engine.calculate(input: input); currentStep = .result; validationMessage = nil }
        catch { validationMessage = error.localizedDescription }
    }

    func saveResult() async {
        guard let result else { return }
        do {
            let record = SavedCalculationRecord(id: UUID(), recordType: .tipOnly, tipResult: result, splitResult: nil, receiptID: nil, merchantName: nil, notes: "Guided Tip Assistant", currencyConversion: nil, shareSummary: shareSummary, createdAt: Date(), updatedAt: Date())
            try await repository.saveCalculation(record)
            saveConfirmation = "Calculation saved."
        } catch { saveConfirmation = "Could not save calculation. Please try again." }
    }

    var shareSummary: String { guard let result else { return "" }; return "Tip for \(result.service.name): \(formatMoney(result.suggestedAdditionalTip, code: result.input.currencyCode)); final total \(formatMoney(result.finalTotal, code: result.input.currencyCode))." }
    func guideRoute() -> AppRoute { .guideSection(selectedService?.guideSectionID ?? input.serviceID) }
    func splitRoute() -> AppRoute { guard let result else { return .splitCalculator() }; return .splitCalculator(.tipResult(result)) }
    func convertRoute() -> AppRoute { .currencyConverter }

    private func invalidate() { result = nil; validationMessage = nil }
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
    init(prefilledInput: TipCalculationInput? = nil) { _model = StateObject(wrappedValue: GuidedTipAssistantViewModel(prefilledInput: prefilledInput)) }
    var body: some View { AppScreen { ScrollView { VStack(spacing: AppSpacing.section) { progress; content; if let message = model.validationMessage { InlineErrorView(message: message) }; controls }.padding(AppSpacing.screen) } }.navigationTitle("Guided Tip Assistant").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }.hideKeyboardToolbar().alert("Guided Tip Assistant", isPresented: Binding(get: { model.saveConfirmation != nil }, set: { if !$0 { model.saveConfirmation = nil } })) { Button("OK", role: .cancel) {} } message: { Text(model.saveConfirmation ?? "") } }
    private var progress: some View { VStack(alignment: .leading) { Text("Step \(min(model.currentStep.rawValue + 1, 6)) of 6: \(model.currentStep.title)").appFont(.h3); ProgressView(value: Double(model.currentStep.rawValue + 1), total: 6).accessibilityValue("Step \(model.currentStep.rawValue + 1) of 6") } }
    @ViewBuilder private var content: some View { switch model.currentStep { case .service: serviceStep; case .quality: qualityStep; case .gratuity: gratuityStep; case .bill: billStep; case .people: peopleStep; case .result: resultStep } }
    private var controls: some View { HStack { if model.currentStep != .service { SecondaryButton(title: "Back", systemImage: "chevron.left") { model.back() } }; if model.currentStep != .result { PrimaryButton(title: "Continue", systemImage: "chevron.right") { model.advance() } } } }
    private var serviceStep: some View { ThemedCard { Text("What service did you receive?").appFont(.h2); TextField("Search services", text: $model.searchText).textFieldStyle(AppTextFieldStyle()); ScrollView(.horizontal, showsIndicators: false) { HStack { FilterChip(title: "All", isSelected: model.selectedCategory == nil) { model.selectedCategory = nil }; ForEach(TippingServiceCategory.allCases) { cat in FilterChip(title: cat.title, isSelected: model.selectedCategory == cat) { model.selectedCategory = cat } } } }; ForEach(model.filteredServices) { service in Button { model.selectService(service) } label: { HStack { Image(systemName: service.symbolName); VStack(alignment: .leading) { Text(service.name).appFont(.h3); Text(service.recommendationSummary).appFont(.paragraph).foregroundStyle(AppTheme.text.opacity(0.78)) }; Spacer(); Image(systemName: model.input.serviceID == service.id ? "checkmark.circle.fill" : "circle") } }.buttonStyle(.plain).padding(.vertical, 8).accessibilityValue(model.input.serviceID == service.id ? "Selected" : "Not selected") } } }
    private var qualityStep: some View { ThemedCard { Text("How was the service?").appFont(.h2); ForEach(ServiceQuality.allCases) { q in RadioButton(title: q.label, isSelected: model.input.serviceQuality == q) { model.setQuality(q) }; Text(q.guidance).appFont(.paragraph).foregroundStyle(AppTheme.text.opacity(0.75)) } } }
    private var gratuityStep: some View { ThemedCard { Text("Is gratuity already included?").appFont(.h2); HStack { ForEach(GratuityStatus.allCases) { status in RadioButton(title: status.rawValue.capitalized, isSelected: model.input.gratuityStatus == status) { model.setGratuity(status) } } }; if model.input.gratuityStatus == .yes { Picker("Included charge", selection: $model.input.includedGratuityEntryMode) { Text("Unknown").tag(IncludedGratuityEntryMode.unknown); Text("Percent").tag(IncludedGratuityEntryMode.percentage); Text("Dollars").tag(IncludedGratuityEntryMode.amount) }.pickerStyle(.segmented); if model.input.includedGratuityEntryMode == .percentage { DecimalField(title: "Included percent", value: $model.input.includedGratuityPercentage) { model.updateAmounts() } }; if model.input.includedGratuityEntryMode == .amount { DecimalField(title: "Included amount", value: $model.input.includedGratuityAmount) { model.updateAmounts() } }; Toggle("Receipt total already includes this charge", isOn: $model.input.finalTotalIncludesIncludedGratuity).appFont(.paragraph) }; if model.input.gratuityStatus == .unsure { Text("Look for gratuity, automatic gratuity, service charge, hospitality charge, administrative fee, delivery fee, and suggested gratuity. Suggested gratuity is not included; delivery fees are not automatically driver tips.").appFont(.paragraph) } } }
    private var billStep: some View { ThemedCard { Text("Bill details").appFont(.h2); DecimalField(title: "Subtotal", value: $model.input.subtotal) { model.updateAmounts() }; DecimalField(title: "Tax", value: $model.input.tax) { model.updateAmounts() }; DecimalField(title: "Final total", value: $model.input.finalTotal) { model.updateAmounts() }; TextField("Currency code", text: $model.input.currencyCode).textFieldStyle(AppTextFieldStyle()).textInputAutocapitalization(.characters); Picker("Calculation basis", selection: $model.input.calculationBasis) { ForEach(TipCalculationBasis.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented); Text(model.input.calculationBasis == .subtotalBeforeTax ? "Traditionally, restaurant tips may be calculated using the pre-tax subtotal." : "Many payment terminals calculate suggested tips using the final total.").appFont(.paragraph); serviceSpecificFields } }
    @ViewBuilder private var serviceSpecificFields: some View { if model.input.serviceID == "bell-staff" { WholeNumberField(title: "Number of bags", value: $model.input.numberOfBags) }; if model.input.serviceID == "housekeeping" { WholeNumberField(title: "Number of days", value: $model.input.numberOfHousekeepingDays) }; if model.input.serviceID == "bar" { Picker("Bar tip mode", selection: $model.input.bartenderTipMode) { Text("Percentage of tab").tag(BartenderTipMode.percentageOfTab); Text("Per drink").tag(BartenderTipMode.perDrink) }.pickerStyle(.segmented); if model.input.bartenderTipMode == .perDrink { WholeNumberField(title: "Number of drinks", value: $model.input.numberOfDrinks) } }; if model.input.serviceID == "food-delivery" { Text("Delivery difficulty").appFont(.h3); DifficultyToggle(title: "Bad weather", flag: .badWeather, selection: $model.input.foodDeliveryDifficulty); DifficultyToggle(title: "Long distance", flag: .longDistance, selection: $model.input.foodDeliveryDifficulty); DifficultyToggle(title: "Difficult entrance or stairs", flag: .difficultEntrance, selection: $model.input.foodDeliveryDifficulty); DifficultyToggle(title: "Large order", flag: .largeOrder, selection: $model.input.foodDeliveryDifficulty); DifficultyToggle(title: "Late-night delivery", flag: .lateNight, selection: $model.input.foodDeliveryDifficulty) } }
    private var peopleStep: some View { ThemedCard { Text("How many people are paying?").appFont(.h2); Stepper(value: $model.input.peopleCount, in: 1...99) { Text("\(model.input.peopleCount) people").appFont(.h2) }; Text("This creates a simple even per-person amount. Advanced allocation comes later.").appFont(.paragraph) } }
    private var resultStep: some View { VStack(spacing: AppSpacing.section) { if let r = model.result { ResultSummary(result: r); ResultActions(model: model) } else { EmptyStateView(systemImage: "exclamationmark.triangle", title: "No result", message: "Go back and calculate again.") }; SecondaryButton(title: "Start Over", systemImage: "arrow.counterclockwise") { model.restart() } } }
}

extension ServiceQuality { var label: String { rawValue.capitalized }; var guidance: String { switch self { case .poor: return "Important problems directly related to the service."; case .standard: return "Service met normal expectations."; case .good: return "Attentive and helpful service."; case .exceptional: return "Unusually thoughtful or difficult service." } } }

struct DecimalField: View { let title: String; @Binding var value: Decimal?; let onChange: () -> Void; @State private var text = ""; var body: some View { TextField(title, text: $text).keyboardType(.decimalPad).textFieldStyle(AppTextFieldStyle()).onAppear { if let value { text = "\(value)" } }.onChange(of: text) { newValue in value = LocalizedDecimalParser.parse(newValue); onChange() }.accessibilityLabel(title) } }
struct WholeNumberField: View { let title: String; @Binding var value: Int?; @State private var text = ""; var body: some View { TextField(title, text: $text).keyboardType(.numberPad).textFieldStyle(AppTextFieldStyle()).onAppear { if let value { text = "\(value)" } }.onChange(of: text) { newValue in if let int = Int(newValue), String(int) == newValue, int > 0 { value = int } else { value = nil } }.accessibilityLabel(title) } }
struct DifficultyToggle: View { let title: String; let flag: FoodDeliveryDifficulty; @Binding var selection: FoodDeliveryDifficulty; var body: some View { Toggle(title, isOn: Binding(get: { selection.contains(flag) }, set: { $0 ? selection.insert(flag) : selection.remove(flag) })).appFont(.paragraph) } }
struct ResultSummary: View { let result: TipCalculationResult; var body: some View { ThemedCard { Text("Recommended Tip").appFont(.h2); Text(result.recommendedPercentage.map { "\($0)% — \(formatMoney(result.suggestedAdditionalTip, code: result.input.currencyCode))" } ?? formatMoney(result.suggestedAdditionalTip, code: result.input.currencyCode)).appFont(.h1).foregroundStyle(AppTheme.highlight); ResultSummaryRow(label: "Final total", value: formatMoney(result.finalTotal, code: result.input.currencyCode)); ResultSummaryRow(label: "Split between \(result.input.peopleCount) people", value: "\(formatMoney(result.amountPerPerson, code: result.input.currencyCode)) each"); ResultSummaryRow(label: result.normalRange == nil ? "Customary guidance" : "Customary range", value: result.customaryGuidance); if result.input.gratuityStatus == .yes { ResultSummaryRow(label: "Included gratuity", value: formatMoney(result.includedGratuityAmount, code: result.input.currencyCode)); ResultSummaryRow(label: "Suggested additional", value: formatMoney(result.suggestedAdditionalTip, code: result.input.currencyCode)); ResultSummaryRow(label: "Combined gratuity", value: formatMoney(result.combinedGratuity, code: result.input.currencyCode)) }; Text(result.explanation).appFont(.paragraph); if let lower = result.lowerAlternative { ResultSummaryRow(label: lower.label, value: alternativeText(lower, code: result.input.currencyCode)) }; if let higher = result.higherAlternative { ResultSummaryRow(label: higher.label, value: alternativeText(higher, code: result.input.currencyCode)) } }.accessibilityElement(children: .contain) } }
struct ResultActions: View { @ObservedObject var model: GuidedTipAssistantViewModel; var body: some View { ThemedCard { Text("Next actions").appFont(.h2); NavigationLink("Split This Bill", value: model.splitRoute()); Button("Save Calculation") { Task { await model.saveResult() } }; NavigationLink("Convert Total", value: model.convertRoute()); NavigationLink("Add Receipt", value: AppRoute.receiptScanner(.attachToCalculation(model.result?.id ?? UUID()))); ShareLink(item: model.shareSummary) { Text("Share Summary") }; NavigationLink("Read Service Guide", value: model.guideRoute()) }.appFont(.paragraph).foregroundStyle(AppTheme.accent) } }
func formatMoney(_ value: Decimal, code: String) -> String { (value as NSDecimalNumber).doubleValue.formatted(.currency(code: code)) }
func alternativeText(_ alt: TipAlternative, code: String) -> String { if let p = alt.percentage { return "\(p)% — \(formatMoney(alt.amount, code: code))" }; return formatMoney(alt.amount, code: code) }

struct HistoryView: View {
    @StateObject private var model = HistoryViewModel()
    @State private var confirmDeleteAll = false
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
    private func route(for entry: HistoryEntry) -> AppRoute { switch entry.recordType { case .receipt: return .receiptDetail(entry.linkedRecordID); case .tipCalculation: return .calculationDetail(entry.linkedRecordID); case .split: return .splitCalculator() } }
}

struct HistoryRow: View { let entry: HistoryEntry; var body: some View { HStack(spacing: AppSpacing.standard) { Image(systemName: icon).foregroundStyle(AppTheme.accent).frame(width: 32).accessibilityLabel(entry.recordType == .receipt ? "Receipt thumbnail" : entry.recordType.title); VStack(alignment: .leading, spacing: 4) { Text(entry.title).appFont(.h3); Text(entry.subtitle ?? entry.recordType.title).appFont(.paragraph).foregroundStyle(AppTheme.text.opacity(0.75)); Text(entry.createdAt.formatted(date: .abbreviated, time: .omitted)).appFont(.paragraph).foregroundStyle(AppTheme.text.opacity(0.65)); if let paid = entry.paidSummary { Text(paid).appFont(.paragraph).foregroundStyle(AppTheme.highlight) } }; Spacer(); if let total = entry.totalAmount { Text(formatMoney(total, code: entry.currencyCode)).appFont(.h3) } }.accessibilityElement(children: .combine).accessibilityLabel("\(entry.title), \(entry.recordType.title), \(entry.createdAt.formatted(date: .abbreviated, time: .omitted)), \(entry.totalAmount.map { formatMoney($0, code: entry.currencyCode) } ?? "No total")") }
    private var icon: String { switch entry.recordType { case .tipCalculation: return "percent"; case .receipt: return "doc.text.image"; case .split: return "person.2" } }
}
struct EmptySearchHistoryRow: View { let clear: () -> Void; var body: some View { VStack(alignment: .leading, spacing: AppSpacing.standard) { Text("No matching history").appFont(.h2); Text("Try clearing search or resetting filters.").appFont(.paragraph); Button("Clear Search", action: clear) }.listRowBackground(AppTheme.surface) } }
struct RecentActivityCard: View { @StateObject private var model = HistoryViewModel(); var body: some View { ThemedCard { Text("Recent Activity").appFont(.h2); if model.state.entries.isEmpty { Text("Your recent calculations will appear here.").appFont(.paragraph).foregroundStyle(AppTheme.text.opacity(0.75)) } else { ForEach(Array(model.state.filteredAndSorted.prefix(3))) { entry in NavigationLink(value: entry.recordType == .receipt ? AppRoute.receiptDetail(entry.linkedRecordID) : AppRoute.history) { HStack { Image(systemName: entry.recordType == .split ? "person.2" : entry.recordType == .receipt ? "doc.text.image" : "percent"); VStack(alignment: .leading) { Text(entry.title).appFont(.h3); Text(entry.subtitle ?? entry.recordType.title).appFont(.paragraph).foregroundStyle(AppTheme.text.opacity(0.7)) }; Spacer() } } } } }.task { await model.load() } }
}

struct CalculationDetailView: View {
    let calculationID: UUID
    @State private var record: SavedCalculationRecord?
    @State private var error: String?
    private let repository = FileCalculationRepository()
    var body: some View { AppScreen { ScrollView { VStack(spacing: AppSpacing.section) { if let record, let tip = record.tipResult { ResultSummary(result: tip); ThemedCard { Text("Saved Details").appFont(.h2); ResultSummaryRow(label: "Service", value: tip.service.name); ResultSummaryRow(label: "Basis", value: tip.input.calculationBasis.title); ResultSummaryRow(label: "Currency", value: tip.input.currencyCode); ResultSummaryRow(label: "Date", value: record.createdAt.formatted(date: .abbreviated, time: .shortened)); if !record.notes.isEmpty { Text(record.notes).appFont(.paragraph) }; NavigationLink("Split this bill", value: AppRoute.splitCalculator(.tipResult(tip, sourceCalculationID: record.id))); NavigationLink("Convert", value: AppRoute.currencyConverter); NavigationLink("Open related guidance", value: AppRoute.guideSection(tip.service.guideSectionID ?? tip.service.id)); ShareLink(item: ShareSummaryBuilder().tipSummary(tip)) { Text("Share") } } } else if let record, let split = record.splitResult { SplitDetailSummary(result: split); ShareLink(item: ShareSummaryBuilder().splitSummary(split)) { Text("Share Split") } } else { EmptyStateView(systemImage: "exclamationmark.triangle", title: "Related record no longer available", message: error ?? "This saved calculation could not be found.") } }.padding(AppSpacing.screen) } }.navigationTitle("History Detail").task { await load() } }
    private func load() async { do { record = try await repository.fetchCalculations().first { $0.id == calculationID } } catch { self.error = "Saved calculation could not be loaded." } }
}
struct ReceiptDetailView: View { let receiptID: UUID; @State private var receipt: ReceiptRecord?; private let repository = FileReceiptRepository(); var body: some View { AppScreen { ScrollView { VStack(spacing: AppSpacing.section) { if let receipt { ThemedCard { Text(receipt.displayName).appFont(.h2); ResultSummaryRow(label: "Currency", value: receipt.currencyCode); if let subtotal = receipt.subtotal { ResultSummaryRow(label: "Subtotal", value: formatMoney(subtotal, code: receipt.currencyCode)) }; if let tax = receipt.tax { ResultSummaryRow(label: "Tax", value: formatMoney(tax, code: receipt.currencyCode)) }; if let total = receipt.total { ResultSummaryRow(label: "Total", value: formatMoney(total, code: receipt.currencyCode)) }; Text(receipt.notes.isEmpty ? "No notes" : receipt.notes).appFont(.paragraph); Text("Receipt images may contain merchant information, payment details, order numbers and personal notes. Share the image only when you choose to include it.").appFont(.paragraph).foregroundStyle(AppTheme.text.opacity(0.75)); ShareLink(item: ShareSummaryBuilder().receiptSummary(receipt)) { Text("Share summary only") }; NavigationLink("Calculate tip", value: AppRoute.guidedTipAssistant); NavigationLink("Split bill", value: AppRoute.splitCalculator(.receipt(receipt))); NavigationLink("Convert", value: AppRoute.currencyConverter) } } else { EmptyStateView(systemImage: "doc.text.magnifyingglass", title: "Related record no longer available", message: "This receipt could not be found.") } }.padding(AppSpacing.screen) } }.navigationTitle("Receipt").task { receipt = try? await repository.fetchReceipts().first { $0.id == receiptID } } } }
struct SplitDetailSummary: View { let result: SplitCalculationResult; var body: some View { ThemedCard { Text(result.session.name).appFont(.h2); ResultSummaryRow(label: "Original total", value: formatMoney(result.originalTotal, code: result.session.currencyCode)); ResultSummaryRow(label: "Rounded total", value: formatMoney(result.roundedCollectedTotal, code: result.session.currencyCode)); ResultSummaryRow(label: "Difference", value: formatMoney(result.roundingDifference, code: result.session.currencyCode)); ForEach(result.participantResults) { p in ResultSummaryRow(label: p.participantName + (p.isPaid ? " (paid)" : " (unpaid)"), value: formatMoney(p.finalAmount, code: result.session.currencyCode)) } } } }

struct SettingsPlaceholder: View { let preferences: UserPreferences; var body: some View { AppScreen { ScrollView { VStack(spacing: AppSpacing.section) { ScreenTitle(text: "Settings", subtitle: "Defaults now have a V2 model and repository."); ThemedCard { ResultSummaryRow(label: "Home currency", value: preferences.homeCurrencyCode); ResultSummaryRow(label: "Default tip", value: "\(preferences.defaultTipPercentage)%"); ResultSummaryRow(label: "Tip basis", value: preferences.tipCalculationBasis.title); ResultSummaryRow(label: "Default people", value: "\(preferences.defaultPeopleCount)") }; EmptyStateView(systemImage: "gearshape", title: "Editable settings coming next", message: "Phase 1 establishes source-of-truth preferences; future phases will add editable controls, privacy info and data deletion.") }.padding(AppSpacing.screen) } }.navigationTitle("Settings") } }
struct GuideSectionPlaceholder: View { let sectionID: String; var body: some View { AppScreen { EmptyStateView(systemImage: "book", title: "Guide section", message: "Deep link target: \(sectionID)") }.navigationTitle("Guide") } }

#Preview { MainMenu() }
