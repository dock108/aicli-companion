import SwiftUI

/// Spacing system based on Figma design specifications
public struct Spacing {
    // MARK: - Base Spacing Values
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 8
    public static let sm: CGFloat = 12
    public static let md: CGFloat = 16
    public static let lg: CGFloat = 24
    public static let xl: CGFloat = 32
    public static let xxl: CGFloat = 48
    public static let xxxl: CGFloat = 60
    
    // MARK: - Component Specific Spacing
    public struct Component {
        public static let buttonPaddingVertical: CGFloat = 16
        public static let buttonPaddingHorizontal: CGFloat = 24
        public static let navBarPadding: CGFloat = 16
        public static let navBarVerticalPadding: CGFloat = 8
        public static let cardPadding: CGFloat = 20
    }
    
    // MARK: - Layout Specific Spacing
    public struct Layout {
        public static let screenPaddingTop: CGFloat = 24
        public static let screenPaddingBottom: CGFloat = 24
        public static let screenPaddingHorizontal: CGFloat = 24
        
        // Connection screen specific spacing
        public static let navBarToHero: CGFloat = 32
        public static let heroToTitle: CGFloat = 24
        public static let titleToButton: CGFloat = 32
        public static let buttonToDivider: CGFloat = 12
        public static let dividerToSecondaryButton: CGFloat = 12
        public static let secondaryButtonToHelp: CGFloat = 24
    }
}

/// Corner radius system
public struct CornerRadius {
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12  // Buttons
    public static let lg: CGFloat = 16  // Cards
    public static let xl: CGFloat = 24  // Bottom sheets
    
    // Component specific
    public static let button: CGFloat = 12
    public static let card: CGFloat = 16
    public static let sheet: CGFloat = 24
    public static let icon: CGFloat = 8
}

/// Shadow definitions
@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
public struct Shadows {
    public static let small = Shadow(
        color: Color.black.opacity(0.04),
        radius: 2,
        xOffset: 0,
        yOffset: 1
    )
    
    public static let medium = Shadow(
        color: Color.black.opacity(0.06),
        radius: 4,
        xOffset: 0,
        yOffset: 2
    )
    
    public static let large = Shadow(
        color: Color.black.opacity(0.08),
        radius: 8,
        xOffset: 0,
        yOffset: 4
    )
    
    public struct Shadow {
        let color: Color
        let radius: CGFloat
        let xOffset: CGFloat
        let yOffset: CGFloat
    }
}

// MARK: - View Extensions
@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
extension View {
    /// Apply standard screen padding
    public func screenPadding() -> some View {
        self.padding(.horizontal, Spacing.Layout.screenPaddingHorizontal)
            .padding(.top, Spacing.Layout.screenPaddingTop)
            .padding(.bottom, Spacing.Layout.screenPaddingBottom)
    }
    
    /// Apply component padding
    public func componentPadding() -> some View {
        self.padding(Spacing.Component.cardPadding)
    }
    
    /// Apply shadow
    public func shadow(_ shadow: Shadows.Shadow) -> some View {
        self.shadow(
            color: shadow.color,
            radius: shadow.radius,
            x: shadow.xOffset,
            y: shadow.yOffset
        )
    }
}
