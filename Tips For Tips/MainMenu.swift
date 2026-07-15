import SwiftUI

enum AppRoute: Hashable {
    case guidedTipAssistant
    case receiptScanner
    case splitCalculator
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
                                NavigationLink("Tip Calculator", value: AppRoute.legacyTipCalculator)
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
        case .guidedTipAssistant: GuidedTipAssistantPlaceholder()
        case .receiptScanner, .legacyReceipts: Receipts()
        case .splitCalculator: SplitBillCalculator()
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
        ("Scan Receipt", "doc.text.viewfinder", .receiptScanner),
        ("Split a Bill", "person.2", .splitCalculator),
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

struct GuidedTipAssistantPlaceholder: View {
    var body: some View { AppScreen { ScrollView { VStack(spacing: AppSpacing.section) { ScreenTitle(text: "Guided Tip Assistant", subtitle: "Phase 1 has added the shared models, navigation, preferences and migration foundation. The guided question flow comes next in Phase 2."); EmptyStateView(systemImage: "list.bullet.clipboard", title: "Ready for Phase 2", message: "The assistant will ask about service, quality, gratuity, basis, bill amount and people count without requiring duplicate entry.") }.padding(AppSpacing.screen) } }.navigationTitle("Guided Tip Assistant") }
}

struct HistoryPlaceholder: View { var body: some View { AppScreen { EmptyStateView(systemImage: "clock", title: "History foundation ready", message: "Unified saved calculations, receipts and split records will be wired in Phase 5.") }.navigationTitle("History") } }
struct SettingsPlaceholder: View { let preferences: UserPreferences; var body: some View { AppScreen { ScrollView { VStack(spacing: AppSpacing.section) { ScreenTitle(text: "Settings", subtitle: "Defaults now have a V2 model and repository."); ThemedCard { ResultSummaryRow(label: "Home currency", value: preferences.homeCurrencyCode); ResultSummaryRow(label: "Default tip", value: "\(preferences.defaultTipPercentage)%"); ResultSummaryRow(label: "Tip basis", value: preferences.tipCalculationBasis.title); ResultSummaryRow(label: "Default people", value: "\(preferences.defaultPeopleCount)") }; EmptyStateView(systemImage: "gearshape", title: "Editable settings coming next", message: "Phase 1 establishes source-of-truth preferences; future phases will add editable controls, privacy info and data deletion.") }.padding(AppSpacing.screen) } }.navigationTitle("Settings") } }
struct GuideSectionPlaceholder: View { let sectionID: String; var body: some View { AppScreen { EmptyStateView(systemImage: "book", title: "Guide section", message: "Deep link target: \(sectionID)") }.navigationTitle("Guide") } }

#Preview { MainMenu() }
