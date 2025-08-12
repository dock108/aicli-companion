import Foundation
import Combine

@available(iOS 16.0, macOS 13.0, *)
@MainActor
public class SecurityManager: ObservableObject {
    static let shared = SecurityManager()
    
    // MARK: - Published Properties
    @Published var configuration: SecurityConfiguration = .default
    @Published var auditLog: [AuditLogEntry] = []
    @Published var pendingPermissions: [PermissionRequest] = []
    @Published var isLoading = false
    @Published var lastError: String?
    
    // Quick toggles
    @Published var filterCommands: Bool = true
    @Published var blockDestructive: Bool = true
    @Published var readOnlyMode: Bool = false
    
    private let httpService = HTTPAICLIService.shared
    private let settingsManager = SettingsManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        loadConfiguration()
        setupBindings()
    }
    
    // MARK: - Setup
    
    private func setupBindings() {
        // Sync quick toggles with configuration
        $filterCommands
            .sink { [weak self] enabled in
                guard let self = self else { return }
                if !enabled {
                    self.configuration.preset = .unrestricted
                }
            }
            .store(in: &cancellables)
        
        $readOnlyMode
            .sink { [weak self] enabled in
                guard let self = self else { return }
                self.configuration.readOnlyMode = enabled
            }
            .store(in: &cancellables)
        
        // Auto-save configuration changes
        $configuration
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] config in
                self?.saveConfiguration(config)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Configuration Management
    
    func loadConfiguration() {
        if let data = UserDefaults.standard.data(forKey: "SecurityConfiguration"),
           let config = try? JSONDecoder().decode(SecurityConfiguration.self, from: data) {
            self.configuration = config
            self.readOnlyMode = config.readOnlyMode
            self.filterCommands = config.preset != .unrestricted
            self.blockDestructive = config.requireConfirmation
        }
    }
    
    func saveConfiguration(_ config: SecurityConfiguration) {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: "SecurityConfiguration")
        }
    }
    
    // MARK: - Server Communication
    
    func fetchCurrentConfiguration() async {
        isLoading = true
        lastError = nil
        
        do {
            guard let serverURL = settingsManager.serverURL else {
                throw URLError(.badURL)
            }
            
            let url = serverURL.appendingPathComponent("api/security/settings")
            let (data, _) = try await URLSession.shared.data(from: url)
            
            let response = try JSONDecoder().decode(SecurityAPIResponse.self, from: data)
            if response.success, let config = response.config {
                await MainActor.run {
                    self.configuration = config
                    self.readOnlyMode = config.readOnlyMode
                    self.filterCommands = config.preset != .unrestricted
                    self.blockDestructive = config.requireConfirmation
                }
            }
        } catch {
            await MainActor.run {
                self.lastError = error.localizedDescription
            }
        }
        
        await MainActor.run {
            self.isLoading = false
        }
    }
    
    func updateServerConfiguration() async {
        isLoading = true
        lastError = nil
        
        do {
            guard let serverURL = settingsManager.serverURL else {
                throw URLError(.badURL)
            }
            
            let url = serverURL.appendingPathComponent("api/security/settings")
            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(configuration)
            
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(SecurityAPIResponse.self, from: data)
            
            if !response.success {
                throw NSError(domain: "SecurityManager", code: 0,
                            userInfo: [NSLocalizedDescriptionKey: response.error ?? "Update failed"])
            }
        } catch {
            await MainActor.run {
                self.lastError = error.localizedDescription
            }
        }
        
        await MainActor.run {
            self.isLoading = false
        }
    }
    
    // MARK: - Audit Log
    
    func fetchAuditLog(limit: Int = 100) async {
        do {
            guard let serverURL = settingsManager.serverURL else {
                throw URLError(.badURL)
            }
            
            let url = serverURL.appendingPathComponent("api/security/audit")
                .appending(queryItems: [URLQueryItem(name: "limit", value: String(limit))])
            
            let (data, _) = try await URLSession.shared.data(from: url)
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let response = try decoder.decode(AuditAPIResponse.self, from: data)
            
            if response.success {
                await MainActor.run {
                    self.auditLog = response.entries
                }
            }
        } catch {
            await MainActor.run {
                self.lastError = error.localizedDescription
            }
        }
    }
    
    func clearAuditLog() async {
        do {
            guard let serverURL = settingsManager.serverURL else {
                throw URLError(.badURL)
            }
            
            let url = serverURL.appendingPathComponent("api/security/audit")
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            
            let (_, _) = try await URLSession.shared.data(for: request)
            
            await MainActor.run {
                self.auditLog = []
            }
        } catch {
            await MainActor.run {
                self.lastError = error.localizedDescription
            }
        }
    }
    
    // MARK: - Command Testing
    
    func testCommand(_ command: String, workingDirectory: String = "/tmp") async -> TestCommandResponse? {
        do {
            guard let serverURL = settingsManager.serverURL else {
                throw URLError(.badURL)
            }
            
            let url = serverURL.appendingPathComponent("api/security/test")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let body = ["command": command, "workingDirectory": workingDirectory]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(TestCommandResponse.self, from: data)
            
            return response
        } catch {
            await MainActor.run {
                self.lastError = error.localizedDescription
            }
            return nil
        }
    }
    
    // MARK: - Directory Management
    
    func addSafeDirectory(_ path: String) {
        if !configuration.safeDirectories.contains(path) {
            configuration.safeDirectories.append(path)
            Task {
                await updateServerConfiguration()
            }
        }
    }
    
    func removeSafeDirectory(_ path: String) {
        configuration.safeDirectories.removeAll { $0 == path }
        Task {
            await updateServerConfiguration()
        }
    }
    
    // MARK: - Command Patterns
    
    func addBlockedCommand(_ pattern: String) {
        if !configuration.blockedCommands.contains(pattern) {
            configuration.blockedCommands.append(pattern)
            Task {
                await updateServerConfiguration()
            }
        }
    }
    
    func removeBlockedCommand(_ pattern: String) {
        configuration.blockedCommands.removeAll { $0 == pattern }
        Task {
            await updateServerConfiguration()
        }
    }
    
    // MARK: - Presets
    
    func applyPreset(_ preset: SecurityPreset) {
        configuration.preset = preset
        
        switch preset {
        case .unrestricted:
            configuration.blockedCommands = []
            configuration.requireConfirmation = false
            configuration.readOnlyMode = false
            filterCommands = false
            blockDestructive = false
            readOnlyMode = false
            
        case .standard:
            configuration.blockedCommands = [
                "rm -rf /",
                "rm -rf /*",
                "format",
                "diskutil eraseDisk",
                "dd if=/dev/zero of=/dev/",
                "mkfs",
                ":(){ :|:& };:"
            ]
            configuration.requireConfirmation = true
            configuration.readOnlyMode = false
            filterCommands = true
            blockDestructive = true
            readOnlyMode = false
            
        case .restricted:
            configuration.blockedCommands = ["*"]
            configuration.requireConfirmation = true
            configuration.readOnlyMode = true
            filterCommands = true
            blockDestructive = true
            readOnlyMode = true
            
        case .custom:
            // Keep current settings
            break
        }
        
        Task {
            await updateServerConfiguration()
        }
    }
    
    // MARK: - Permission Requests
    
    func fetchPendingPermissions() async {
        // Implementation for fetching pending permissions
        // This would connect to the WebSocket or poll the server
    }
    
    func approvePermission(_ requestId: String) async {
        do {
            guard let serverURL = settingsManager.serverURL else {
                throw URLError(.badURL)
            }
            
            let url = serverURL.appendingPathComponent("api/security/permissions/\(requestId)/approve")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            
            let (_, _) = try await URLSession.shared.data(for: request)
            
            // Remove from pending list
            await MainActor.run {
                self.pendingPermissions.removeAll { $0.id == requestId }
            }
        } catch {
            await MainActor.run {
                self.lastError = error.localizedDescription
            }
        }
    }
    
    func denyPermission(_ requestId: String, reason: String? = nil) async {
        do {
            guard let serverURL = settingsManager.serverURL else {
                throw URLError(.badURL)
            }
            
            let url = serverURL.appendingPathComponent("api/security/permissions/\(requestId)/deny")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            if let reason = reason {
                let body = ["reason": reason]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
            }
            
            let (_, _) = try await URLSession.shared.data(for: request)
            
            // Remove from pending list
            await MainActor.run {
                self.pendingPermissions.removeAll { $0.id == requestId }
            }
        } catch {
            await MainActor.run {
                self.lastError = error.localizedDescription
            }
        }
    }
}
