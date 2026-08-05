import SwiftUI

@MainActor
final class AppEnvironment: ObservableObject {
    @Published private(set) var preferences: UserPreferences = .defaults
    @Published private(set) var isLoaded = false
    @Published private(set) var startupError: String?
    @Published private(set) var migrationRecoveryIssues: [MigrationRecoveryIssue] = []
    let preferencesRepository: UserPreferencesRepository
    let receiptRepository: ReceiptRepository
    let calculationRepository: CalculationRepository
    let currencyRateRepository: CurrencyRateRepository
    let migrationCoordinator: V2MigrationCoordinator
    let dataService: (any AppDataExporting & AppDataManaging)

    init(preferencesRepository: UserPreferencesRepository = FileUserPreferencesRepository(), receiptRepository: ReceiptRepository = FileReceiptRepository(), calculationRepository: CalculationRepository = FileCalculationRepository(), currencyRateRepository: CurrencyRateRepository = FileCurrencyRateRepository(), migrationCoordinator: V2MigrationCoordinator? = nil) {
        self.preferencesRepository = preferencesRepository; self.receiptRepository = receiptRepository; self.calculationRepository = calculationRepository; self.currencyRateRepository = currencyRateRepository
        self.migrationCoordinator = migrationCoordinator ?? V2MigrationCoordinator(receiptRepository: receiptRepository)
        self.dataService = FileAppDataService(receiptRepository: receiptRepository, calculationRepository: calculationRepository, preferencesRepository: preferencesRepository)
    }
    /// Migration must finish before preferences are published and workflows become reachable.
    func prepare() async {
        isLoaded = false; startupError = nil
        let report = await migrationCoordinator.migrateIfNeeded()
        guard report.succeeded else { migrationRecoveryIssues = await migrationCoordinator.recoveryIssues; startupError = report.partialFailures.joined(separator: "\n"); return }
        do { preferences = (try await preferencesRepository.loadPreferences()).validated; if ProcessInfo.processInfo.arguments.contains("-ui-testing") { preferences.hasCompletedOnboarding = true }; migrationRecoveryIssues = []; isLoaded = true }
        catch { startupError = error.localizedDescription }
    }
    func updatePreferences(_ mutation: (inout UserPreferences) -> Void) async throws { var updated = preferences; mutation(&updated); updated = updated.validated; try await preferencesRepository.savePreferences(updated); preferences = updated }
    func quarantineAndRetry(_ issue: MigrationRecoveryIssue) async { do { try await migrationCoordinator.quarantine(issue, appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown", build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"); await prepare() } catch { startupError = "The unreadable legacy source could not be quarantined. Try again or export recovery details." } }
    func resetAfterDataDeletion() async { await prepare() }
    func deleteAndRetry(_ issue: MigrationRecoveryIssue) async { do { try await migrationCoordinator.deleteSource(issue); await prepare() } catch { startupError = "The selected unreadable legacy source could not be deleted." } }
}

@main
struct Tips_For_TipsApp: App {
    @StateObject private var appEnvironment = AppEnvironment()
    var body: some Scene {
        WindowGroup {
            Group {
                if appEnvironment.isLoaded && appEnvironment.preferences.hasCompletedOnboarding { MainMenu() }
                else if appEnvironment.isLoaded { OnboardingView() }
                else if appEnvironment.startupError != nil { MigrationRecoveryView() }
                else { ProgressView("Preparing local data…").task { await appEnvironment.prepare() } }
            }
                .environmentObject(appEnvironment)
                .preferredColorScheme(appEnvironment.preferences.appearancePreference.colorScheme)
        }
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var errorMessage: String?
    var body: some View {
        AppScreen {
            VStack(spacing: AppSpacing.section) {
                Spacer()
                Image("MainLogo").resizable().scaledToFit().frame(maxWidth: 260).accessibilityHidden(true)
                ScreenTitle(text: "Tips for Tips", subtitle: "Calculate tips, review receipt-detected charges, split bills, and keep optional records locally on this device.")
                ThemedCard {
                    Label("Receipt recognition runs on device", systemImage: "lock.shield")
                    Label("Detected gratuity must be reviewed", systemImage: "checkmark.seal")
                    Label("No account is required", systemImage: "person.crop.circle.badge.xmark")
                }
                PrimaryButton(title: "Continue", systemImage: "arrow.right") {
                    Task { do { try await environment.updatePreferences { $0.hasCompletedOnboarding = true } } catch { errorMessage = "Onboarding could not be completed. Try again." } }
                }
                Spacer()
            }.padding(AppSpacing.screen)
        }.alert("Onboarding", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
    }
}

struct MigrationRecoveryView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var selectedIssue: MigrationRecoveryIssue?
    @State private var deleteIssue: MigrationRecoveryIssue?
    var body: some View { NavigationStack { List { Section { Text("Valid Tips for Tips V2 data is kept in place. Choose how to handle only the unreadable legacy source.") }; ForEach(environment.migrationRecoveryIssues) { issue in VStack(alignment: .leading) { Text(issue.sourceKind.rawValue).font(.headline); Text(issue.message); Text(issue.backupAvailable ? "Migration backup available" : "No migration backup is currently available").font(.caption); Button("View Recovery Details") { selectedIssue = issue }; Button("Quarantine Unreadable Legacy Data and Continue") { Task { await environment.quarantineAndRetry(issue) } }; Button("Delete Unreadable Legacy Source", role: .destructive) { deleteIssue = issue } } }; Section { Button("Retry Migration") { Task { await environment.prepare() } } } }.navigationTitle("Migration Recovery").sheet(item: $selectedIssue) { issue in NavigationStack { Form { LabeledContent("Legacy data", value: issue.sourceKind.rawValue); LabeledContent("Source", value: issue.sourceRelativePath); LabeledContent("Backup", value: issue.backupAvailable ? "Available" : "Not available"); Text("Recommended: quarantine the unreadable source, then allow migration to continue.") }.navigationTitle("Recovery Details") } }.confirmationDialog("Delete only this unreadable legacy source?", isPresented: Binding(get: { deleteIssue != nil }, set: { if !$0 { deleteIssue = nil } })) { Button("Delete Source", role: .destructive) { if let issue = deleteIssue { Task { await environment.deleteAndRetry(issue) } }; deleteIssue = nil }; Button("Cancel", role: .cancel) {} } message: { Text("Valid V2 data and existing migration backups remain. Recovery from this legacy source may no longer be possible.") } } }
}

private extension AppearancePreference {
    var colorScheme: ColorScheme? { switch self { case .system: return nil; case .dark: return .dark; case .light: return .light } }
}
