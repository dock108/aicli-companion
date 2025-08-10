//
//  MockKeychainManager.swift
//  AICLICompanionHostTests
//
//  Mock keychain manager for unit testing without actual keychain access
//

import Foundation
@testable import AICLICompanionHost

class MockKeychainManager {
    // MARK: - In-Memory Storage
    private var storage: [String: String] = [:]
    
    // MARK: - Test Tracking Properties
    var saveAuthTokenCalled = false
    var saveAuthTokenCallCount = 0
    var loadAuthTokenCalled = false
    var loadAuthTokenCallCount = 0
    var deleteAuthTokenCalled = false
    var deleteAuthTokenCallCount = 0
    
    // Test control properties
    var loadAuthTokenShouldReturnNil = false
    var saveAuthTokenShouldFail = false
    
    // MARK: - Singleton (for testing consistency)
    static let shared = MockKeychainManager()
    
    // MARK: - Public Methods
    
    func saveAuthToken(_ token: String) -> Bool {
        saveAuthTokenCalled = true
        saveAuthTokenCallCount += 1
        
        if saveAuthTokenShouldFail {
            return false
        }
        
        storage["authToken"] = token
        return true
    }
    
    func loadAuthToken() -> String? {
        loadAuthTokenCalled = true
        loadAuthTokenCallCount += 1
        
        if loadAuthTokenShouldReturnNil {
            return nil
        }
        
        return storage["authToken"]
    }
    
    func deleteAuthToken() -> Bool {
        deleteAuthTokenCalled = true
        deleteAuthTokenCallCount += 1
        
        storage.removeValue(forKey: "authToken")
        return true
    }
    
    // MARK: - Additional Keychain Methods (if needed)
    
    func save(key: String, value: String) -> Bool {
        storage[key] = value
        return true
    }
    
    func load(key: String) -> String? {
        return storage[key]
    }
    
    func delete(key: String) -> Bool {
        storage.removeValue(forKey: key)
        return true
    }
    
    // MARK: - Test Helpers
    
    func reset() {
        storage.removeAll()
        
        saveAuthTokenCalled = false
        saveAuthTokenCallCount = 0
        loadAuthTokenCalled = false
        loadAuthTokenCallCount = 0
        deleteAuthTokenCalled = false
        deleteAuthTokenCallCount = 0
        
        loadAuthTokenShouldReturnNil = false
        saveAuthTokenShouldFail = false
    }
    
    func setAuthToken(_ token: String) {
        storage["authToken"] = token
    }
    
    func getAllStoredData() -> [String: String] {
        return storage
    }
}