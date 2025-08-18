import SwiftUI
import Foundation

// MARK: - Message Code Block View Component

@available(iOS 17.0, macOS 14.0, *)
struct MessageCodeBlockView: View {
    let code: String
    let language: String?
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var clipboardManager = ClipboardManager.shared
    @State private var showCopyButton = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Language label with copy button
            HStack {
                if let lang = language {
                    Text(lang.uppercased())
                        .font(Typography.font(.caption))
                        .foregroundColor(Colors.textSecondary(for: colorScheme))
                }
                
                Spacer()
                
                Button(action: {
                    clipboardManager.copyToClipboard(code)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.caption2)
                        Text("Copy")
                            .font(Typography.font(.caption))
                    }
                    .foregroundColor(Colors.textSecondary(for: colorScheme))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Colors.bgCard(for: colorScheme).opacity(0.8))
                    )
                }
                .opacity(showCopyButton ? 1 : 0.6)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Colors.bgBase(for: colorScheme).opacity(0.5))
            
            // Code content with syntax highlighting (simplified)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(Colors.accentWarning) // Terminal green
                    .padding(12)
                    .textSelection(.enabled)
            }
            .background(Colors.bgBase(for: colorScheme))
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Colors.strokeLight, lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                showCopyButton = hovering
            }
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                showCopyButton.toggle()
            }
        }
        .onAppear {
            // Always show on touch devices
            #if os(iOS)
            showCopyButton = true
            #endif
        }
    }
}

// MARK: - Extended Typography for Code Blocks
// ExtendedFontStyle removed - using main Typography from DesignSystem/Typography.swift
// Colors extension removed - using main Colors from DesignSystem/Colors.swift