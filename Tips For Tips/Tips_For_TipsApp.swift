import SwiftUI

@MainActor
final class AppEnvironment: ObservableObject {
    @Published private(set) var preferences: UserPreferences = .defaults
    @Published private(set) var isLoaded = false
    let preferencesRepository: UserPreferencesRepository
    let receiptRepository: ReceiptRepository
    let calculationRepository: CalculationRepository
    let currencyRateRepository: CurrencyRateRepository

    init(preferencesRepository: UserPreferencesRepository = FileUserPreferencesRepository(), receiptRepository: ReceiptRepository = FileReceiptRepository(), calculationRepository: CalculationRepository = FileCalculationRepository(), currencyRateRepository: CurrencyRateRepository = FileCurrencyRateRepository()) {
        self.preferencesRepository = preferencesRepository; self.receiptRepository = receiptRepository; self.calculationRepository = calculationRepository; self.currencyRateRepository = currencyRateRepository
    }
    func load() async { preferences = (try? await preferencesRepository.loadPreferences())?.validated ?? .defaults; isLoaded = true }
    func updatePreferences(_ mutation: (inout UserPreferences) -> Void) async throws { var updated = preferences; mutation(&updated); updated = updated.validated; try await preferencesRepository.savePreferences(updated); preferences = updated }
}

@main
struct Tips_For_TipsApp: App {
    @StateObject private var appEnvironment = AppEnvironment()
    var body: some Scene {
        WindowGroup {
            Group { if appEnvironment.isLoaded { MainMenu() } else { ProgressView("Loading…").task { await appEnvironment.load() } } }
                .environmentObject(appEnvironment)
                .preferredColorScheme(.dark)
        }
    }
}
