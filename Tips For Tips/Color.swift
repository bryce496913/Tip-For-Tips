import SwiftUI

enum AppTheme {
    static let background = Color.black
    static let surface = Color(red: 0.12, green: 0.04, blue: 0.2)
    static let accent = Color(red: 0.72, green: 0.29, blue: 0.95)
    static let highlight = Color(red: 0.98, green: 0.32, blue: 0.67)
    static let text = Color.white
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
    static let small: CGFloat = 6
    static let standard: CGFloat = 10
    static let section: CGFloat = 16
    static let screen: CGFloat = 20
    static let large: CGFloat = 24
    static let corner: CGFloat = 16
}

enum AppTextStyle {
    case h1, h2, h3, paragraph

    var size: CGFloat {
        switch self { case .h1: return 16; case .h2: return 14; case .h3: return 12; case .paragraph: return 10 }
    }

    var weight: Font.Weight {
        switch self { case .h1: return .bold; case .h2: return .semibold; case .h3: return .medium; case .paragraph: return .regular }
    }

    var relativeTo: Font.TextStyle {
        switch self { case .h1: return .title2; case .h2: return .headline; case .h3: return .subheadline; case .paragraph: return .body }
    }
}

private struct AppFontModifier: ViewModifier {
    let style: AppTextStyle
    @ScaledMetric private var scaledSize: CGFloat

    init(style: AppTextStyle) {
        self.style = style
        _scaledSize = ScaledMetric(wrappedValue: style.size, relativeTo: style.relativeTo)
    }

    func body(content: Content) -> some View {
        content.font(.system(size: scaledSize, weight: style.weight))
    }
}

extension View {
    func appFont(_ style: AppTextStyle) -> some View { modifier(AppFontModifier(style: style)) }

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
        VStack(spacing: AppSpacing.small) {
            Text(text).appFont(.h1).multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
            if let subtitle { Text(subtitle).appFont(.paragraph).foregroundStyle(AppTheme.text.opacity(0.8)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true) }
        }
        .foregroundStyle(AppTheme.text)
    }
}

struct ThemedCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.standard) { content }
            .padding(AppSpacing.section)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AppSpacing.corner, style: .continuous).stroke(AppTheme.accent.opacity(0.25), lineWidth: 1))
    }
}

struct PrimaryButton: View {
    let title: String; var systemImage: String?; var isDisabled = false; let action: () -> Void
    var body: some View { Button(action: action) { label }.buttonStyle(AppButtonStyle(background: AppTheme.accent, outlined: false)).disabled(isDisabled).opacity(isDisabled ? 0.45 : 1) }
    @ViewBuilder private var label: some View { if let systemImage { Label(title, systemImage: systemImage).appFont(.h3).frame(maxWidth: .infinity, minHeight: 44) } else { Text(title).appFont(.h3).frame(maxWidth: .infinity, minHeight: 44) } }
}

struct SecondaryButton: View {
    let title: String; var systemImage: String?; var isDisabled = false; let action: () -> Void
    var body: some View { Button(action: action) { label }.buttonStyle(AppButtonStyle(background: AppTheme.surface, outlined: true)).disabled(isDisabled).opacity(isDisabled ? 0.45 : 1) }
    @ViewBuilder private var label: some View { if let systemImage { Label(title, systemImage: systemImage).appFont(.h3).frame(maxWidth: .infinity, minHeight: 44) } else { Text(title).appFont(.h3).frame(maxWidth: .infinity, minHeight: 44) } }
}

struct DestructiveButton: View {
    let title: String; var systemImage: String?; let action: () -> Void
    var body: some View { Button(action: action) { if let systemImage { Label(title, systemImage: systemImage).appFont(.h3).frame(maxWidth: .infinity, minHeight: 44) } else { Text(title).appFont(.h3).frame(maxWidth: .infinity, minHeight: 44) } }.buttonStyle(AppButtonStyle(background: AppTheme.highlight, outlined: false)) }
}

private struct AppButtonStyle: ButtonStyle {
    let background: Color; let outlined: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(AppTheme.text).padding(.horizontal, AppSpacing.section)
            .background(outlined ? background.opacity(configuration.isPressed ? 0.65 : 1) : background.opacity(configuration.isPressed ? 0.72 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppTheme.accent.opacity(outlined ? 0.8 : 0), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct AppTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration.appFont(.paragraph).foregroundStyle(AppTheme.text).padding(12).background(AppTheme.surface)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppTheme.accent, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct EmptyStateView: View {
    let systemImage: String; let title: String; let message: String
    var body: some View { VStack(spacing: AppSpacing.standard) { Image(systemName: systemImage).font(.title2).foregroundStyle(AppTheme.highlight); Text(title).appFont(.h2); Text(message).appFont(.paragraph).foregroundStyle(AppTheme.text.opacity(0.8)).multilineTextAlignment(.center) }.frame(maxWidth: .infinity).padding(AppSpacing.large) }
}
