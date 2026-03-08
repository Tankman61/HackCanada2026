import SwiftUI
import CoreText

// MARK: - Theme Bootstrap

/// Call once when either Copped clip launches to configure ClankerComponents theme.
enum CoppedTheme {
    private static var isConfigured = false

    static func bootstrap() {
        guard !isConfigured else { return }
        isConfigured = true
        registerManropeFonts()
        Theme.configureApp()
    }

    /// Programmatically register Manrope .ttf files from the app bundle
    /// so they work without Info.plist entries (hackathon convenience).
    private static func registerManropeFonts() {
        let fontNames = [
            "Manrope-ExtraLight", "Manrope-Light", "Manrope-Regular",
            "Manrope-Medium", "Manrope-SemiBold", "Manrope-Bold", "Manrope-ExtraBold"
        ]
        for name in fontNames {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }
}

// MARK: - CoppedPalette (brand accent colors, kept thin)

enum CoppedPalette {
    // Primary surfaces
    static let ink = Color(red: 0.07, green: 0.07, blue: 0.07)

    // Accent kept from ClankerComponents theme — violet #7C3AED
    static var accent: Color { UniversalColor.accent.color }
    static var accentBg: Color { UniversalColor.accentBackground.color }

    // Semantic
    static var success: Color { UniversalColor.success.color }
    static var danger: Color { UniversalColor.danger.color }
    static var warning: Color { UniversalColor.warning.color }

    // Neutrals
    static var fg: Color { UniversalColor.foreground.color }
    static var fgSecondary: Color { UniversalColor.secondaryForeground.color }
    static var bg: Color { UniversalColor.background.color }
    static var divider: Color { UniversalColor.divider.color }
    static var content1: Color { UniversalColor.content1.color }
    static var content2: Color { UniversalColor.content2.color }
}

// MARK: - Copped Glass Card (bridges to ClankerComponents glass)

struct CoppedGlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .liquidGlass(cornerRadius: cornerRadius)
    }
}

extension View {
    func coppedGlass(cornerRadius: CGFloat = 20) -> some View {
        modifier(CoppedGlassCardModifier(cornerRadius: cornerRadius))
    }

    /// Legacy name kept for files that still reference it.
    func coppedGlassCard(cornerRadius: CGFloat = 22) -> some View {
        coppedGlass(cornerRadius: cornerRadius)
    }
}

// MARK: - Background

struct CoppedStageBackground: View {
    var body: some View {
        CoppedPalette.ink
            .ignoresSafeArea()
    }
}

// MARK: - Small Utilities

struct CoppedInfoChip: View {
    let title: String
    let icon: String
    var tint: Color = .white

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.custom(Manrope.semiBold, size: 9))
            Text(title)
                .font(.custom(Manrope.bold, size: 10))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .liquidGlass(cornerRadius: 20, useCapsule: true)
    }
}

struct CoppedStepPill: View {
    let label: String
    let isActive: Bool

    var body: some View {
        Text(label)
            .font(.custom(Manrope.bold, size: 10))
            .foregroundStyle(isActive ? .white : .white.opacity(0.5))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .liquidGlass(cornerRadius: 20, useCapsule: true)
            .animation(.easeInOut(duration: 0.25), value: isActive)
    }
}

// MARK: - Bridge Button Styles (ClankerComponents look via SwiftUI ButtonStyle)

struct CoppedPrimaryButtonStyle: SwiftUI.ButtonStyle {
    var disabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.custom(Manrope.bold, size: 15))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(disabled ? CoppedPalette.accent.opacity(0.4) : CoppedPalette.accent)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct CoppedSecondaryButtonStyle: SwiftUI.ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.custom(Manrope.semiBold, size: 14))
            .foregroundStyle(.white.opacity(0.85))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Convenience Button Builders

enum CoppedButtons {
    static func primary(
        title: String,
        icon: String? = nil,
        isLoading: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> SUButton {
        SUButton(model: ButtonVM {
            $0.title = title
            $0.style = .filled
            $0.color = .accent
            $0.size = .large
            $0.isFullWidth = true
            $0.isLoading = isLoading
            $0.isEnabled = isEnabled
            if let icon {
                $0.image = UniversalImage(systemName: icon)
            }
        }, action: action)
    }

    static func secondary(
        title: String,
        icon: String? = nil,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> SUButton {
        SUButton(model: ButtonVM {
            $0.title = title
            $0.style = .light
            $0.color = .primary
            $0.size = .medium
            $0.isFullWidth = true
            $0.isEnabled = isEnabled
            if let icon {
                $0.image = UniversalImage(systemName: icon)
            }
        }, action: action)
    }

    static func ghost(
        title: String,
        icon: String? = nil,
        action: @escaping () -> Void
    ) -> SUButton {
        SUButton(model: ButtonVM {
            $0.title = title
            $0.style = .plain
            $0.color = .primary
            $0.size = .small
            if let icon {
                $0.image = UniversalImage(systemName: icon)
            }
        }, action: action)
    }
}
