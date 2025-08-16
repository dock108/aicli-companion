import Foundation
@testable import AICLICompanion

/// Mock implementation of KeychainManager for testing
class MockKeychainManager {
    
    // MARK: - Mock Storage
    private var mockStorage: [String: String] = [:]
    
    // MARK: - Mock Control
    var shouldFailOperations = false
    var operationDelay: TimeInterval = 0.0
    var recordedOperations: [String] = []
    
    // MARK: - Keychain Operations
    
    func save(_ value: String, forKey key: String) -> Bool {
        recordOperation("save for key: \(key)")
        
        if shouldFailOperations {
            return false
        }
        
        mockStorage[key] = value
        return true
    }
    
    func load(forKey key: String) -> String? {
        recordOperation("load for key: \(key)")
        
        if shouldFailOperations {
            return nil
        }
        
        return mockStorage[key]
    }
    
    func delete(forKey key: String) -> Bool {
        recordOperation("delete for key: \(key)")
        
        if shouldFailOperations {
            return false
        }
        
        mockStorage.removeValue(forKey: key)
        return true
    }
    
    func deleteAll() -> Bool {
        recordOperation("deleteAll")
        
        if shouldFailOperations {
            return false
        }
        
        mockStorage.removeAll()
        return true
    }
    
    func exists(forKey key: String) -> Bool {
        recordOperation("exists for key: \(key)")
        
        if shouldFailOperations {
            return false
        }
        
        return mockStorage[key] != nil
    }
    
    // MARK: - Server Connection Methods
    
    func saveServerConnection(_ connection: ServerConnection) -> Bool {
        recordOperation("saveServerConnection")
        
        if shouldFailOperations {
            return false
        }
        
        // Simulate encoding the connection
        mockStorage["server_address"] = connection.address
        mockStorage["server_port"] = String(connection.port)
        mockStorage["server_auth_token"] = connection.authToken
        mockStorage["server_is_secure"] = connection.isSecure ? "true" : "false"
        
        return true
    }
    
    func loadServerConnection() -> ServerConnection? {
        recordOperation("loadServerConnection")
        
        if shouldFailOperations {
            return nil
        }
        
        guard let address = mockStorage["server_address"],
              let portString = mockStorage["server_port"],
              let port = Int(portString) else {
            return nil
        }
        
        let authToken = mockStorage["server_auth_token"]
        let isSecure = mockStorage["server_is_secure"] == "true"
        
        return ServerConnection(
            address: address,
            port: port,
            authToken: authToken,
            isSecure: isSecure
        )
    }
    
    func deleteServerConnection() -> Bool {
        recordOperation("deleteServerConnection")
        
        if shouldFailOperations {
            return false
        }
        
        mockStorage.removeValue(forKey: "server_address")
        mockStorage.removeValue(forKey: "server_port")
        mockStorage.removeValue(forKey: "server_auth_token")
        mockStorage.removeValue(forKey: "server_is_secure")
        
        return true
    }
    
    // MARK: - Auth Token Methods
    
    func saveAuthToken(_ token: String) -> Bool {
        return save(token, forKey: "auth_token")
    }
    
    func loadAuthToken() -> String? {
        return load(forKey: "auth_token")
    }
    
    func deleteAuthToken() -> Bool {
        return delete(forKey: "auth_token")
    }
    
    // MARK: - Device Token Methods
    
    func saveDeviceToken(_ token: String) -> Bool {
        return save(token, forKey: "device_token")
    }
    
    func loadDeviceToken() -> String? {
        return load(forKey: "device_token")
    }
    
    func deleteDeviceToken() -> Bool {
        return delete(forKey: "device_token")
    }
    
    // MARK: - Session Methods
    
    func saveSessionId(_ sessionId: String, forProject project: String) -> Bool {
        return save(sessionId, forKey: "session_\(project)")
    }
    
    func loadSessionId(forProject project: String) -> String? {
        return load(forKey: "session_\(project)")
    }
    
    func deleteSessionId(forProject project: String) -> Bool {
        return delete(forKey: "session_\(project)")
    }
    
    // MARK: - Mock Helpers
    
    private func recordOperation(_ operation: String) {
        recordedOperations.append(operation)
    }
    
    func reset() {
        mockStorage.removeAll()
        shouldFailOperations = false
        operationDelay = 0.0
        recordedOperations.removeAll()
    }
    
    func simulateOperationFailure() {
        shouldFailOperations = true
    }
    
    func setMockValue(_ value: String, forKey key: String) {
        mockStorage[key] = value
    }
    
    func getMockValue(forKey key: String) -> String? {
        return mockStorage[key]
    }
    
    func getAllMockValues() -> [String: String] {
        return mockStorage
    }
    
    func getRecordedOperations() -> [String] {
        return recordedOperations
    }
    
    func clearRecordedOperations() {
        recordedOperations.removeAll()
    }
    
    func setOperationDelay(_ delay: TimeInterval) {
        operationDelay = delay
    }
}

// MARK: - Test Extensions

extension MockKeychainManager {
    
    func setupTestServerConnection() -> ServerConnection {
        let connection = TestDataFactory.createServerConnection(
            address: "localhost",
            port: 3000,
            authToken: "test-token-123"
        )
        
        _ = saveServerConnection(connection)
        return connection
    }
    
    func setupTestAuthToken() -> String {
        let token = "test-auth-token-456"
        _ = saveAuthToken(token)
        return token
    }
    
    func setupTestSession(project: String = "test-project") -> String {
        let sessionId = "test-session-789"
        _ = saveSessionId(sessionId, forProject: project)
        return sessionId
    }
}