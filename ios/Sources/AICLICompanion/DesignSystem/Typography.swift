import SwiftUI

/// Dark-Slate Terminal typography system
@available(iOS 16.0, macOS 13.0, *)
public struct Typography {
    // MARK: - Font Styles
    public enum FontStyle {
        // Navigation
        case navTitle

        // Hero/Headings (SF Mono)
        case hero
        case heading1
        case heading2
        case heading3

        // Body text (SF Pro)
        case body
        case bodyLarge
        case bodySmall
        case caption
        case footnote

        // Code/Terminal
        case code
        case terminal
    }

    // MARK: - Font Factory
    public static func font(_ style: FontStyle) -> Font {
        switch style {
        // Navigation - SF Mono Semibold
        case .navTitle:
            return .custom("SFMono-Semibold", size: 17)

        // Headings - SF Mono for terminal vibe
        case .hero:
            return .custom("SFMono-Bold", size: 28)
        case .heading1:
            return .custom("SFMono-Semibold", size: 24)
        case .heading2:
            return .custom("SFMono-Semibold", size: 20)
        case .heading3:
            return .custom("SFMono-Medium", size: 17)

        // Body text - SF Pro (slightly smaller for mobile readability)
        case .body:
            return .system(size: 16)
        case .bodyLarge:
            return .system(size: 18)
        case .bodySmall:
            return .system(size: 14)
        case .caption:
            return .system(size: 12)
        case .footnote:
            return .system(size: 13)

        // Code/Terminal - SF Mono
        case .code:
            return .custom("SFMono-Regular", size: 14)
        case .terminal:
            return .custom("SFMono-Medium", size: 15)
        }
    }

    // MARK: - Line Heights
    public static func lineHeight(for style: FontStyle) -> CGFloat {
        switch style {
        case .hero: return 36
        case .heading1: return 32
        case .heading2: return 28
        case .heading3: return 24
        case .navTitle: return 22
        case .body: return 24
        case .terminal: return 22
        case .bodyLarge: return 28
        case .bodySmall: return 22
        case .caption: return 18
        case .footnote: return 20
        case .code: return 22
        }
    }
}

// MARK: - Text Style Modifiers
@available(iOS 16.0, macOS 13.0, *)
extension Text {
    /// Applies typography style with proper line height
    public func typographyStyle(_ style: Typography.FontStyle) -> some View {
        self
            .font(Typography.font(style))
            .lineSpacing(Typography.lineHeight(for: style) - Typography.defaultLineHeight(for: style))
    }
}

// MARK: - Helper Methods
@available(iOS 13.0, macOS 10.15, *)
extension Typography {
    /// Calculate default line height for a font style
    static func defaultLineHeight(for style: FontStyle) -> CGFloat {
        switch style {
        case .hero: return 34
        case .heading1: return 29
        case .heading2: return 24
        case .heading3: return 20
        case .navTitle: return 20
        case .body, .terminal: return 20
        case .bodyLarge: return 22
        case .bodySmall: return 18
        case .caption: return 14
        case .footnote: return 15
        case .code: return 16
        }
    }
}
