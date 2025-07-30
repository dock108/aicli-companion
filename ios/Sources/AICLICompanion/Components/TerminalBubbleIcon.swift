import SwiftUI

/// Terminal bubble icon combining terminal and chat elements
@available(iOS 16.0, macOS 13.0, *)
public struct TerminalBubbleIcon: View {
    let size: CGFloat
    let isGradient: Bool
    
    @Environment(\.colorScheme) var colorScheme
    
    public init(size: CGFloat = 64, isGradient: Bool = true) {
        self.size = size
        self.isGradient = isGradient
    }
    
    public var body: some View {
        ZStack {
            if isGradient {
                gradientVersion
            } else {
                solidVersion
            }
        }
        .frame(width: size, height: size)
    }
    
    private var gradientVersion: some View {
        ZStack {
            // Background bubble with gradient
            Image(systemName: "bubble.left.fill")
                .font(.system(size: size))
                .foregroundColor(Colors.accentPrimaryEnd)
            
            // Terminal overlay
            Image(systemName: "terminal")
                .font(.system(size: size * 0.5, weight: .medium))
                .foregroundColor(.white)
                .offset(x: -size * 0.05, y: -size * 0.05)
        }
    }
    
    private var solidVersion: some View {
        ZStack {
            // Background bubble
            Image(systemName: "bubble.left.fill")
                .font(.system(size: size))
                .foregroundColor(Colors.accentPrimaryEnd)
            
            // Terminal overlay
            Image(systemName: "terminal")
                .font(.system(size: size * 0.5, weight: .medium))
                .foregroundColor(.white)
                .offset(x: -size * 0.05, y: -size * 0.05)
        }
    }
}

/// Alternative design using message circle
@available(iOS 16.0, macOS 13.0, *)
public struct TerminalChatIcon: View {
    let size: CGFloat
    let style: IconStyle
    
    @Environment(\.colorScheme) var colorScheme
    
    public enum IconStyle {
        case filled
        case outlined
        case gradient
    }
    
    public init(size: CGFloat = 64, style: IconStyle = .gradient) {
        self.size = size
        self.style = style
    }
    
    public var body: some View {
        ZStack {
            switch style {
            case .filled:
                filledVersion
            case .outlined:
                outlinedVersion
            case .gradient:
                gradientVersion
            }
        }
        .frame(width: size, height: size)
    }
    
    private var filledVersion: some View {
        ZStack {
            Circle()
                .fill(Colors.accentPrimaryEnd)
            
            Image(systemName: "terminal")
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundColor(.white)
        }
    }
    
    private var outlinedVersion: some View {
        ZStack {
            Circle()
                .stroke(
                    LinearGradient(
                        colors: Colors.accentPrimary(for: colorScheme),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3
                )
            
            Image(systemName: "terminal")
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundColor(Colors.accentPrimaryEnd)
        }
    }
    
    private var gradientVersion: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: Colors.accentPrimary(for: colorScheme),
                        center: .center,
                        startRadius: 0,
                        endRadius: size / 2
                    )
                )
                .shadow(
                    color: Colors.shadowDark,
                    radius: 10,
                    x: 0,
                    y: 5
                )
            
            Image(systemName: "terminal.fill")
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundColor(.white)
        }
    }
}

/// Code bracket chat icon for AI messaging
@available(iOS 16.0, macOS 13.0, *)
public struct CodeChatIcon: View {
    let size: CGFloat
    
    @Environment(\.colorScheme) var colorScheme
    
    public init(size: CGFloat = 64) {
        self.size = size
    }
    
    public var body: some View {
        ZStack {
            // Chat bubble background
            RoundedRectangle(cornerRadius: size * 0.3)
                .fill(Colors.bgCard(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.3)
                        .stroke(Colors.strokeLight, lineWidth: 1)
                )
                .frame(width: size, height: size * 0.8)
            
            // Code brackets
            HStack(spacing: size * 0.15) {
                Text("<")
                    .font(.system(size: size * 0.4, weight: .bold, design: .monospaced))
                
                Text("/>")
                    .font(.system(size: size * 0.4, weight: .bold, design: .monospaced))
            }
            .foregroundColor(Colors.accentPrimaryEnd)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Preview

@available(iOS 17.0, macOS 14.0, *)
#Preview("Terminal Icons") {
    VStack(spacing: 40) {
        VStack(spacing: 20) {
            Text("Terminal Bubble Icons")
                .font(.headline)
            
            HStack(spacing: 30) {
                VStack {
                    TerminalBubbleIcon(size: 64)
                    Text("Gradient")
                        .font(.caption)
                }
                
                VStack {
                    TerminalBubbleIcon(size: 64, isGradient: false)
                    Text("Solid")
                        .font(.caption)
                }
            }
        }
        
        Divider()
        
        VStack(spacing: 20) {
            Text("Terminal Chat Icons")
                .font(.headline)
            
            HStack(spacing: 30) {
                VStack {
                    TerminalChatIcon(size: 64, style: .gradient)
                    Text("Gradient")
                        .font(.caption)
                }
                
                VStack {
                    TerminalChatIcon(size: 64, style: .outlined)
                    Text("Outlined")
                        .font(.caption)
                }
                
                VStack {
                    TerminalChatIcon(size: 64, style: .filled)
                    Text("Filled")
                        .font(.caption)
                }
            }
        }
        
        Divider()
        
        VStack(spacing: 20) {
            Text("Code Chat Icon")
                .font(.headline)
            
            CodeChatIcon(size: 64)
        }
        
        Divider()
        
        VStack(spacing: 20) {
            Text("Different Sizes")
                .font(.headline)
            
            HStack(spacing: 20) {
                TerminalChatIcon(size: 32, style: .gradient)
                TerminalChatIcon(size: 48, style: .gradient)
                TerminalChatIcon(size: 64, style: .gradient)
                TerminalChatIcon(size: 96, style: .gradient)
            }
        }
    }
    .padding()
    .background(Colors.bgBase(for: .dark))
    .preferredColorScheme(.dark)
}