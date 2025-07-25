import SwiftUI
import Combine

@available(iOS 16.0, macOS 13.0, *)
struct ConnectionView: View {
    @EnvironmentObject var claudeService: ClaudeCodeService
    @EnvironmentObject var settings: SettingsManager
    @StateObject private var discoveryManager = ServiceDiscoveryManager()
    @StateObject private var webSocketService = WebSocketService()
    @Binding var isConnected: Bool

    @State private var serverAddress = ""
    @State private var serverPort = "3001"
    @State private var authToken = ""
    @State private var useSecureConnection = false
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showingManualSetup = false
    @State private var showingQRScanner = false
    @State private var selectedServer: DiscoveredClaudeServer?
    @State private var cancellables = Set<AnyCancellable>()
    @State private var connectionState: ConnectionState = .default
    
    enum ConnectionState {
        case `default`
        case scanning
        case connected
        case error
    }
    
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: Spacing.Layout.navBarToHero)
            
            // Hero Illustration
            ZStack {
                Circle()
                    .fill(Gradients.heroIcon)
                    .frame(width: 120, height: 120)
                
                if connectionState == .connected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 60, weight: .semibold))
                        .foregroundColor(.white)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.white)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .scaleEffect(connectionState == .connected ? 1.1 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: connectionState)
            
            Spacer()
                .frame(height: Spacing.Layout.heroToTitle)

            // Title Block
            VStack(spacing: Spacing.sm) {
                Text("Connect to Code Companion")
                    .h1()
                    .fixedSize(horizontal: false, vertical: true)

                Text("Scan the QR code displayed by your desktop server to start coding on mobile.")
                    .secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 280)
            }
            
            Spacer()
                .frame(height: Spacing.Layout.titleToButton)

            // Buttons section
            VStack(spacing: 0) {
                // Primary CTA
                PrimaryButton(
                    "Scan QR Code",
                    isLoading: connectionState == .scanning,
                    isEnabled: connectionState != .scanning
                ) {
                    showingQRScanner = true
                    connectionState = .scanning
                }
                .padding(.horizontal, Spacing.Layout.screenPaddingHorizontal)
                
                Spacer()
                    .frame(height: Spacing.Layout.buttonToDivider)
                
                // Divider
                DividerView()
                    .padding(.horizontal, Spacing.Layout.screenPaddingHorizontal)
                
                Spacer()
                    .frame(height: Spacing.Layout.dividerToSecondaryButton)
                
                // Secondary CTA
                SecondaryButton("Manual Setup") {
                    showingManualSetup = true
                }
                .padding(.horizontal, Spacing.Layout.screenPaddingHorizontal)
                
                // Auto-discovery servers (if any)
                if !discoveryManager.discoveredServers.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Discovered Servers")
                            .font(Typography.font(.small))
                            .foregroundColor(Colors.secondaryText)
                            .padding(.top, Spacing.md)
                        
                        ForEach(discoveryManager.discoveredServers) { server in
                            DiscoveredServerCard(
                                server: server,
                                isSelected: selectedServer?.id == server.id,
                                onSelect: {
                                    selectedServer = server
                                    connectToDiscoveredServer(server)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, Spacing.Layout.screenPaddingHorizontal)
                }
            }

            Spacer()
                .frame(height: Spacing.Layout.secondaryButtonToHelp)
            
            // Help Footer
            VStack(spacing: Spacing.xs) {
                Text("Need Help?")
                    .font(Typography.font(.link))
                    .foregroundColor(Colors.ink900)
                
                Button(action: {
                    // TODO: Open setup instructions
                }) {
                    Text("Setup Instructions")
                        .linkText()
                }
            }
            .padding(.bottom, Spacing.Layout.screenPaddingBottom)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Colors.adaptiveBackground(colorScheme: colorScheme))
        .overlay(
            // Error state card
            Group {
                if connectionState == .error && !errorMessage.isEmpty {
                    ErrorCard(message: errorMessage) {
                        withAnimation {
                            connectionState = .default
                            errorMessage = ""
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 100)
                }
            }
            , alignment: .top
        )
        .ignoresSafeArea(edges: .bottom)
        .sheet(isPresented: $showingQRScanner) {
            QRScannerSheet(isConnected: $isConnected) { result in
                showingQRScanner = false
                connectionState = .default
                // Handle QR scan result
                if case .success(let url) = result {
                    // Parse and connect using the URL
                    handleQRCodeURL(url)
                }
            }
        }
        .sheet(isPresented: $showingManualSetup) {
            ManualConnectionView(
                serverAddress: $serverAddress,
                serverPort: $serverPort,
                authToken: $authToken,
                useSecureConnection: $useSecureConnection,
                isConnected: $isConnected,
                errorMessage: $errorMessage,
                onConnect: connectManually
            )
        }
        .onAppear {
            // Start discovery when view appears
            if discoveryManager.discoveredServers.isEmpty && !discoveryManager.isScanning {
                discoveryManager.startDiscovery()
            }
        }
    }

    private func discoverServers() {
        print("Starting server discovery...")
        errorMessage = ""
        discoveryManager.startDiscovery()
    }

    private func connectToDiscoveredServer(_ server: DiscoveredClaudeServer) {
        isLoading = true
        errorMessage = ""

        // First validate the server
        discoveryManager.validateServer(server) { result in
            switch result {
            case .success(let connection):
                // Connect using WebSocket service
                self.connectWithWebSocket(connection, authToken: nil)
            case .failure(let error):
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = "Server validation failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func connectManually() {
        // Clean up the address - remove any protocol prefix if present
        var cleanAddress = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanAddress.hasPrefix("http://") {
            cleanAddress = String(cleanAddress.dropFirst(7))
        } else if cleanAddress.hasPrefix("https://") {
            cleanAddress = String(cleanAddress.dropFirst(8))
        }
        
        print("Attempting manual connection to: \(cleanAddress):\(serverPort)")
        
        let config = ManualServerConfiguration(
            address: cleanAddress,
            port: Int(serverPort) ?? 3001,
            isSecure: useSecureConnection,
            authToken: authToken.isEmpty ? nil : authToken
        )

        isLoading = true
        errorMessage = ""

        discoveryManager.validateManualConfiguration(config) { result in
            print("Validation result received")
            switch result {
            case .success(let connection):
                print("Validation successful, connecting to WebSocket...")
                self.connectWithWebSocket(connection, authToken: config.authToken)
            case .failure(let error):
                print("Validation failed: \(error)")
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = "Connection failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func handleQRCodeURL(_ url: URL) {
        // Parse the QR code URL and extract connection details
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            connectionState = .error
            errorMessage = "Invalid QR code format"
            return
        }
        
        // Extract host, port, and token from URL
        if let host = components.host,
           let port = components.port {
            serverAddress = host
            serverPort = String(port)
            
            // Extract token from query parameters
            if let token = components.queryItems?.first(where: { $0.name == "token" })?.value {
                authToken = token
            }
            
            // Attempt connection
            connectManually()
        } else {
            connectionState = .error
            errorMessage = "QR code missing connection details"
        }
    }
    
    private func connectWithWebSocket(_ connection: ServerConnection, authToken: String?) {
        guard let wsURL = connection.wsURL else {
            DispatchQueue.main.async {
                self.isLoading = false
                self.errorMessage = "Invalid WebSocket URL"
            }
            return
        }

        webSocketService.connect(to: wsURL, authToken: authToken)

        // Set up connection state observer
        webSocketService.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { connected in
                if connected {
                    self.settings.saveConnection(
                        address: connection.address,
                        port: connection.port,
                        token: authToken
                    )
                    self.isConnected = true
                    self.isLoading = false
                } else if !self.isLoading {
                    // Only update if we're not in the middle of connecting
                    self.isConnected = false
                }
            }
            .store(in: &cancellables)

        webSocketService.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { state in
                switch state {
                case .error(let message):
                    self.isLoading = false
                    self.errorMessage = message
                    self.connectionState = .error
                case .connecting:
                    self.isLoading = true
                    self.errorMessage = ""
                    self.connectionState = .scanning
                case .connected:
                    self.isLoading = false
                    self.errorMessage = ""
                    self.connectionState = .connected
                    // Add a small delay before transitioning to the chat view
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.isConnected = true
                    }
                case .disconnected:
                    if !self.isLoading {
                        self.isConnected = false
                        self.connectionState = .default
                    }
                }
            }
            .store(in: &cancellables)
    }
}

@available(iOS 15.0, macOS 12.0, *)
struct DiscoveredServerCard: View {
    let server: DiscoveredClaudeServer
    let isSelected: Bool
    let onSelect: () -> Void
    
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(server.displayName)
                            .font(Typography.font(.body))
                            .foregroundColor(Colors.adaptivePrimaryText(colorScheme: colorScheme))

                        Text("\(server.address):\(server.port)")
                            .font(Typography.font(.small))
                            .foregroundColor(Colors.adaptiveSecondaryText(colorScheme: colorScheme))
                    }

                    Spacer()

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? Colors.brandBlue500 : Colors.ink700.opacity(0.3))
                        .font(.system(size: 20))
                }

                if !server.connectionInfo.isEmpty {
                    Text(server.connectionInfo)
                        .font(Typography.font(.small))
                        .foregroundColor(Colors.adaptiveSecondaryText(colorScheme: colorScheme))
                }
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.card)
                    .fill(isSelected ? Colors.brandBlue500.opacity(0.1) : Colors.surface10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.card)
                    .stroke(isSelected ? Colors.brandBlue500 : Color.clear, lineWidth: 2)
            )
            .shadow(Shadows.medium)
        }
        .buttonStyle(.plain)
    }
}

@available(iOS 15.0, macOS 12.0, *)
struct ManualConnectionView: View {
    @Binding var serverAddress: String
    @Binding var serverPort: String
    @Binding var authToken: String
    @Binding var useSecureConnection: Bool
    @Binding var isConnected: Bool
    @Binding var errorMessage: String
    let onConnect: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isConnecting = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("SERVER DETAILS")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            TextField("Server Address", text: $serverAddress)
                                .textFieldStyle(.roundedBorder)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .placeholder(when: serverAddress.isEmpty) {
                                    Text("192.168.1.100 or myserver.local")
                                        .foregroundColor(.gray)
                                }
                            
                            TextField("Port", text: $serverPort)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.numberPad)
                            
                            Toggle("Use Secure Connection (TLS)", isOn: $useSecureConnection)
                        }
                        .padding(.vertical, 8)
                    }
                    
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("AUTHENTICATION")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            SecureField("Auth Token", text: $authToken)
                                .textFieldStyle(.roundedBorder)
                            
                            Text("Optional: Enter auth token if your server requires authentication")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                    
                    Section {
                        Button(action: {
                            print("Connect button tapped - Address: \(serverAddress), Port: \(serverPort)")
                            isConnecting = true
                            onConnect()
                            // Don't dismiss immediately - let the connection complete first
                        }) {
                            HStack {
                                if isConnecting {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                } else {
                                    Text("Connect")
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(serverAddress.isEmpty || isConnecting ? Color.gray : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .listRowBackground(Color.clear)
                        .disabled(serverAddress.isEmpty || isConnecting)
                    }
                    
                    if !errorMessage.isEmpty {
                        Section {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("Manual Setup")
            #if os(iOS)

            .navigationBarTitleDisplayMode(.inline)

            #endif
            .onChange(of: isConnected) { oldValue, newValue in
                if newValue {
                    // Dismiss sheet when connected
                    dismiss()
                }
            }
            .onChange(of: errorMessage) { oldValue, newValue in
                // Stop loading when error occurs
                isConnecting = false
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

@available(iOS 13.0, macOS 10.15, *)
extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content) -> some View {
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
#Preview {
    ConnectionView(isConnected: .constant(false))
        .environmentObject(ClaudeCodeService())
        .environmentObject(SettingsManager())
}
