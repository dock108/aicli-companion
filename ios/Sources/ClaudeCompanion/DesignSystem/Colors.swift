import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Dark-Slate Terminal design system color palette
@available(iOS 14.0, macOS 11.0, *)
public struct Colors {
    // MARK: - Background Colors
    /// App canvas background
    public static let bgBase = Color("bg/base", bundle: .main)
    public static let bgBaseFallback = Color(light: Color(hex: "#F4F6F8"), dark: Color(hex: "#0E1116"))
    
    /// Card and bubble backgrounds
    public static let bgCard = Color("bg/card", bundle: .main)
    public static let bgCardFallback = Color(light: Color(hex: "#FFFFFF"), dark: Color(hex: "#1A1D22"))
    
    // MARK: - Accent Colors
    /// Primary accent gradient colors
    public static let accentPrimaryStart = Color(hex: "#3F7AF5")
    public static let accentPrimaryEnd = Color(hex: "#3364E1")
    
    /// Warning/Success accent (connected status)
    public static let accentWarning = Color(hex: "#10B981")
    
    // MARK: - Text Colors
    /// Primary text color
    public static let textPrimary = Color("text/primary", bundle: .main)
    public static let textPrimaryFallback = Color(light: Color(hex: "#0E1116"), dark: Color(hex: "#E9EAEC"))
    
    /// Secondary text color (timestamps, subtitles)
    public static let textSecondary = Color("text/secondary", bundle: .main)
    public static let textSecondaryFallback = Color(light: Color(hex: "#4A5568"), dark: Color(hex: "#99A3B4"))
    
    // MARK: - Additional Colors
    /// Stroke and border colors
    public static let strokeLight = Color(white: 1, opacity: 0.06)
    public static let strokeDark = Color(white: 0, opacity: 0.08)
    
    /// Shadow colors
    public static let shadowDark = Color(red: 0, green: 0, blue: 0, opacity: 0.25)
    public static let shadowNeumorphicOuter = Color(red: 0, green: 0, blue: 0, opacity: 0.6)
    public static let shadowNeumorphicInner = Color(white: 1, opacity: 0.1)
    
    /// Divider colors
    public static let divider = Color(white: 1, opacity: 0.08)
    public static let dividerLight = Color(white: 0, opacity: 0.1)
    
    // MARK: - Semantic Colors (for backwards compatibility)
    public static let brandBlue400 = accentPrimaryStart
    public static let brandBlue500 = accentPrimaryEnd
    public static let ink900 = Color(hex: "#0E1116")
    public static let ink700 = Color(hex: "#4A5568")
    public static let surface00 = Color.white
    public static let surface10 = Color(white: 0, opacity: 0.05)
    
    // MARK: - Helper Methods
    public static func bgBase(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "#0E1116") : Color(hex: "#F4F6F8")
    }
    
    public static func bgCard(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "#1A1D22") : Color(hex: "#FFFFFF")
    }
    
    public static func textPrimary(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "#E9EAEC") : Color(hex: "#0E1116")
    }
    
    public static func textSecondary(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "#99A3B4") : Color(hex: "#4A5568")
    }
    
    public static func accentPrimary(for colorScheme: ColorScheme) -> [Color] {
        let baseColors = [accentPrimaryStart, accentPrimaryEnd]
        if colorScheme == .dark {
            // +10% brightness in dark mode
            return baseColors.map { color in
                var hue: CGFloat = 0
                var saturation: CGFloat = 0
                var brightness: CGFloat = 0
                var opacity: CGFloat = 0
                
                #if os(iOS)
                UIColor(color).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &opacity)
                #elseif os(macOS)
                NSColor(color).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &opacity)
                #endif
                return Color(hue: Double(hue), saturation: Double(saturation), brightness: min(1.0, Double(brightness * 1.1)), opacity: Double(opacity))
            }
        }
        return baseColors
    }
    
    // MARK: - Adaptive Colors (deprecated - use specific methods above)
    @available(*, deprecated, message: "Use bgBase(for:) instead")
    public static func adaptiveBackground(colorScheme: ColorScheme) -> Color {
        bgBase(for: colorScheme)
    }
    
    @available(*, deprecated, message: "Use textPrimary(for:) instead")
    public static func adaptivePrimaryText(colorScheme: ColorScheme) -> Color {
        textPrimary(for: colorScheme)
    }
    
    @available(*, deprecated, message: "Use textSecondary(for:) instead")
    public static func adaptiveSecondaryText(colorScheme: ColorScheme) -> Color {
        textSecondary(for: colorScheme)
    }
}

// MARK: - Color Extension for Hex Support
@available(iOS 14.0, macOS 11.0, *)
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
    
    /// Creates a color that automatically adapts to light/dark mode
    init(light: Color, dark: Color) {
        #if os(iOS)
        self.init(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #elseif os(macOS)
        self.init(NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(dark) : NSColor(light)
        } ?? NSColor(light))
        #endif
    }
}

// MARK: - Gradient Definitions
@available(iOS 14.0, macOS 11.0, *)
public struct Gradients {
    /// Primary button gradient
    public static func primaryButton(for colorScheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: Colors.accentPrimary(for: colorScheme),
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    /// Hero icon radial gradient
    public static func heroIcon(for colorScheme: ColorScheme) -> RadialGradient {
        RadialGradient(
            colors: Colors.accentPrimary(for: colorScheme),
            center: .center,
            startRadius: 0,
            endRadius: 68 // Half of 136pt circle
        )
    }
    
    // MARK: - Legacy gradients for compatibility
    public static let primaryButton = LinearGradient(
        colors: [Colors.accentPrimaryStart, Colors.accentPrimaryEnd],
        startPoint: .top,
        endPoint: .bottom
    )
    
    public static let heroIcon = RadialGradient(
        colors: [Colors.accentPrimaryStart, Colors.accentPrimaryEnd],
        center: .center,
        startRadius: 0,
        endRadius: 60
    )
}