import SwiftUI

/// Settings tile component with neumorphic design
@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
public struct SettingsTile<Content: View>: View {
    let title: String
    let value: String?
    let content: Content
    
    @Environment(\.colorScheme) var colorScheme
    
    public init(
        title: String,
        value: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.value = value
        self.content = content()
    }
    
    public var body: some View {
        HStack(spacing: Spacing.md) {
            Text(title)
                .font(Typography.font(.body))
                .foregroundColor(Colors.textPrimary(for: colorScheme))
            
            Spacer()
            
            if let value = value {
                Text(value)
                    .font(Typography.font(.bodySmall))
                    .foregroundColor(Colors.textSecondary(for: colorScheme))
            }
            
            content
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
        .frame(height: 56)
    }
}

/// Settings section with card styling
@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
public struct SettingsSection<Content: View>: View {
    let title: String?
    let content: Content
    
    @Environment(\.colorScheme) var colorScheme
    
    public init(
        title: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = content()
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title = title {
                Text(title.uppercased())
                    .font(Typography.font(.caption))
                    .foregroundColor(Colors.textSecondary(for: colorScheme))
                    .padding(.horizontal, Spacing.md)
                    .padding(.bottom, Spacing.xs)
            }
            
            VStack(spacing: 0) {
                content
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Colors.bgCard(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Colors.strokeLight, lineWidth: 1)
            )
        }
        .padding(.horizontal, Spacing.md)
    }
}

/// Divider for settings rows
@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
public struct SettingsDivider: View {
    @Environment(\.colorScheme) var colorScheme
    
    public var body: some View {
        Rectangle()
            .fill(Colors.divider)
            .frame(height: 1)
            .padding(.horizontal, Spacing.md)
    }
}

/// Neumorphic toggle style
@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
public struct NeumorphicToggleStyle: ToggleStyle {
    @Environment(\.colorScheme) var colorScheme
    
    public func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            
            Spacer()
            
            ZStack {
                // Outer shadow
                RoundedRectangle(cornerRadius: 16)
                    .fill(Colors.bgCard(for: colorScheme))
                    .frame(width: 52, height: 32)
                    .shadow(
                        color: Colors.shadowNeumorphicOuter,
                        radius: 3,
                        x: 0,
                        y: 2
                    )
                
                // Inner shadow effect
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Colors.strokeLight, lineWidth: 1)
                    .frame(width: 52, height: 32)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Colors.shadowNeumorphicInner,
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 52, height: 32)
                            .opacity(configuration.isOn ? 0 : 0.3)
                    )
                
                // Thumb
                Circle()
                    .fill(
                        configuration.isOn
                            ? LinearGradient(
                                colors: Colors.accentPrimary(for: colorScheme),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [Colors.textSecondary(for: colorScheme)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                    )
                    .frame(width: 26, height: 26)
                    .offset(x: configuration.isOn ? 11 : -11)
                    .shadow(
                        color: Colors.shadowDark.opacity(0.3),
                        radius: 2,
                        x: 0,
                        y: 1
                    )
            }
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    configuration.isOn.toggle()
                    HapticManager.shared.lightImpact()
                }
            }
        }
    }
}

/// Picker row style
@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
public struct SettingsPickerRow<T: Hashable>: View {
    let title: String
    @Binding var selection: T
    let options: [(T, String)]
    
    @Environment(\.colorScheme) var colorScheme
    
    public init(
        title: String,
        selection: Binding<T>,
        options: [(T, String)]
    ) {
        self.title = title
        self._selection = selection
        self.options = options
    }
    
    public var body: some View {
        Menu {
            ForEach(options, id: \.0) { value, label in
                Button(action: {
                    selection = value
                    HapticManager.shared.selectionChanged()
                }) {
                    HStack {
                        Text(label)
                        if selection == value {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            SettingsTile(
                title: title,
                value: options.first(where: { $0.0 == selection })?.1
            ) {
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundColor(Colors.textSecondary(for: colorScheme))
            }
        }
    }
}

// MARK: - Preview

@available(iOS 17.0, iPadOS 17.0, macOS 14.0, *)
#Preview("Settings Tiles") {
    VStack(spacing: Spacing.lg) {
        // Connection section
        SettingsSection(title: "Connection") {
            SettingsTile(title: "Server", value: "192.168.1.100:3001") {
                EmptyView()
            }
            
            SettingsDivider()
            
            SettingsTile(title: "Status") {
                HStack(spacing: Spacing.xs) {
                    Circle()
                        .fill(Colors.accentWarning)
                        .frame(width: 8, height: 8)
                    Text("Connected")
                        .font(Typography.font(.caption))
                        .foregroundColor(Colors.accentWarning)
                }
            }
        }
        
        // Appearance section
        SettingsSection(title: "Appearance") {
            SettingsPickerRow(
                title: "Theme",
                selection: .constant(Theme.dark),
                options: [
                    (Theme.system, "System"),
                    (Theme.light, "Light"),
                    (Theme.dark, "Dark")
                ]
            )
            
            SettingsDivider()
            
            SettingsPickerRow(
                title: "Font Size",
                selection: .constant(FontSize.medium),
                options: [
                    (FontSize.small, "Small"),
                    (FontSize.medium, "Medium"),
                    (FontSize.large, "Large")
                ]
            )
        }
        
        // Behavior section with toggles
        SettingsSection(title: "Behavior") {
            Toggle(isOn: .constant(true)) {
                Text("Auto-scroll")
                    .font(Typography.font(.body))
                    .foregroundColor(Colors.textPrimary(for: .dark))
            }
            .toggleStyle(NeumorphicToggleStyle())
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            
            SettingsDivider()
            
            Toggle(isOn: .constant(false)) {
                Text("Haptic feedback")
                    .font(Typography.font(.body))
                    .foregroundColor(Colors.textPrimary(for: .dark))
            }
            .toggleStyle(NeumorphicToggleStyle())
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
    }
    .padding(.vertical)
    .background(Colors.bgBase(for: .dark))
    .preferredColorScheme(.dark)
}