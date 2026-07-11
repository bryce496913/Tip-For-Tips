import SwiftUI

struct MainMenu: View {
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]
    private let menuItems: [MenuItem] = [
        .init(title: "Tip Calculator", imageName: "TipCalculator", destination: AnyView(TipCalculator())),
        .init(title: "Split Bill", imageName: "SplitBillCalculator", destination: AnyView(SplitBillCalculator())),
        .init(title: "Currency Converter", imageName: "CurrencyConverter", destination: AnyView(CurrencyConverter())),
        .init(title: "Receipts", imageName: "Receipts", destination: AnyView(Receipts())),
        .init(title: "Note Pad", imageName: "NotePad", destination: AnyView(NotePad())),
        .init(title: "Helpful Tips", imageName: "HelpfulTips", destination: AnyView(HelpfulTips()))
    ]

    var body: some View {
        NavigationStack {
            AppScreen {
                ScrollView {
                    VStack(spacing: 24) {
                        Image("MainLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 220, height: 220)
                            .accessibilityHidden(true)

                        ScreenTitle(text: "Tips for Tips")

                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(menuItems) { item in
                                NavigationLink(destination: item.destination) {
                                    ThemedCard {
                                        VStack(spacing: 10) {
                                            Image(item.imageName)
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .frame(width: 88, height: 88)
                                                .accessibilityHidden(true)
                                            Text(item.title)
                                                .appFont(.h3)
                                                .foregroundStyle(AppTheme.text)
                                                .multilineTextAlignment(.center)
                                        }
                                        .frame(maxWidth: .infinity, minHeight: 132)
                                    }
                                }
                                .accessibilityLabel(item.title)
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct MenuItem: Identifiable {
    let id = UUID()
    let title: String
    let imageName: String
    let destination: AnyView
}

#Preview {
    MainMenu()
}
