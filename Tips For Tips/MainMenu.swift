import SwiftUI

enum AppRoute: String, CaseIterable, Identifiable, Hashable {
    case tipCalculator, splitBill, currencyConverter, receipts, notePad, helpfulTips
    var id: String { rawValue }
    var title: String { switch self { case .tipCalculator: return "Tip Calculator"; case .splitBill: return "Split Bill"; case .currencyConverter: return "Currency Converter"; case .receipts: return "Receipts"; case .notePad: return "Note Pad"; case .helpfulTips: return "Helpful Tips" } }
    var imageName: String { switch self { case .tipCalculator: return "TipCalculator"; case .splitBill: return "SplitBillCalculator"; case .currencyConverter: return "CurrencyConverter"; case .receipts: return "Receipts"; case .notePad: return "NotePad"; case .helpfulTips: return "HelpfulTips" } }
}

struct MainMenu: View {
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]
    var body: some View {
        NavigationStack { AppScreen { ScrollView { VStack(spacing: 24) { Image("MainLogo").resizable().aspectRatio(contentMode: .fit).frame(width: 220, height: 220).accessibilityHidden(true); ScreenTitle(text: "Tips for Tips"); LazyVGrid(columns: columns, spacing: 16) { ForEach(AppRoute.allCases) { route in NavigationLink(value: route) { ThemedCard { VStack(spacing: 10) { Image(route.imageName).resizable().aspectRatio(contentMode: .fit).frame(width: 88, height: 88).accessibilityHidden(true); Text(route.title).appFont(.h3).foregroundStyle(AppTheme.text).multilineTextAlignment(.center) }.frame(maxWidth: .infinity, minHeight: 132) } }.accessibilityLabel(route.title) } } }.padding(20) } }.navigationBarTitleDisplayMode(.inline).navigationDestination(for: AppRoute.self) { route in destination(for: route) } }
    }
    @ViewBuilder private func destination(for route: AppRoute) -> some View { switch route { case .tipCalculator: TipCalculator(); case .splitBill: SplitBillCalculator(); case .currencyConverter: CurrencyConverter(); case .receipts: Receipts(); case .notePad: NotePad(); case .helpfulTips: HelpfulTips() } }
}
#Preview { MainMenu() }
