import SwiftUI

struct ConnectionView: View {
    @EnvironmentObject var claudeService: ClaudeCodeService
    @EnvironmentObject var settings: SettingsManager
    @Binding var isConnected: Bool
    
    @State private var serverAddress = ""
    @State private var serverPort = "3001"
    @State private var authToken = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showingManualSetup = false
    
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
                // Auto-discovery section
                Button(action: discoverServers) {
                    HStack {
                        Image(systemName: "wifi")
                        Text("Scan for Local Servers")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(isLoading)
                
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
                isConnected: $isConnected,
                onConnect: connectManually
            )
        }
    }
    
    private func discoverServers() {
        isLoading = true
        errorMessage = ""
        
        claudeService.discoverLocalServers { result in
            DispatchQueue.main.async {
                isLoading = false
                
                switch result {
                case .success(let servers):
                    if let server = servers.first {
                        // Auto-connect to first discovered server
                        connectToServer(address: server.address, port: server.port, token: "")
                    } else {
                        errorMessage = "No Claude Code servers found on local network"
                    }
                case .failure(let error):
                    errorMessage = "Discovery failed: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func connectManually() {
        connectToServer(address: serverAddress, port: Int(serverPort) ?? 3001, token: authToken)
    }
    
    private func connectToServer(address: String, port: Int, token: String) {
        isLoading = true
        errorMessage = ""
        
        claudeService.connect(to: address, port: port, authToken: token) { result in
            DispatchQueue.main.async {
                isLoading = false
                
                switch result {
                case .success:
                    settings.saveConnection(address: address, port: port, token: token)
                    isConnected = true
                case .failure(let error):
                    errorMessage = "Connection failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

struct ManualConnectionView: View {
    @Binding var serverAddress: String
    @Binding var serverPort: String
    @Binding var authToken: String
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