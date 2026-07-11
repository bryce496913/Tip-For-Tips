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
                        Text("Amount").appFont(.h2)
                        TextField("0.00", text: $viewModel.amountText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(AppTextFieldStyle())
                            .accessibilityLabel("Amount to convert")
                        if viewModel.parsedAmount == nil && !viewModel.amountText.isEmpty {
                            Text("Use a positive decimal amount.").appFont(.paragraph).foregroundStyle(AppTheme.highlight)
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
                selection: kind == .source ? $viewModel.sourceCurrency : $viewModel.destinationCurrency
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
            ThemedCard { HStack { ProgressView().tint(AppTheme.accent); Text("Loading the latest exchange rate…").appFont(.paragraph) } }
        case .success:
            EmptyView()
        case .failure(let message):
            ThemedCard {
                Label("Currency data unavailable", systemImage: "exclamationmark.triangle.fill").appFont(.h2).foregroundStyle(AppTheme.highlight)
                Text(message).appFont(.paragraph).fixedSize(horizontal: false, vertical: true)
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
                    Text(currency.flag ?? "").appFont(.h1).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: AppSpacing.small) {
                        Text(title).appFont(.paragraph).foregroundStyle(AppTheme.text.opacity(0.75))
                        Text(currency.code).appFont(.h1)
                        Text(currency.name).appFont(.paragraph).foregroundStyle(AppTheme.text.opacity(0.85))
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
    var body: some View {
        ThemedCard {
            Text("Conversion Result").appFont(.h2)
            Text("\(viewModel.formattedCurrency(result.enteredAmount, code: result.from.code)) \(result.from.code)").appFont(.h3)
            Text("\(viewModel.formattedCurrency(result.convertedAmount, code: result.to.code)) \(result.to.code)").appFont(.h1).foregroundStyle(AppTheme.highlight)
            Text("1 \(result.from.code) = \(viewModel.formattedRate(result.rate)) \(result.to.code)").appFont(.paragraph)
            Text("\(result.isCached ? "Cached" : "Last updated") \(result.timestamp.formatted(date: .abbreviated, time: .shortened))").appFont(.paragraph).foregroundStyle(AppTheme.text.opacity(0.75))
        }
        .accessibilityElement(children: .combine)
    }
}

private struct CurrencySelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let currencies: [Currency]
    @Binding var selection: Currency
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
                            VStack(alignment: .leading) { Text(currency.code).appFont(.h3); Text(currency.name).appFont(.paragraph).foregroundStyle(AppTheme.text.opacity(0.75)) }
                            Spacer()
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
