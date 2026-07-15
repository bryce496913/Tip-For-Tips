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

                        EmptyStateView(systemImage: "clock.arrow.circlepath", title: "No recent calculations yet", message: "Your most recent V2 calculation and saved receipts will appear here after Phase 2 and history integration.")

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
        case .history: HistoryPlaceholder()
        case .tippingGuide: HelpfulTips()
        case .settings: SettingsPlaceholder(preferences: preferences)
        case .receiptDetail: Receipts()
        case .calculationDetail: HistoryPlaceholder()
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

struct HistoryPlaceholder: View { var body: some View { AppScreen { EmptyStateView(systemImage: "clock", title: "History foundation ready", message: "Unified saved calculations, receipts and split records will be wired in Phase 5.") }.navigationTitle("History") } }
struct SettingsPlaceholder: View { let preferences: UserPreferences; var body: some View { AppScreen { ScrollView { VStack(spacing: AppSpacing.section) { ScreenTitle(text: "Settings", subtitle: "Defaults now have a V2 model and repository."); ThemedCard { ResultSummaryRow(label: "Home currency", value: preferences.homeCurrencyCode); ResultSummaryRow(label: "Default tip", value: "\(preferences.defaultTipPercentage)%"); ResultSummaryRow(label: "Tip basis", value: preferences.tipCalculationBasis.title); ResultSummaryRow(label: "Default people", value: "\(preferences.defaultPeopleCount)") }; EmptyStateView(systemImage: "gearshape", title: "Editable settings coming next", message: "Phase 1 establishes source-of-truth preferences; future phases will add editable controls, privacy info and data deletion.") }.padding(AppSpacing.screen) } }.navigationTitle("Settings") } }
struct GuideSectionPlaceholder: View { let sectionID: String; var body: some View { AppScreen { EmptyStateView(systemImage: "book", title: "Guide section", message: "Deep link target: \(sectionID)") }.navigationTitle("Guide") } }

#Preview { MainMenu() }
