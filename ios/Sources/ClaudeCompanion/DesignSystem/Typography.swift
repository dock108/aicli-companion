import SwiftUI

/// Typography system based on SF Pro Rounded with Figma specifications
public struct Typography {
    
    // MARK: - Font Styles
    public enum TextStyle {
        case h1
        case body
        case bodySecondary
        case small
        case button
        case navTitle
        case link
        
        var size: CGFloat {
            switch self {
            case .h1: return 28
            case .body, .button: return 17
            case .bodySecondary: return 17
            case .small: return 13
            case .navTitle: return 17
            case .link: return 15
            }
        }
        
        var weight: Font.Weight {
            switch self {
            case .h1, .button, .navTitle, .link: return .semibold
            case .body, .bodySecondary, .small: return .regular
            }
        }
        
        var design: Font.Design {
            return .rounded
        }
        
        var lineSpacing: CGFloat {
            switch self {
            case .h1: return 4
            case .body, .bodySecondary: return 2
            case .small: return 1
            default: return 0
            }
        }
    }
    
    // MARK: - Font Creation
    public static func font(_ style: TextStyle) -> Font {
        if #available(iOS 16.0, *) {
            return .system(size: style.size, weight: style.weight, design: style.design)
        } else {
            // Fallback for older iOS versions
            return .system(size: style.size, weight: style.weight)
        }
    }
    
    // MARK: - Text Modifiers
    public static func styled(_ text: Text, as style: TextStyle, color: Color? = nil) -> some View {
        text
            .font(font(style))
            .foregroundColor(color)
            .lineSpacing(style.lineSpacing)
    }
}

// MARK: - View Extension for Typography
extension View {
    public func textStyle(_ style: Typography.TextStyle, color: Color? = nil) -> some View {
        self
            .font(Typography.font(style))
            .foregroundColor(color)
            .lineSpacing(style.lineSpacing)
    }
}

// MARK: - Text Alignment Helpers
extension Text {
    public func h1() -> some View {
        self
            .font(Typography.font(.h1))
            .foregroundColor(Colors.primaryText)
            .multilineTextAlignment(.center)
    }
    
    public func bodyText() -> some View {
        self
            .font(Typography.font(.body))
            .foregroundColor(Colors.primaryText)
            .multilineTextAlignment(.center)
    }
    
    public func secondaryText() -> some View {
        self
            .font(Typography.font(.bodySecondary))
            .foregroundColor(Colors.secondaryText)
            .multilineTextAlignment(.center)
    }
    
    public func smallText() -> some View {
        self
            .font(Typography.font(.small))
            .foregroundColor(Colors.secondaryText)
    }
    
    public func buttonText() -> some View {
        self
            .font(Typography.font(.button))
            .foregroundColor(.white)
    }
    
    public func linkText() -> some View {
        self
            .font(Typography.font(.link))
            .foregroundColor(Colors.linkColor)
            .underline()
    }
}