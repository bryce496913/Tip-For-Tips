import SwiftUI

struct CurrencyConverter: View {
    @StateObject private var viewModel = CurrencyConverterViewModel()
    @State private var selector: CurrencySelectorKind?
    @AccessibilityFocusState private var resultFocused: Bool

    var body: some View {
        AppScreen {
            ScrollView {
                VStack(spacing: AppSpacing.section) {
                    ScreenTitle(text: "Currency Converter", subtitle: "Enter an amount, choose currencies, then convert with the latest available rate.")

                    ThemedCard {
                        Text("Amount").appFont(.title2)
                        TextField("0.00", text: $viewModel.amountText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(AppTextFieldStyle())
                            .accessibilityLabel("Amount to convert")
                        if viewModel.parsedAmount == nil && !viewModel.amountText.isEmpty {
                            Text("Use a positive decimal amount.").appFont(.body).foregroundStyle(AppTheme.highlight)
                        }
                    }

                    VStack(spacing: AppSpacing.standard) {
                        CurrencySelectionButton(title: "From", currency: viewModel.sourceCurrency) { selector = .source }
                        Button { viewModel.swapCurrencies() } label: {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.headline)
                                .foregroundStyle(AppTheme.text)
                                .frame(width: 48, height: 48)
                                .background(AppTheme.accent)
                                .clipShape(Circle())
                        }
                        .accessibilityLabel("Swap currencies")
                        CurrencySelectionButton(title: "To", currency: viewModel.destinationCurrency) { selector = .destination }
                    }

                    PrimaryButton(title: convertingTitle, systemImage: convertingImage, isDisabled: !viewModel.canConvert) { viewModel.convert() }

                    feedbackView

                    if !viewModel.recentPairs.isEmpty { RecentCurrencyPairsView(viewModel: viewModel) }

                    if let result = viewModel.result {
                        ResultCard(viewModel: viewModel, result: result)
                            .accessibilityFocused($resultFocused)
                            .onAppear { resultFocused = true }
                    }
                }
                .padding(AppSpacing.screen)
            }
        }
        .navigationTitle("Currency Converter")
        .navigationBarTitleDisplayMode(.inline)
        .hideKeyboardToolbar()
        .sheet(item: $selector) { kind in
            CurrencySelectionSheet(
                title: kind == .source ? "Source Currency" : "Destination Currency",
                currencies: viewModel.currencies,
                selection: kind == .source ? $viewModel.sourceCurrency : $viewModel.destinationCurrency,
                isFavorite: { viewModel.isFavorite($0) },
                toggleFavorite: { viewModel.toggleFavorite($0) }
            )
        }
    }

    private var convertingTitle: String { if case .loading = viewModel.state { return "Converting…" }; return "Convert" }
    private var convertingImage: String? { if case .loading = viewModel.state { return nil }; return "arrow.right.circle" }

    @ViewBuilder private var feedbackView: some View {
        switch viewModel.state {
        case .idle:
            if viewModel.result == nil { EmptyStateView(systemImage: "network", title: "Ready to convert", message: "Exchange-rate data will load when you tap Convert.") }
        case .loading:
            ThemedCard { HStack { ProgressView().tint(AppTheme.accent); Text("Loading the latest exchange rate…").appFont(.body) } }
        case .success:
            EmptyView()
        case .failure(let message):
            ThemedCard {
                Label("Currency data unavailable", systemImage: "exclamationmark.triangle.fill").appFont(.title2).foregroundStyle(AppTheme.highlight)
                Text(message).appFont(.body).fixedSize(horizontal: false, vertical: true)
                SecondaryButton(title: "Retry", systemImage: "arrow.clockwise", isDisabled: !viewModel.canConvert) { viewModel.convert() }
            }
        }
    }
}

private enum CurrencySelectorKind: String, Identifiable { case source, destination; var id: String { rawValue } }

private struct CurrencySelectionButton: View {
    let title: String; let currency: Currency; let action: () -> Void
    var body: some View {
        Button(action: action) {
            ThemedCard {
                HStack(spacing: AppSpacing.standard) {
                    Text(currency.flag ?? "").appFont(.title).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: AppSpacing.small) {
                        Text(title).appFont(.body).foregroundStyle(AppTheme.secondaryText)
                        Text(currency.code).appFont(.title)
                        Text(currency.name).appFont(.body).foregroundStyle(AppTheme.text.opacity(0.85))
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").foregroundStyle(AppTheme.accent).accessibilityHidden(true)
                }
            }
        }
        .accessibilityLabel("\(title) currency")
        .accessibilityValue("\(currency.code), \(currency.name)")
    }
}

private struct ResultCard: View {
    @ObservedObject var viewModel: CurrencyConverterViewModel
    let result: ConversionResult
    private var rateDescription: String {
        let prefix = result.isCached ? "Cached rate" : "Rate"
        if let rateDate = result.rateDate { return "\(prefix) date: \(rateDate.formatted(date: .abbreviated, time: .omitted))" }
        return "\(prefix) fetched: \(result.fetchedAt.formatted(date: .abbreviated, time: .shortened))"
    }
    var body: some View {
        ThemedCard {
            Text("Conversion Result").appFont(.title2)
            Text("\(viewModel.formattedCurrency(result.enteredAmount, code: result.from.code)) \(result.from.code)").appFont(.headline)
            Text("\(viewModel.formattedCurrency(result.convertedAmount, code: result.to.code)) \(result.to.code)").appFont(.title).foregroundStyle(AppTheme.highlight)
            Text("1 \(result.from.code) = \(viewModel.formattedRate(result.rate)) \(result.to.code)").appFont(.body)
            if viewModel.multiValueLines.count > 1 { ForEach(viewModel.multiValueLines) { line in ResultSummaryRow(label: line.label, value: "\(viewModel.formattedCurrency(line.sourceAmount, code: result.from.code)) → \(viewModel.formattedCurrency(line.convertedAmount, code: result.to.code))") } }
            Text(rateDescription).appFont(.body).foregroundStyle(AppTheme.secondaryText)
            ShareLink(item: ShareSummaryBuilder().currencySummary(source: ConvertibleAmount(id: "amount", label: "Amount", amount: result.enteredAmount), converted: result.convertedAmount, rate: result.rate, from: result.from.code, to: result.to.code, fetchedAt: result.fetchedAt, cached: result.isCached)) { Text("Share Conversion") }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct RecentCurrencyPairsView: View { @ObservedObject var viewModel: CurrencyConverterViewModel; var body: some View { ThemedCard { HStack { Text("Recent pairs").appFont(.title2); Spacer(); Button("Clear") { viewModel.clearRecentPairs() } }; ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(viewModel.recentPairs) { pair in Button("\(pair.sourceCode) → \(pair.destinationCode)") { viewModel.usePair(pair) }.buttonStyle(.bordered) } } } } } }

private struct CurrencySelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let currencies: [Currency]
    @Binding var selection: Currency
    let isFavorite: (Currency) -> Bool
    let toggleFavorite: (Currency) -> Void
    @State private var searchText = ""

    private var filtered: [Currency] {
        guard !searchText.isEmpty else { return currencies }
        return currencies.filter { $0.code.localizedCaseInsensitiveContains(searchText) || $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            AppScreen {
                List(filtered) { currency in
                    Button { selection = currency; dismiss() } label: {
                        HStack {
                            Text(currency.flag ?? "").accessibilityHidden(true)
                            VStack(alignment: .leading) { Text(currency.code).appFont(.headline); Text(currency.name).appFont(.body).foregroundStyle(AppTheme.secondaryText) }
                            Spacer()
                            Button { toggleFavorite(currency) } label: { Image(systemName: isFavorite(currency) ? "star.fill" : "star") }.accessibilityLabel(isFavorite(currency) ? "Unfavorite currency" : "Favorite currency")
                            if currency == selection { Image(systemName: "checkmark.circle.fill").foregroundStyle(AppTheme.highlight) }
                        }
                    }
                    .listRowBackground(AppTheme.surface)
                    .foregroundStyle(AppTheme.text)
                }
                .searchable(text: $searchText, prompt: "Search code or name")
            }
            .navigationTitle(title)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview { NavigationStack { CurrencyConverter() } }
