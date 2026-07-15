import SwiftUI

enum AppTheme {
    static let background = Color.black
    static let surface = Color(red: 0.12, green: 0.04, blue: 0.2)
    static let accent = Color(red: 0.72, green: 0.29, blue: 0.95)
    static let highlight = Color(red: 0.98, green: 0.32, blue: 0.67)
    static let text = Color.white
    static let secondaryText = Color.white.opacity(0.72)
    static let tertiaryText = Color.white.opacity(0.52)
    static let border = Color.white.opacity(0.14)
    static let disabled = Color.white.opacity(0.28)
    static let success = Color.green
    static let warning = Color.orange
    static let error = Color.red
}

enum TipInputMode: String, CaseIterable, Identifiable {
    case percentage
    case fixedAmount

    var id: String { rawValue }

    var shortTitle: String {
        switch self { case .percentage: return "%"; case .fixedAmount: return "$" }
    }

    var title: String {
        switch self { case .percentage: return "Percentage"; case .fixedAmount: return "Fixed Amount" }
    }
}

enum AppSpacing {
    static let xSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let standard: CGFloat = 16
    static let large: CGFloat = 24
    static let xLarge: CGFloat = 32
    static let screen: CGFloat = 20
    static let section: CGFloat = 24
    static let corner: CGFloat = AppRadius.large
}

enum AppRadius {
    static let small: CGFloat = 10
    static let medium: CGFloat = 14
    static let large: CGFloat = 20
}

enum AppTextStyle {
    case largeTitle
    case title
    case title2
    case headline
    case body
    case callout
    case subheadline
    case footnote
    case caption

    var font: Font {
        switch self {
        case .largeTitle: return .appLargeTitle
        case .title: return .appTitle
        case .title2: return .appTitle2
        case .headline: return .appHeadline
        case .body: return .appBody
        case .callout: return .appCallout
        case .subheadline: return .appSubheadline
        case .footnote: return .appFootnote
        case .caption: return .appCaption
        }
    }
}

extension Font {
    static let appLargeTitle = Font.system(.largeTitle, design: .rounded, weight: .bold)
    static let appTitle = Font.system(.title, design: .rounded, weight: .bold)
    static let appTitle2 = Font.system(.title2, design: .rounded, weight: .semibold)
    static let appHeadline = Font.system(.headline, design: .rounded, weight: .semibold)
    static let appBody = Font.system(.body, design: .default, weight: .regular)
    static let appCallout = Font.system(.callout, design: .default, weight: .regular)
    static let appSubheadline = Font.system(.subheadline, design: .default, weight: .regular)
    static let appFootnote = Font.system(.footnote, design: .default, weight: .regular)
    static let appCaption = Font.system(.caption, design: .default, weight: .regular)
    static let appMoneyPrimary = Font.system(.largeTitle, design: .rounded, weight: .bold)
    static let appMoneySecondary = Font.system(.title2, design: .rounded, weight: .semibold)
}

extension View {
    func appFont(_ style: AppTextStyle) -> some View { font(style.font) }

    func appNavigationStyle() -> some View {
        toolbarBackground(AppTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .tint(AppTheme.accent)
    }

    func hideKeyboardToolbar() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                    .foregroundStyle(AppTheme.accent)
            }
        }
    }
}

struct AppScreen<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        ZStack { AppTheme.background.ignoresSafeArea(); content }
            .foregroundStyle(AppTheme.text)
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .appNavigationStyle()
    }
}

struct ScreenTitle: View {
    let text: String
    var subtitle: String?
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text(text).appFont(.title).multilineTextAlignment(.leading).accessibilityAddTraits(.isHeader)
            if let subtitle { Text(subtitle).appFont(.body).foregroundStyle(AppTheme.secondaryText).multilineTextAlignment(.leading).lineSpacing(3).fixedSize(horizontal: false, vertical: true) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(AppTheme.text)
    }
}

struct ThemedCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.standard) { content }
            .padding(AppSpacing.standard)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous).stroke(AppTheme.border, lineWidth: 1))
    }
}

struct PrimaryButton: View {
    let title: String; var systemImage: String?; var isDisabled = false; let action: () -> Void
    var body: some View { Button(action: action) { label }.buttonStyle(AppButtonStyle(background: AppTheme.accent, outlined: false)).disabled(isDisabled).opacity(isDisabled ? 0.55 : 1) }
    @ViewBuilder private var label: some View { if let systemImage { Label(title, systemImage: systemImage).appFont(.headline).frame(maxWidth: .infinity, minHeight: 50) } else { Text(title).appFont(.headline).frame(maxWidth: .infinity, minHeight: 50) } }
}

struct SecondaryButton: View {
    let title: String; var systemImage: String?; var isDisabled = false; let action: () -> Void
    var body: some View { Button(action: action) { label }.buttonStyle(AppButtonStyle(background: AppTheme.surface, outlined: true)).disabled(isDisabled).opacity(isDisabled ? 0.55 : 1) }
    @ViewBuilder private var label: some View { if let systemImage { Label(title, systemImage: systemImage).appFont(.headline).frame(maxWidth: .infinity, minHeight: 50) } else { Text(title).appFont(.headline).frame(maxWidth: .infinity, minHeight: 50) } }
}

struct DestructiveButton: View {
    let title: String; var systemImage: String?; let action: () -> Void
    var body: some View { Button(action: action) { if let systemImage { Label(title, systemImage: systemImage).appFont(.headline).frame(maxWidth: .infinity, minHeight: 50) } else { Text(title).appFont(.headline).frame(maxWidth: .infinity, minHeight: 50) } }.buttonStyle(AppButtonStyle(background: AppTheme.error, outlined: false)) }
}

private struct AppButtonStyle: ButtonStyle {
    let background: Color; let outlined: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(AppTheme.text).padding(.horizontal, AppSpacing.standard).padding(.vertical, AppSpacing.xSmall)
            .background(outlined ? background.opacity(configuration.isPressed ? 0.65 : 1) : background.opacity(configuration.isPressed ? 0.72 : 1))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous).stroke(outlined ? AppTheme.accent : Color.clear, lineWidth: 1))
            .scaleEffect(!reduceMotion && configuration.isPressed ? 0.98 : 1)
    }
}

struct AppTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration.appFont(.body).foregroundStyle(AppTheme.text).padding(.horizontal, 14).frame(minHeight: 50).background(AppTheme.surface)
            .overlay(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous).stroke(AppTheme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
    }
}

struct EmptyStateView: View {
    let systemImage: String; let title: String; let message: String
    var body: some View { VStack(spacing: AppSpacing.standard) { Image(systemName: systemImage).font(.title2).foregroundStyle(AppTheme.highlight); Text(title).appFont(.title2); Text(message).appFont(.body).foregroundStyle(AppTheme.secondaryText).multilineTextAlignment(.center).lineSpacing(3) }.frame(maxWidth: .infinity).padding(AppSpacing.large) }
}

enum AppCornerRadius {
    static let small: CGFloat = AppRadius.small
    static let card: CGFloat = AppRadius.large
    static let large: CGFloat = 22
}

struct ResultSummaryRow: View {
    let label: String
    let value: String
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).appFont(.callout).foregroundStyle(AppTheme.secondaryText)
                Spacer(minLength: AppSpacing.standard)
                Text(value).appFont(.headline).foregroundStyle(AppTheme.text).monospacedDigit().multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text(label).appFont(.callout).foregroundStyle(AppTheme.secondaryText)
                Text(value).appFont(.headline).foregroundStyle(AppTheme.text).monospacedDigit().fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct InlineErrorView: View {
    let message: String
    var body: some View { Label(message, systemImage: "exclamationmark.triangle").appFont(.body).foregroundStyle(AppTheme.error).fixedSize(horizontal: false, vertical: true) }
}

struct LoadingStateView: View {
    let message: String
    var body: some View { HStack(spacing: AppSpacing.medium) { ProgressView(); Text(message).appFont(.body) }.frame(maxWidth: .infinity).padding(AppSpacing.standard).accessibilityElement(children: .combine) }
}

struct FilterChip: View {
    let title: String
    var isSelected: Bool
    let action: () -> Void
    var body: some View { Button(action: action) { HStack(spacing: AppSpacing.small) { if isSelected { Image(systemName: "checkmark") }; Text(title) }.appFont(.callout).padding(.horizontal, AppSpacing.standard).padding(.vertical, AppSpacing.small).frame(minHeight: 44) }.background(isSelected ? AppTheme.accent : AppTheme.surface).clipShape(Capsule()).overlay(Capsule().stroke(isSelected ? AppTheme.accent : AppTheme.border, lineWidth: 1)).accessibilityValue(isSelected ? "Selected" : "Not selected") }
}

enum AppButtonStylePublic {
    static var primary: some ButtonStyle { AppButtonStyle(background: AppTheme.accent, outlined: false) }
    static var secondary: some ButtonStyle { AppButtonStyle(background: AppTheme.surface, outlined: true) }
    static var destructive: some ButtonStyle { AppButtonStyle(background: AppTheme.highlight, outlined: false) }
}
