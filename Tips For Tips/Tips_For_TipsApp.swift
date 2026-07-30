import SwiftUI

@MainActor
final class AppEnvironment: ObservableObject {
    @Published private(set) var preferences: UserPreferences = .defaults
    @Published private(set) var isLoaded = false
    @Published private(set) var startupError: String?
    let preferencesRepository: UserPreferencesRepository
    let receiptRepository: ReceiptRepository
    let calculationRepository: CalculationRepository
    let currencyRateRepository: CurrencyRateRepository
    let migrationCoordinator: V2MigrationCoordinator

    init(preferencesRepository: UserPreferencesRepository = FileUserPreferencesRepository(), receiptRepository: ReceiptRepository = FileReceiptRepository(), calculationRepository: CalculationRepository = FileCalculationRepository(), currencyRateRepository: CurrencyRateRepository = FileCurrencyRateRepository(), migrationCoordinator: V2MigrationCoordinator? = nil) {
        self.preferencesRepository = preferencesRepository; self.receiptRepository = receiptRepository; self.calculationRepository = calculationRepository; self.currencyRateRepository = currencyRateRepository
        self.migrationCoordinator = migrationCoordinator ?? V2MigrationCoordinator(receiptRepository: receiptRepository)
    }
    /// Migration must finish before preferences are published and workflows become reachable.
    func prepare() async {
        isLoaded = false; startupError = nil
        let report = await migrationCoordinator.migrateIfNeeded()
        guard report.succeeded else { startupError = report.partialFailures.joined(separator: "\n"); return }
        do { preferences = (try await preferencesRepository.loadPreferences()).validated; isLoaded = true }
        catch { startupError = error.localizedDescription }
    }
    func updatePreferences(_ mutation: (inout UserPreferences) -> Void) async throws { var updated = preferences; mutation(&updated); updated = updated.validated; try await preferencesRepository.savePreferences(updated); preferences = updated }
}

@main
struct Tips_For_TipsApp: App {
    @StateObject private var appEnvironment = AppEnvironment()
    var body: some Scene {
        WindowGroup {
            Group {
                if appEnvironment.isLoaded { MainMenu() }
                else if let error = appEnvironment.startupError { VStack(spacing: 16) { Text("Local data needs attention").font(.headline); Text(error).multilineTextAlignment(.center); Button("Retry") { Task { await appEnvironment.prepare() } } }.padding() }
                else { ProgressView("Preparing local data…").task { await appEnvironment.prepare() } }
            }
                .environmentObject(appEnvironment)
                .preferredColorScheme(appEnvironment.preferences.appearancePreference.colorScheme)
        }
    }
}

private extension AppearancePreference {
    var colorScheme: ColorScheme? { switch self { case .system: return nil; case .dark: return .dark; case .light: return .light } }
}
