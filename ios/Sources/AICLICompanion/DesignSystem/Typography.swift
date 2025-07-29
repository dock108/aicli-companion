import SwiftUI

/// Dark-Slate Terminal typography system
@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
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
            
        // Body text - SF Pro
        case .body:
            return .system(size: 17)
        case .bodyLarge:
            return .system(size: 19)
        case .bodySmall:
            return .system(size: 15)
        case .caption:
            return .system(size: 12)
        case .footnote:
            return .system(size: 13)
            
        // Code/Terminal - SF Mono
        case .code:
            return .custom("SFMono-Regular", size: 14)
        case .terminal:
            return .custom("SFMono-Medium", size: 16)
        }
    }
    
    // MARK: - Line Heights
    public static func lineHeight(for style: FontStyle) -> CGFloat {
        switch style {
        case .hero: return 34
        case .heading1: return 28
        case .heading2: return 24
        case .heading3: return 22
        case .navTitle: return 22
        case .body, .terminal: return 22
        case .bodyLarge: return 24
        case .bodySmall: return 20
        case .caption: return 16
        case .footnote: return 18
        case .code: return 20
        }
    }
    
    // MARK: - Legacy Support
    public enum TextStyle {
        case title
        case headline
        case body
        case bodyLarge
        case callout
        case caption
        case footnote
    }
    
    @available(*, deprecated, message: "Use font(_:) with FontStyle instead")
    public static func font(_ style: TextStyle, size: CGFloat? = nil, weight: Font.Weight = .regular) -> Font {
        let baseFont: Font
        
        switch style {
        case .title:
            baseFont = .system(size: size ?? 28, weight: weight, design: .rounded)
        case .headline:
            baseFont = .system(size: size ?? 17, weight: .semibold, design: .rounded)
        case .body:
            baseFont = .system(size: size ?? 17, weight: weight, design: .rounded)
        case .bodyLarge:
            baseFont = .system(size: size ?? 19, weight: weight, design: .rounded)
        case .callout:
            baseFont = .system(size: size ?? 16, weight: weight, design: .rounded)
        case .caption:
            baseFont = .system(size: size ?? 12, weight: weight, design: .rounded)
        case .footnote:
            baseFont = .system(size: size ?? 13, weight: weight, design: .rounded)
        }
        
        return baseFont
    }
}

// MARK: - Text Style Modifiers
@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
extension Text {
    /// Applies typography style with proper line height
    public func typographyStyle(_ style: Typography.FontStyle) -> some View {
        self
            .font(Typography.font(style))
            .lineSpacing(Typography.lineHeight(for: style) - Typography.defaultLineHeight(for: style))
    }
}

// MARK: - Helper Methods
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
