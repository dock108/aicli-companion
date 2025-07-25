import SwiftUI

/// Design system color palette based on Figma specifications
public struct Colors {
    // MARK: - Brand Colors
    public static let brandBlue400 = Color(hex: "#4A7AE4")
    public static let brandBlue500 = Color(hex: "#3366E0")
    
    // MARK: - Ink Colors (Text)
    public static let ink900 = Color(hex: "#0F1B2B")
    public static let ink700 = Color(hex: "#3E4C63")
    
    // MARK: - Surface Colors
    public static let surface00 = Color.white
    public static let surface10 = Color(red: 16/255, green: 37/255, blue: 69/255, opacity: 0.05)
    
    // MARK: - Semantic Colors
    public static let primaryText = ink900
    public static let secondaryText = ink700
    public static let primaryButton = brandBlue500
    public static let primaryButtonHighlight = brandBlue400
    public static let linkColor = brandBlue500
    
    // MARK: - Dark Mode Support
    public static func adaptiveBackground(colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(white: 0.1) : surface00
    }
    
    public static func adaptivePrimaryText(colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .white : ink900
    }
    
    public static func adaptiveSecondaryText(colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(white: 0.7) : ink700
    }
}

// MARK: - Color Extension for Hex Support
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Gradient Definitions
public struct Gradients {
    public static let primaryButton = LinearGradient(
        colors: [Colors.brandBlue500, Colors.brandBlue400],
        startPoint: .top,
        endPoint: .bottom
    )
    
    public static let heroIcon = RadialGradient(
        colors: [Colors.brandBlue400, Colors.brandBlue500],
        center: .center,
        startRadius: 0,
        endRadius: 60
    )
}