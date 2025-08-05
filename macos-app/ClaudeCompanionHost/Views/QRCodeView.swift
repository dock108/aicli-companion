//
//  QRCodeView.swift
//  ClaudeCompanionHost
//
//  Displays a QR code for mobile app connection
//

import SwiftUI
import CoreImage.CIFilterBuiltins

struct QRCodeView: View {
    let connectionString: String
    @State private var qrImage: NSImage?
    @State private var copied = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("Mobile Connection")
                        .font(.headline)
                    
                    Text("Scan with Claude Companion app")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            // QR Code
            if let qrImage = qrImage {
                Image(nsImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(12)
                    .shadow(radius: 5)
            } else {
                ProgressView()
                    .frame(width: 200, height: 200)
            }
            
            // Connection String
            VStack(spacing: 8) {
                Text("Connection String")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text(connectionString)
                    .font(.system(.caption, design: .monospaced))
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                    .contextMenu {
                        Button("Copy") {
                            copyConnectionString()
                        }
                    }
            }
            
            // Copy Button
            Button(action: copyConnectionString) {
                HStack {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .symbolEffect(.bounce, value: copied)
                    
                    Text(copied ? "Copied!" : "Copy Connection String")
                }
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(copied)
            
            // Instructions
            VStack(alignment: .leading, spacing: 4) {
                Label("Open Claude Companion on your iOS device", systemImage: "1.circle.fill")
                Label("Tap the + button to add a server", systemImage: "2.circle.fill")
                Label("Scan this QR code or paste the connection string", systemImage: "3.circle.fill")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)
        }
        .padding()
        .frame(width: 350, height: 500)
        .background(MacOSVisualEffectView())
        .onAppear {
            generateQRCode()
        }
    }
    
    private func generateQRCode() {
        DispatchQueue.global(qos: .userInitiated).async {
            let context = CIContext()
            let filter = CIFilter.qrCodeGenerator()
            
            filter.message = Data(connectionString.utf8)
            filter.correctionLevel = "H"
            
            if let outputImage = filter.outputImage {
                // Scale up the image
                let scale = 10.0
                let transform = CGAffineTransform(scaleX: scale, y: scale)
                let scaledImage = outputImage.transformed(by: transform)
                
                if let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) {
                    let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: 200, height: 200))
                    
                    DispatchQueue.main.async {
                        self.qrImage = nsImage
                    }
                }
            }
        }
    }
    
    private func copyConnectionString() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(connectionString, forType: .string)
        
        withAnimation(.easeInOut(duration: 0.2)) {
            copied = true
        }
        
        // Reset after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.2)) {
                copied = false
            }
        }
        
        // Play sound if enabled
        if SettingsManager.shared.enableSounds {
            NSSound.beep()
        }
    }
}