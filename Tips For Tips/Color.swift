import SwiftUI

// Central visual theme for Tips for Tips.
enum AppTheme {
    static let background = Color.black
    static let surface = Color(red: 0.12, green: 0.04, blue: 0.2)
    static let accent = Color(red: 0.72, green: 0.29, blue: 0.95)
    static let highlight = Color(red: 0.98, green: 0.32, blue: 0.67)
    static let text = Color.white
}

enum AppTextStyle {
    case h1
    case h2
    case h3
    case paragraph

    var size: CGFloat {
        switch self {
        case .h1: return 16
        case .h2: return 14
        case .h3: return 12
        case .paragraph: return 10
        }
    }

    var weight: Font.Weight {
        switch self {
        case .h1: return .bold
        case .h2: return .semibold
        case .h3: return .medium
        case .paragraph: return .regular
        }
    }

    var relativeTo: Font.TextStyle {
        switch self {
        case .h1: return .title2
        case .h2: return .headline
        case .h3: return .subheadline
        case .paragraph: return .body
        }
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
        content.font(.system(size: scaledSize, weight: style.weight, design: .default))
    }
}

extension View {
    func appFont(_ style: AppTextStyle) -> some View {
        modifier(AppFontModifier(style: style))
    }

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
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .foregroundStyle(AppTheme.accent)
            }
        }
    }
}

struct AppScreen<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            content
        }
        .foregroundStyle(AppTheme.text)
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .appNavigationStyle()
    }
}

struct ScreenTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .appFont(.h1)
            .foregroundStyle(AppTheme.text)
            .multilineTextAlignment(.center)
            .accessibilityAddTraits(.isHeader)
    }
}

struct ThemedCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct PrimaryButton: View {
    let title: String
    var systemImage: String?
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            buttonLabel
        }
        .buttonStyle(AppButtonStyle(background: AppTheme.accent))
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
    }
}

extension PrimaryButton {
    @ViewBuilder private var buttonLabel: some View {
        if let systemImage {
            Label(title, systemImage: systemImage)
                .appFont(.h3)
                .frame(maxWidth: .infinity, minHeight: 44)
        } else {
            Text(title)
                .appFont(.h3)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }
}

struct SecondaryButton: View {
    let title: String
    var systemImage: String?
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            buttonLabel
        }
        .buttonStyle(AppButtonStyle(background: AppTheme.highlight))
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
    }
}

extension SecondaryButton {
    @ViewBuilder private var buttonLabel: some View {
        if let systemImage {
            Label(title, systemImage: systemImage)
                .appFont(.h3)
                .frame(maxWidth: .infinity, minHeight: 44)
        } else {
            Text(title)
                .appFont(.h3)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }
}

private struct AppButtonStyle: ButtonStyle {
    let background: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(AppTheme.text)
            .padding(.horizontal, 16)
            .background(background.opacity(configuration.isPressed ? 0.72 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct AppTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .appFont(.paragraph)
            .foregroundStyle(AppTheme.text)
            .padding(12)
            .background(AppTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppTheme.accent, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
