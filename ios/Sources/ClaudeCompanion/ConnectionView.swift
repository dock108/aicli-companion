import SwiftUI

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

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text("Connect to Claude Code")
                .font(.title)
                .fontWeight(.bold)

            Text("Connect to your Claude Code companion server to start coding on mobile")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            VStack(spacing: 16) {
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
                Button(action: discoverServers) {
                    HStack {
                        if discoveryManager.isScanning {
                            ProgressView()
                                .scaleEffect(0.8)
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
                    .disabled(isLoading)
                }

                Text("or")
                    .foregroundColor(.secondary)

                // Manual connection button
                Button(action: { showingManualSetup = true }) {
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
            }
            .padding(.horizontal)

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding(.horizontal)
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
        }
        .padding()
        .sheet(isPresented: $showingManualSetup) {
            ManualConnectionView(
                serverAddress: $serverAddress,
                serverPort: $serverPort,
                authToken: $authToken,
                useSecureConnection: $useSecureConnection,
                isConnected: $isConnected,
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
        let config = ManualServerConfiguration(
            address: serverAddress,
            port: Int(serverPort) ?? 3001,
            isSecure: useSecureConnection,
            authToken: authToken.isEmpty ? nil : authToken
        )

        isLoading = true
        errorMessage = ""

        discoveryManager.validateManualConfiguration(config) { result in
            switch result {
            case .success(let connection):
                self.connectWithWebSocket(connection, authToken: config.authToken)
            case .failure(let error):
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
            .store(in: &webSocketService.cancellables)

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
            .store(in: &webSocketService.cancellables)
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
        .buttonStyle(PlainButtonStyle())
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
    let onConnect: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Server Details")) {
                    TextField("Server Address", text: $serverAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .placeholder(when: serverAddress.isEmpty) {
                            Text("192.168.1.100 or myserver.local")
                                .foregroundColor(.gray)
                        }

                    TextField("Port", text: $serverPort)
                        .keyboardType(.numberPad)

                    Toggle("Use Secure Connection (TLS)", isOn: $useSecureConnection)
                }

                Section(header: Text("Authentication"), footer: Text("Optional: Enter auth token if your server requires authentication")) {
                    SecureField("Auth Token", text: $authToken)
                }

                Section {
                    Button("Connect") {
                        onConnect()
                        dismiss()
                    }
                    .disabled(serverAddress.isEmpty)
                }
            }
            .navigationTitle("Manual Setup")
            .navigationBarTitleDisplayMode(.inline)
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
