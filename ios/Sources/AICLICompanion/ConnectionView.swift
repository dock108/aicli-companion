import SwiftUI

/// Connection state for the view
@available(iOS 14.0, macOS 11.0, *)
enum ConnectionState {
    case `default`
    case scanning
    case connected
    case error
}

/// Dark-Slate Terminal style connection screen
@available(iOS 14.0, macOS 11.0, *)
struct ConnectionView: View {
    @Binding var isConnected: Bool
    @State private var connectionState = ConnectionState.default
    @State private var errorMessage: String?
    @State private var showManualSetup = false
    @State private var showQRScanner = false
    @State private var showHelp = false
    @State private var heroScale: CGFloat = 0.9
    @State private var heroOpacity: Double = 0
    
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var settings: SettingsManager
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer(minLength: 64)
            
            // Hero terminal chat icon
            TerminalChatIcon(size: 136, style: .gradient)
            .scaleEffect(heroScale)
            .opacity(heroOpacity)
            
            // Title and subtitle
            VStack(spacing: Spacing.sm) {
                Text("Connect to Code Companion")
                    .font(Typography.font(.heading1))
                    .foregroundColor(Colors.textPrimary(for: colorScheme))
                    .multilineTextAlignment(.center)
                
                Text("Connect your mobile device to AICLI on your desktop for seamless AI-powered development")
                    .font(Typography.font(.body))
                    .foregroundColor(Colors.textSecondary(for: colorScheme))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
                    .opacity(0.7)
            }
            
            // Action buttons
            VStack(spacing: Spacing.md) {
                // Scan QR Code button with loading state
                LoadingPrimaryButton(
                    "Scan QR Code",
                    isLoading: $showQRScanner
                ) {
                    await scanQRCode()
                }
                
                // Divider with "or"
                HStack(spacing: Spacing.sm) {
                    Rectangle()
                        .fill(Colors.divider.opacity(0.4))
                        .frame(height: 1)
                    
                    Text("or")
                        .font(Typography.font(.caption))
                        .foregroundColor(Colors.textSecondary(for: colorScheme))
                        .opacity(0.6)
                    
                    Rectangle()
                        .fill(Colors.divider.opacity(0.4))
                        .frame(height: 1)
                }
                .padding(.vertical, Spacing.xs)
                
                // Manual Setup button
                SecondaryButton("Manual Setup") {
                    showManualSetup = true
                }
            }
            .padding(.horizontal, Spacing.xl)
            
            Spacer()
            
            // Help footer link
            TextLinkButton("Need help connecting?") {
                showHelp = true
            }
            .padding(.bottom, Spacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Colors.bgBase(for: colorScheme))
        .onAppear {
            animateHero()
        }
        .sheet(isPresented: $showQRScanner) {
            #if os(iOS)
            if #available(iOS 16.0, *) {
                QRScannerSheet(
                    isConnected: $isConnected,
                    onResult: { result in
                        switch result {
                        case .success(let url):
                            handleScanResult(url.absoluteString)
                        case .failure:
                            withAnimation {
                                connectionState = .error
                                errorMessage = "Failed to scan QR code"
                            }
                        }
                        showQRScanner = false
                    }
                )
            } else {
                Text("QR scanning requires iOS 16.0 or later")
                    .padding()
            }
            #else
            VStack {
                Text("QR code scanning is not available on macOS")
                    .font(Typography.font(.body))
                    .foregroundColor(Colors.textPrimary(for: colorScheme))
                    .padding()
                
                Button("Use Manual Setup") {
                    showQRScanner = false
                    showManualSetup = true
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding()
            }
            #endif
        }
        .sheet(isPresented: $showManualSetup) {
            ManualSetupSheet(
                onConnect: handleManualConnection
            )
        }
        .sheet(isPresented: $showHelp) {
            HelpSheet()
        }
        .alert("Connection Error", isPresented: .constant(connectionState == .error)) {
            Button("OK") {
                withAnimation {
                    connectionState = .default
                    errorMessage = nil
                }
            }
        } message: {
            Text(errorMessage ?? "Failed to connect to the server")
        }
    }
    
    // MARK: - Private Methods
    
    private func animateHero() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.1)) {
            heroScale = 1.0
            heroOpacity = 1.0
        }
    }
    
    private func scanQRCode() async {
        // Simulate QR scanning
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        showQRScanner = true
    }
    
    private func handleScanResult(_ result: String) {
        showQRScanner = false
        
        // Parse QR code result
        if let connection = parseConnectionString(result) {
            saveConnection(connection)
        } else {
            withAnimation {
                connectionState = .error
                errorMessage = "Invalid QR code format"
            }
        }
    }
    
    private func handleManualConnection(_ connection: ServerConnection) {
        showManualSetup = false
        saveConnection(connection)
    }
    
    private func saveConnection(_ connection: ServerConnection) {
        withAnimation {
            connectionState = .connected
        }
        
        settings.saveConnection(address: connection.address, port: connection.port, token: connection.authToken)
        
        // Delay before transitioning
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeInOut(duration: 0.3)) {
                isConnected = true
            }
        }
    }
    
    private func parseConnectionString(_ string: String) -> ServerConnection? {
        // Format: ws://host:port/ws?token=xxx
        guard let url = URL(string: string),
              url.scheme == "ws" || url.scheme == "wss",
              let host = url.host,
              let port = url.port else {
            return nil
        }
        
        let token = url.queryParameters?["token"]
        
        return ServerConnection(
            address: host,
            port: port,
            authToken: token
        )
    }
}

// MARK: - Manual Setup Sheet
@available(iOS 16.0, macOS 13.0, *)
struct ManualSetupSheet: View {
    @State private var address = ""
    @State private var port = "3001"
    @State private var authToken = ""
    
    let onConnect: (ServerConnection) -> Void
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Server Address")
                        .font(Typography.font(.heading3))
                        .foregroundColor(Colors.textPrimary(for: colorScheme))
                    
                    TextField("192.168.1.100", text: $address)
                        .textFieldStyle(TerminalTextFieldStyle())
                    
                    Text("Port")
                        .font(Typography.font(.heading3))
                        .foregroundColor(Colors.textPrimary(for: colorScheme))
                        .padding(.top, Spacing.sm)
                    
                    TextField("3001", text: $port)
                        .textFieldStyle(TerminalTextFieldStyle())
                        .keyboardType(.numberPad)
                    
                    Text("Auth Token (optional)")
                        .font(Typography.font(.heading3))
                        .foregroundColor(Colors.textPrimary(for: colorScheme))
                        .padding(.top, Spacing.sm)
                    
                    TextField("Enter token if required", text: $authToken)
                        .textFieldStyle(TerminalTextFieldStyle())
                }
                .padding()
                
                Spacer()
                
                PrimaryButton("Connect", isEnabled: !address.isEmpty) {
                    let connection = ServerConnection(
                        address: address,
                        port: Int(port) ?? 3001,
                        authToken: authToken.isEmpty ? nil : authToken
                    )
                    onConnect(connection)
                }
                .padding()
            }
            .background(Colors.bgBase(for: colorScheme))
            .navigationTitle("Manual Setup")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Help Sheet
@available(iOS 16.0, macOS 13.0, *)
struct HelpSheet: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    Text("How to Connect")
                        .font(Typography.font(.heading2))
                        .foregroundColor(Colors.textPrimary(for: colorScheme))
                    
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        HelpStep(number: "1", text: "Install AICLI on your desktop")
                        HelpStep(number: "2", text: "Start the companion server")
                        HelpStep(number: "3", text: "Scan the QR code or enter connection details")
                        HelpStep(number: "4", text: "Start coding with AI assistance!")
                    }
                    
                    Link("View detailed setup guide", destination: URL(string: "https://github.com/aicli/aicli")!)
                        .font(Typography.font(.body))
                        .foregroundColor(Colors.accentPrimaryEnd)
                        .padding(.top)
                }
                .padding()
            }
            .background(Colors.bgBase(for: colorScheme))
            .navigationTitle("Help")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

@available(iOS 14.0, macOS 11.0, *)
struct HelpStep: View {
    let number: String
    let text: String
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Text(number)
                .font(Typography.font(.terminal))
                .foregroundColor(Colors.accentPrimaryEnd)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .stroke(Colors.accentPrimaryEnd, lineWidth: 2)
                )
            
            Text(text)
                .font(Typography.font(.body))
                .foregroundColor(Colors.textPrimary(for: colorScheme))
        }
    }
}

// MARK: - Terminal Text Field Style
struct TerminalTextFieldStyle: TextFieldStyle {
    @Environment(\.colorScheme) var colorScheme
    
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(Typography.font(.code))
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Colors.bgCard(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Colors.strokeLight, lineWidth: 1)
                    )
            )
            .foregroundColor(Colors.textPrimary(for: colorScheme))
    }
}

// MARK: - URL Extension
extension URL {
    var queryParameters: [String: String]? {
        guard let components = URLComponents(url: self, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return nil
        }
        
        return queryItems.reduce(into: [String: String]()) { result, item in
            result[item.name] = item.value
        }
    }
}

// MARK: - Preview
@available(iOS 17.0, macOS 14.0, *)
#Preview("Connection View") {
    ConnectionView(isConnected: .constant(false))
        .environmentObject(SettingsManager())
        .preferredColorScheme(.dark)
}

@available(iOS 17.0, macOS 14.0, *)
#Preview("Manual Setup") {
    ManualSetupSheet { connection in
        print("Connect to: \(connection)")
    }
    .preferredColorScheme(.dark)
}