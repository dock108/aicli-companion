import SwiftUI
import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Command Output View Component

@available(iOS 16.0, macOS 13.0, *)
struct CommandOutputView: View {
    let commandData: CommandOutputData
    @Binding var isExpanded: Bool
    @State private var showActions = false
    @State private var showCopyConfirmation = false
    
    private let previewLines = 15
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack {
                Image(systemName: "terminal")
                    .foregroundColor(.green)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Command Output")
                        .font(.headline)
                        .fontWeight(.medium)
                    
                    HStack {
                        Text(commandData.command)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(Color.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        
                        if commandData.exitCode == 0 {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        } else {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                        
                        Text("Exit: \(commandData.exitCode)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if let workingDir = commandData.workingDirectory {
                            Text("• \(workingDir)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                
                Spacer()
                
                // Actions
                HStack(spacing: 8) {
                    if showCopyConfirmation {
                        Text("Copied!")
                            .font(.caption)
                            .foregroundColor(.green)
                            .transition(.opacity)
                    }
                    
                    Button {
                        copyToClipboard(commandData.output)
                        withAnimation {
                            showCopyConfirmation = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation {
                                showCopyConfirmation = false
                            }
                        }
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .opacity(showActions ? 1 : 0)
                    
                    if needsExpandToggle {
                        Button {
                            withAnimation(.easeInOut) {
                                isExpanded.toggle()
                            }
                        } label: {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            
            Divider()
                .padding(.horizontal, 12)
            
            // Output content
            ScrollView(.horizontal, showsIndicators: false) {
                Text(displayOutput)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            if needsExpandToggle && !isExpanded {
                HStack {
                    Spacer()
                    Button("Show More") {
                        withAnimation(.easeInOut) {
                            isExpanded = true
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                    Spacer()
                }
                .padding(.bottom, 8)
            }
        }
        .background(commandData.exitCode == 0 ?
                   Color.green.opacity(0.05) :
                   Color.red.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(commandData.exitCode == 0 ?
                       Color.green.opacity(0.3) :
                       Color.red.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                showActions = hovering
            }
        }
    }
    
    private var displayOutput: String {
        if needsExpandToggle && !isExpanded {
            let lines = commandData.output.components(separatedBy: .newlines)
            if lines.count > previewLines {
                return lines.prefix(previewLines).joined(separator: "\n")
            }
        }
        return commandData.output
    }
    
    private var needsExpandToggle: Bool {
        let lineCount = commandData.output.components(separatedBy: .newlines).count
        return lineCount > previewLines
    }
    
    private func copyToClipboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
