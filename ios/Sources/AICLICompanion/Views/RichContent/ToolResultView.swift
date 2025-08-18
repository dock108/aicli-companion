import SwiftUI
import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Tool Result View Component

@available(iOS 16.0, macOS 13.0, *)
struct ToolResultView: View {
    let toolData: ToolResultData
    @Binding var isExpanded: Bool
    @State private var showActions = false
    @State private var showCopyConfirmation = false
    
    private let previewLines = 12
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack {
                Image(systemName: toolData.success ? "wrench.and.screwdriver.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(toolData.success ? .blue : .orange)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tool Result")
                        .font(.headline)
                        .fontWeight(.medium)
                    
                    HStack {
                        Text(toolData.toolName)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        
                        if toolData.success {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                            Text("Success")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                                .font(.caption)
                            Text("Failed")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        
                        if let metadata = toolData.metadata, !metadata.isEmpty {
                            Text("• \(metadata.count) metadata")
                                .font(.caption)
                                .foregroundColor(.secondary)
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
                        copyToClipboard(toolData.result)
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
            
            // Result content
            ScrollView(.horizontal, showsIndicators: false) {
                Text(displayResult)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Metadata section (if exists and expanded)
            if let metadata = toolData.metadata, !metadata.isEmpty, isExpanded {
                Divider()
                    .padding(.horizontal, 12)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Metadata")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                    
                    ForEach(Array(metadata.keys.sorted()), id: \.self) { key in
                        HStack {
                            Text("\(key):")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            
                            Text("\(metadata[key]?.value ?? "N/A")")
                                .font(.caption)
                                .foregroundColor(.primary)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                    }
                }
                .padding(.bottom, 8)
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
        .background(toolData.success ?
                   Color.blue.opacity(0.05) :
                   Color.orange.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(toolData.success ?
                       Color.blue.opacity(0.3) :
                       Color.orange.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                showActions = hovering
            }
        }
    }
    
    private var displayResult: String {
        if needsExpandToggle && !isExpanded {
            let lines = toolData.result.components(separatedBy: .newlines)
            if lines.count > previewLines {
                return lines.prefix(previewLines).joined(separator: "\n")
            }
        }
        return toolData.result
    }
    
    private var needsExpandToggle: Bool {
        let lineCount = toolData.result.components(separatedBy: .newlines).count
        let hasMetadata = toolData.metadata != nil && !toolData.metadata!.isEmpty
        return lineCount > previewLines || hasMetadata
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
