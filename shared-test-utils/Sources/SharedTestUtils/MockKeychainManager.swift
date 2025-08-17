import Foundation

/// Unified mock implementation of KeychainManager for testing
public class MockKeychainManager {
    
    // MARK: - Mock Storage
    private var mockStorage: [String: String] = [:]
    
    // MARK: - Mock Control Properties
    public var shouldFailOperations = false
    public var operationDelay: TimeInterval = 0.0
    public var recordedOperations: [String] = []
    
    // MARK: - Call Tracking
    public var saveCallCount = 0
    public var loadCallCount = 0
    public var deleteCallCount = 0
    public var deleteAllCallCount = 0
    
    // MARK: - Initialization
    public init() {}
    
    // MARK: - Static Shared Instance (for compatibility)
    public static let shared = MockKeychainManager()
    
    // MARK: - Generic Keychain Operations
    
    public func save(_ value: String, forKey key: String) -> Bool {
        recordOperation("save for key: \(key)")
        saveCallCount += 1
        
        if shouldFailOperations {
            return false
        }
        
        if operationDelay > 0 {
            Thread.sleep(forTimeInterval: operationDelay)
        }
        
        mockStorage[key] = value
        return true
    }
    
    public func load(forKey key: String) -> String? {
        recordOperation("load for key: \(key)")
        loadCallCount += 1
        
        if shouldFailOperations {
            return nil
        }
        
        if operationDelay > 0 {
            Thread.sleep(forTimeInterval: operationDelay)
        }
        
        return mockStorage[key]
    }
    
    public func delete(forKey key: String) -> Bool {
        recordOperation("delete for key: \(key)")
        deleteCallCount += 1
        
        if shouldFailOperations {
            return false
        }
        
        if operationDelay > 0 {
            Thread.sleep(forTimeInterval: operationDelay)
        }
        
        mockStorage.removeValue(forKey: key)
        return true
    }
    
    public func deleteAll() -> Bool {
        recordOperation("deleteAll")
        deleteAllCallCount += 1
        
        if shouldFailOperations {
            return false
        }
        
        if operationDelay > 0 {
            Thread.sleep(forTimeInterval: operationDelay)
        }
        
        mockStorage.removeAll()
        return true
    }
    
    // MARK: - Convenience Methods for Common Keys
    
    public func saveAuthToken(_ token: String) -> Bool {
        return save(token, forKey: "authToken")
    }
    
    public func loadAuthToken() -> String? {
        return load(forKey: "authToken")
    }
    
    public func deleteAuthToken() -> Bool {
        return delete(forKey: "authToken")
    }
    
    // MARK: - Test Helpers
    
    public func reset() {
        mockStorage.removeAll()
        recordedOperations.removeAll()
        shouldFailOperations = false
        operationDelay = 0.0
        saveCallCount = 0
        loadCallCount = 0
        deleteCallCount = 0
        deleteAllCallCount = 0
    }
    
    public func preloadData(_ data: [String: String]) {
        mockStorage = data
    }
    
    public func getAllKeys() -> Set<String> {
        return Set(mockStorage.keys)
    }
    
    public func contains(key: String) -> Bool {
        return mockStorage[key] != nil
    }
    
    // MARK: - Private Helpers
    
    private func recordOperation(_ operation: String) {
        recordedOperations.append(operation)
    }
}