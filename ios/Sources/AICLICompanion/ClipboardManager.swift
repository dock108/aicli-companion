import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Centralized clipboard management with visual feedback
@available(iOS 17.0, iPadOS 17.0, macOS 14.0, *)
class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()
    
    @Published var showCopyConfirmation = false
    @Published var copiedText = ""
    
    private init() {}
    
    /// Copy text to clipboard with optional haptic feedback
    func copyToClipboard(_ text: String, withFeedback: Bool = true) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #endif
        
        // Update confirmation state
        copiedText = text
        showCopyConfirmation = true
        
        // Haptic feedback on iOS
        if withFeedback {
            HapticManager.shared.mediumImpact()
        }
        
        // Auto-hide confirmation after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.showCopyConfirmation = false
        }
    }
    
    /// Get text from clipboard
    func getFromClipboard() -> String? {
        #if os(iOS)
        return UIPasteboard.general.string
        #elseif os(macOS)
        return NSPasteboard.general.string(forType: .string)
        #endif
    }
    
    /// Check if clipboard has text
    var hasText: Bool {
        #if os(iOS)
        return UIPasteboard.general.hasStrings
        #elseif os(macOS)
        return NSPasteboard.general.string(forType: .string) != nil
        #endif
    }
}

/// View modifier for showing copy confirmation
@available(iOS 17.0, iPadOS 17.0, macOS 14.0, *)
struct CopyConfirmationModifier: ViewModifier {
    @ObservedObject var clipboardManager = ClipboardManager.shared
    @Environment(\.colorScheme) var colorScheme
    
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if clipboardManager.showCopyConfirmation {
                    CopyConfirmationView()
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        ))
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: clipboardManager.showCopyConfirmation)
                }
            }
    }
}

/// Copy confirmation view
@available(iOS 17.0, iPadOS 17.0, macOS 14.0, *)
struct CopyConfirmationView: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 16))
            
            Text("Copied to clipboard")
                .font(Typography.font(.caption))
                .foregroundColor(Colors.textPrimary(for: colorScheme))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Colors.bgCard(for: colorScheme))
                .overlay(
                    Capsule()
                        .stroke(Colors.strokeLight, lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        .padding(.top, 50) // Below navigation bar
    }
}

// MARK: - View Extension

@available(iOS 17.0, iPadOS 17.0, macOS 14.0, *)
extension View {
    func copyConfirmationOverlay() -> some View {
        self.modifier(CopyConfirmationModifier())
    }
}