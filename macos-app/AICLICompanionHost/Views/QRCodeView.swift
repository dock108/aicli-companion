//
//  QRCodeView.swift
//  AICLICompanionHost
//
//  Displays a QR code for mobile app connection
//

import SwiftUI
import CoreImage.CIFilterBuiltins

struct QRCodeView: View {
    let connectionString: String
    @State private var qrImage: NSImage?
    @State private var qrCodeDataURL: String?
    @State private var copied = false
    @State private var isLoadingFromServer = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("Mobile Connection")
                        .font(.headline)

                    Text("Scan with AICLI Companion app")
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
            .padding(.bottom, 8)

            // QR Code
            if let qrCodeDataURL = qrCodeDataURL,
               let url = URL(string: qrCodeDataURL),
               let data = try? Data(contentsOf: url),
               let image = NSImage(data: data) {
                // Use QR code from server
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .padding(20)
                    .background(Color.white)
                    .cornerRadius(12)
                    .shadow(radius: 3)
            } else if let qrImage = qrImage {
                // Use locally generated QR code as fallback
                Image(nsImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .padding(20)
                    .background(Color.white)
                    .cornerRadius(12)
                    .shadow(radius: 3)
            } else {
                ProgressView()
                    .frame(width: 200, height: 200)
            }

            // Connection String
            VStack(spacing: 10) {
                Text("Connection String")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(connectionString)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(10)
                    .frame(maxWidth: .infinity)
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
            .controlSize(.regular)
            .buttonStyle(.borderedProminent)
            .disabled(copied)

            Spacer(minLength: 16)

            // Instructions
            VStack(alignment: .leading, spacing: 6) {
                Label("Open AICLI Companion on your iOS device", systemImage: "1.circle.fill")
                Label("Tap the + button to add a server", systemImage: "2.circle.fill")
                Label("Scan this QR code or paste the connection string", systemImage: "3.circle.fill")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)
        }
        .padding(24)
        .frame(width: 400, height: 580)
        .background(MacOSVisualEffectView())
        .onAppear {
            fetchQRCodeFromServer()
        }
    }

    private func fetchQRCodeFromServer() {
        // Extract port from connection string
        let components = connectionString.components(separatedBy: ":")
        let port = components.last?.components(separatedBy: "?").first ?? "3001"
        
        guard let url = URL(string: "http://localhost:\(port)/api/auth/setup") else {
            generateQRCodeLocally()
            return
        }
        
        var request = URLRequest(url: url, timeoutInterval: 3.0)
        
        // Extract auth token if present in connection string
        if connectionString.contains("token=") {
            let tokenPart = connectionString.components(separatedBy: "token=").last ?? ""
            let token = tokenPart.components(separatedBy: "&").first ?? ""
            if !token.isEmpty {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isLoadingFromServer = false
                
                guard error == nil,
                      let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let qrCode = json["qrCode"] as? [String: Any],
                      let dataUrl = qrCode["dataUrl"] as? String else {
                    // Fallback to local generation
                    self.generateQRCodeLocally()
                    return
                }
                
                self.qrCodeDataURL = dataUrl
            }
        }.resume()
    }

    private func generateQRCodeLocally() {
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