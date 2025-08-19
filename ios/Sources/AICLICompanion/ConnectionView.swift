import SwiftUI

/// Connection state for the view
@available(iOS 16.0, macOS 13.0, *)
enum ConnectionState {
    case `default`
    case scanning
    case connected
    case error
}

/// Dark-Slate Terminal style connection screen
@available(iOS 16.0, macOS 13.0, *)
struct ConnectionView: View {
    @Binding var isConnected: Bool
    @State private var connectionState = ConnectionState.default
    @State private var errorMessage: String?
    @State private var showManualSetup = false
    @State private var showQRScanner = false
    @StateObject private var loadingStateCoordinator = LoadingStateCoordinator.shared
    
    private var isLoadingQR: Bool {
        loadingStateCoordinator.isLoading(.qrScanning)
    }
    @State private var showHelp = false
    @State private var heroScale: CGFloat = 0.9
    @State private var heroOpacity: Double = 0
    @State private var showingSettings = false
    
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
                    isLoading: Binding(
                        get: { loadingStateCoordinator.isLoading(.qrScanning) },
                        set: { newValue in
                            if newValue {
                                loadingStateCoordinator.startLoading(.qrScanning)
                            } else {
                                loadingStateCoordinator.stopLoading(.qrScanning)
                            }
                        }
                    )
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
        .overlay(alignment: .topTrailing) {
            // Settings button
            Button(action: {
                showingSettings = true
            }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 20))
                    .foregroundColor(Colors.textSecondary(for: colorScheme))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.top, 60)
            .padding(.trailing, 16)
        }
        .onAppear {
            animateHero()
        }
        .sheet(isPresented: $showQRScanner, onDismiss: {
            // Reset loading state when sheet is dismissed
            loadingStateCoordinator.stopLoading(.qrScanning)
        }) {
            #if os(iOS)
            if #available(iOS 16.0, *) {
                QRScannerSheet(
                    isConnected: $isConnected,
                    onResult: { result in
                        switch result {
                        case .success(let url):
                            handleScanResult(url.absoluteString)
                        case .failure(let error):
                            withAnimation {
                                connectionState = .error
                                errorMessage = error.localizedDescription
                            }
                        }
                        showQRScanner = false
                        loadingStateCoordinator.stopLoading(.qrScanning)
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
                .buttonStyle(.borderedProminent)
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
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
            }
        }
        .alert("Connection Error", isPresented: Binding(
            get: { connectionState == .error },
            set: { _ in
                withAnimation {
                    connectionState = .default
                    errorMessage = nil
                }
            }
        )) {
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
        // Show QR scanner immediately
        showQRScanner = true
        // The loading state will be managed by LoadingPrimaryButton
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
        // Format: http://host:port?token=xxx or https://domain.ngrok.app?token=xxx
        print("🔍 Parsing QR code: \(string)")
        
        guard let url = URL(string: string),
              url.scheme == "http" || url.scheme == "https",
              let host = url.host else {
            print("❌ Failed to parse URL - scheme: \(URL(string: string)?.scheme ?? "nil"), host: \(URL(string: string)?.host ?? "nil")")
            return nil
        }
        
        // Use explicit port if available, otherwise use default ports
        let port: Int
        if let explicitPort = url.port {
            port = explicitPort
        } else {
            // Use default ports: 443 for https, 80 for http
            port = (url.scheme == "https") ? 443 : 80
        }
        
        let token = url.queryParameters?["token"]
        let isSecure = (url.scheme == "https")
        
        print("✅ Parsed - host: \(host), port: \(port), token: \(token ?? "none"), secure: \(isSecure)")
        
        return ServerConnection(
            name: "Manual Server",
            address: host,
            port: port,
            authToken: token,
            isSecure: isSecure
        )
    }
}

// MARK: - Manual Setup Sheet
@available(iOS 16.0, macOS 13.0, *)
struct ManualSetupSheet: View {
    @State private var serverURL = ""
    @State private var authToken = ""
    @State private var showError = false
    @State private var errorMessage = ""
    
    let onConnect: (ServerConnection) -> Void
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Server URL")
                        .font(Typography.font(.heading3))
                        .foregroundColor(Colors.textPrimary(for: colorScheme))
                    
                    TextField("http://192.168.1.100:3001 or https://domain.ngrok.app", text: $serverURL)
                        .textFieldStyle(TerminalTextFieldStyle())
                        #if os(iOS)
                        .autocapitalization(.none)
                        #endif
                        .disableAutocorrection(true)
                    
                    Text("Enter the HTTP URL from your server. This can be a local address (http://192.168.1.100:3001) or an ngrok URL (https://domain.ngrok-free.app)")
                        .font(Typography.font(.caption))
                        .foregroundColor(Colors.textSecondary(for: colorScheme))
                        .padding(.top, Spacing.xs)
                    
                    Text("Auth Token (optional)")
                        .font(Typography.font(.heading3))
                        .foregroundColor(Colors.textPrimary(for: colorScheme))
                        .padding(.top, Spacing.sm)
                    
                    TextField("Enter token if required", text: $authToken)
                        .textFieldStyle(TerminalTextFieldStyle())
                        #if os(iOS)
                        .autocapitalization(.none)
                        #endif
                        .disableAutocorrection(true)
                }
                .padding()
                
                Spacer()
                
                PrimaryButton("Connect", isEnabled: !serverURL.isEmpty) {
                    if let connection = parseManualURL(serverURL, token: authToken.isEmpty ? nil : authToken) {
                        onConnect(connection)
                    } else {
                        errorMessage = "Invalid URL format. Please use http:// or https:// scheme."
                        showError = true
                    }
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
            .alert("Invalid URL", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func parseManualURL(_ urlString: String, token: String?) -> ServerConnection? {
        var normalizedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Add http:// prefix if no scheme is present
        if !normalizedURL.contains("://") {
            normalizedURL = "http://\(normalizedURL)"
        }
        
        // Add token if provided and not in URL
        if let token = token, !token.isEmpty, !normalizedURL.contains("?token=") {
            normalizedURL = normalizedURL.contains("?") ? "\(normalizedURL)&token=\(token)" : "\(normalizedURL)?token=\(token)"
        }
        
        // Parse using the same logic as QR scanner
        guard let url = URL(string: normalizedURL),
              url.scheme == "http" || url.scheme == "https",
              let host = url.host else {
            return nil
        }
        
        // Use explicit port if available, otherwise use default ports
        let port: Int
        if let explicitPort = url.port {
            port = explicitPort
        } else {
            // Use default ports: 443 for https, 80 for http
            port = (url.scheme == "https") ? 443 : 80
        }
        
        // Extract token from URL if present, otherwise use the provided one
        let finalToken = url.queryParameters?["token"] ?? token
        let isSecure = (url.scheme == "https")
        
        return ServerConnection(
            name: "Manual Server",
            address: host,
            port: port,
            authToken: finalToken,
            isSecure: isSecure
        )
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

@available(iOS 16.0, macOS 13.0, *)
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
@available(iOS 13.0, macOS 10.15, *)
struct TerminalTextFieldStyle: TextFieldStyle {
    @Environment(\.colorScheme) var colorScheme
    
    // swiftlint:disable:next identifier_name
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
