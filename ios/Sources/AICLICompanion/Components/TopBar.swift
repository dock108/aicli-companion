import SwiftUI

/// Dark-Slate Terminal style top navigation bar
@available(iOS 16.0, macOS 13.0, *)
public struct TopBar: View {
    let title: String
    let leadingIcon: String
    let trailingAction: (() -> Void)?
    let trailingIcon: String
    
    @Environment(\.colorScheme) var colorScheme
    
    public init(
        title: String,
        leadingIcon: String = "terminal.fill",
        trailingIcon: String = "gearshape",
        trailingAction: (() -> Void)? = nil
    ) {
        self.title = title
        self.leadingIcon = leadingIcon
        self.trailingIcon = trailingIcon
        self.trailingAction = trailingAction
    }
    
    public var body: some View {
        HStack(spacing: Spacing.sm) {
            // Leading terminal glyph
            Image(systemName: leadingIcon)
                .font(.system(size: 24))
                .foregroundColor(Colors.accentPrimaryEnd)
                .frame(width: 24, height: 24)
            
            // Title in SF Mono
            Text(title)
                .font(Typography.font(.navTitle))
                .foregroundColor(Colors.textPrimary(for: colorScheme))
            
            Spacer()
            
            // Trailing gear icon
            Button(action: {
                HapticManager.shared.lightImpact()
                trailingAction?()
            }) {
                Image(systemName: trailingIcon)
                    .font(.system(size: 20))
                    .foregroundColor(Colors.textSecondary(for: colorScheme))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, Spacing.Component.navBarPadding)
        .padding(.vertical, Spacing.Component.navBarVerticalPadding)
        .frame(height: 44)
        .background(
            // Blur background with systemThin material
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                
                // Add subtle bottom border
                VStack {
                    Spacer()
                    Rectangle()
                        .fill(colorScheme == .dark ? Colors.divider : Colors.dividerLight)
                        .frame(height: 1)
                }
            }
        )
    }
}

// MARK: - TopBar with Navigation Support
@available(iOS 16.0, macOS 13.0, *)
public struct NavigationTopBar<Destination: View>: View {
    let title: String
    let leadingIcon: String
    let destination: Destination
    
    @Environment(\.colorScheme) var colorScheme
    
    public init(
        title: String,
        leadingIcon: String = "terminal.fill",
        @ViewBuilder destination: () -> Destination
    ) {
        self.title = title
        self.leadingIcon = leadingIcon
        self.destination = destination()
    }
    
    public var body: some View {
        TopBar(
            title: title,
            leadingIcon: leadingIcon,
            trailingAction: nil
        )
        .overlay(alignment: .trailing) {
            NavigationLink(destination: destination) {
                Image(systemName: "gearshape")
                    .font(.system(size: 20))
                    .foregroundColor(Colors.textSecondary(for: colorScheme))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.trailing, Spacing.Component.navBarPadding)
        }
    }
}

// MARK: - Preview
@available(iOS 17.0, macOS 14.0, *)
#Preview("TopBar") {
    VStack(spacing: 0) {
        TopBar(
            title: "Code Companion",
            trailingAction: {
                print("Settings tapped")
            }
        )
        
        Spacer()
    }
    .background(Colors.bgBase(for: .dark))
    .preferredColorScheme(.dark)
}

@available(iOS 17.0, macOS 14.0, *)
#Preview("NavigationTopBar") {
    NavigationStack {
        VStack(spacing: 0) {
            NavigationTopBar(title: "Code Companion") {
                Text("Settings View")
            }
            
            Spacer()
        }
        .background(Colors.bgBase(for: .light))
    }
    .preferredColorScheme(.light)
}