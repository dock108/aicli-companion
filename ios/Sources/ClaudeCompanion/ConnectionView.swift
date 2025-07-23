import SwiftUI
import Combine

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
    @State private var selectedServer: DiscoveredClaudeServer?
    @State private var cancellables = Set<AnyCancellable>()

    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                Spacer()
                    .frame(height: 60)
            
            Image(systemName: "desktopcomputer")
                .font(.system(size: 80))
                .foregroundColor(.blue)
                .padding(.bottom, 10)

            VStack(spacing: 12) {
                Text("Connect to Claude Companion")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Connect to your Claude Code companion server to start coding on mobile")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
            }
            
            Spacer()
                .frame(height: 20)

            VStack(spacing: 16) {
                // Debug button to test tap handling
                Button(action: {
                    print("DEBUG: Test button tapped!")
                    errorMessage = "Test button was tapped successfully"
                }) {
                    Text("Test Button (Tap Me)")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                
                // Discovered servers section
                if !discoveryManager.discoveredServers.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Discovered Servers")
                                .font(.headline)
                            Spacer()
                            Button("Refresh") {
                                discoveryManager.refreshDiscovery()
                            }
                            .font(.caption)
                            .foregroundColor(.blue)
                        }

                        ForEach(discoveryManager.discoveredServers) { server in
                            DiscoveredServerRow(
                                server: server,
                                isSelected: selectedServer?.id == server.id,
                                onSelect: { selectedServer = server }
                            )
                        }
                    }
                    .padding(.horizontal)
                }

                // Auto-discovery section
                Button(action: {
                    print("Scan button tapped")
                    discoverServers()
                }) {
                    HStack {
                        if discoveryManager.isScanning {
                            ProgressView()
                                .scaleEffect(0.8)
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "wifi")
                        }
                        Text(discoveryManager.isScanning ? "Scanning..." : "Scan for Local Servers")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(discoveryManager.isScanning ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .disabled(isLoading || discoveryManager.isScanning)

                if let selectedServer = selectedServer {
                    Button(action: { connectToDiscoveredServer(selectedServer) }) {
                        HStack {
                            Image(systemName: "link")
                            Text("Connect to \(selectedServer.displayName)")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .disabled(isLoading)
                }

                Text("or")
                    .foregroundColor(.secondary)

                // Manual connection button
                Button(action: { 
                    print("Manual setup button tapped")
                    showingManualSetup = true 
                }) {
                    HStack {
                        Image(systemName: "gear")
                        Text("Manual Setup")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .foregroundColor(.primary)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
            .padding(.horizontal, 20)

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            VStack(spacing: 8) {
                Text("Need Help?")
                    .font(.headline)

                Button("Setup Instructions") {
                    // TODO: Open setup instructions
                }
                .foregroundColor(.blue)
            }
            .padding(.bottom, 30)
        }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground))
        .ignoresSafeArea(edges: .bottom)
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
                case .connecting:
                    self.isLoading = true
                    self.errorMessage = ""
                case .connected:
                    self.isLoading = false
                    self.errorMessage = ""
                case .disconnected:
                    if !self.isLoading {
                        self.isConnected = false
                    }
                }
            }
            .store(in: &cancellables)
    }
}

struct DiscoveredServerRow: View {
    let server: DiscoveredClaudeServer
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(server.displayName)
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text("\(server.address):\(server.port)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.blue)
                    } else {
                        Image(systemName: "circle")
                            .foregroundColor(.gray)
                    }
                }

                if !server.connectionInfo.isEmpty {
                    Text(server.connectionInfo)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
        )
    }
}

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
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: isConnected) { newValue in
                if newValue {
                    // Dismiss sheet when connected
                    dismiss()
                }
            }
            .onChange(of: errorMessage) { _ in
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

#Preview {
    ConnectionView(isConnected: .constant(false))
        .environmentObject(ClaudeCodeService())
        .environmentObject(SettingsManager())
}
