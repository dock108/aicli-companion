//
//  MockKeychainManager.swift
//  AICLICompanionHostTests
//
//  Mock implementation of KeychainManager for testing
//

import Foundation
@testable import AICLICompanionHost

public class MockKeychainManager {
    // MARK: - Singleton
    public static let shared = MockKeychainManager()
    
    // MARK: - Test Tracking Properties
    public var storedItems: [String: Any] = [:]
    public var saveCallCount = 0
    public var loadCallCount = 0
    public var deleteCallCount = 0
    public var shouldThrowError = false
    public var errorToThrow: Error?
    
    // Auth token specific tracking
    public var saveAuthTokenCalled = false
    public var saveAuthTokenCallCount = 0
    public var loadAuthTokenCalled = false
    public var loadAuthTokenCallCount = 0
    public var deleteAuthTokenCalled = false
    public var deleteAuthTokenCallCount = 0
    
    // Server settings specific tracking
    public var saveServerSettingsCalled = false
    public var saveServerSettingsCallCount = 0
    public var loadServerSettingsCalled = false
    public var loadServerSettingsCallCount = 0
    
    // Mock Behavior Control
    public var dataToReturn: Data?
    public var stringToReturn: String?
    public var authTokenToReturn: String?
    public var serverSettingsToReturn: ServerSettings?
    public var saveAuthTokenShouldReturnFalse = false
    public var saveServerSettingsShouldReturnFalse = false
    
    public init() {
        // Reset state
        reset()
    }
    
    // MARK: - KeychainManager Protocol Methods
    
    public func save(_ data: Data, for key: String) throws {
        saveCallCount += 1
        
        if shouldThrowError {
            throw errorToThrow ?? KeychainError.unableToSave
        }
        
        storedItems[key] = data
    }
    
    public func save(_ string: String, for key: String) throws {
        saveCallCount += 1
        
        if shouldThrowError {
            throw errorToThrow ?? KeychainError.unableToSave
        }
        
        storedItems[key] = string
    }
    
    public func load(for key: String) throws -> Data {
        loadCallCount += 1
        
        if shouldThrowError {
            throw errorToThrow ?? KeychainError.itemNotFound
        }
        
        if let data = dataToReturn {
            return data
        }
        
        if let data = storedItems[key] as? Data {
            return data
        }
        
        if let string = storedItems[key] as? String {
            return Data(string.utf8)
        }
        
        throw KeychainError.itemNotFound
    }
    
    public func loadString(for key: String) throws -> String {
        loadCallCount += 1
        
        if shouldThrowError {
            throw errorToThrow ?? KeychainError.itemNotFound
        }
        
        if let string = stringToReturn {
            return string
        }
        
        if let string = storedItems[key] as? String {
            return string
        }
        
        if let data = storedItems[key] as? Data {
            return String(data: data, encoding: .utf8) ?? ""
        }
        
        throw KeychainError.itemNotFound
    }
    
    public func delete(for key: String) throws {
        deleteCallCount += 1
        
        if shouldThrowError {
            throw errorToThrow ?? KeychainError.unableToDelete
        }
        
        storedItems.removeValue(forKey: key)
    }
    
    public func exists(for key: String) -> Bool {
        return storedItems[key] != nil
    }
    
    // MARK: - Auth Token Methods
    
    public func saveAuthToken(_ token: String) -> Bool {
        saveAuthTokenCalled = true
        saveAuthTokenCallCount += 1
        
        if saveAuthTokenShouldReturnFalse || saveAuthTokenShouldFail {
            return false
        }
        
        storedItems["authToken"] = token
        return true
    }
    
    public func loadAuthToken() -> String? {
        loadAuthTokenCalled = true
        loadAuthTokenCallCount += 1
        
        if loadAuthTokenShouldReturnNil {
            return nil
        }
        
        if let token = authTokenToReturn {
            return token
        }
        
        return storedItems["authToken"] as? String
    }
    
    public func deleteAuthToken() -> Bool {
        deleteAuthTokenCalled = true
        deleteAuthTokenCallCount += 1
        
        storedItems.removeValue(forKey: "authToken")
        return true
    }
    
    public func getAuthToken() -> String? {
        return loadAuthToken()
    }
    
    // MARK: - Real KeychainManager API Methods
    
    public func retrieve(for key: String) -> Data? {
        loadCallCount += 1
        
        if let data = storedItems[key] as? Data {
            return data
        }
        
        if let string = storedItems[key] as? String {
            return string.data(using: .utf8)
        }
        
        return nil
    }
    
    public func retrieveString(for key: String) -> String? {
        loadCallCount += 1
        
        if let string = storedItems[key] as? String {
            return string
        }
        
        if let data = storedItems[key] as? Data {
            return String(data: data, encoding: .utf8)
        }
        
        return nil
    }
    
    @discardableResult
    public func deleteAll() -> Bool {
        deleteCallCount += 1
        storedItems.removeAll()
        return true
    }
    
    // Additional real API convenience methods
    public func saveServerURL(_ url: String) -> Bool {
        return save(key: "serverURL", value: url)
    }
    
    public func getServerURL() -> String? {
        return retrieveString(for: "serverURL")
    }
    
    public func saveNgrokToken(_ token: String) -> Bool {
        return save(key: "ngrokAuthToken", value: token)
    }
    
    public func getNgrokToken() -> String? {
        return retrieveString(for: "ngrokAuthToken")
    }
    
    @discardableResult
    public func deleteNgrokToken() -> Bool {
        return delete(key: "ngrokAuthToken")
    }
    
    // MARK: - Server Settings Methods
    
    public func saveServerSettings(_ settings: ServerSettings) -> Bool {
        saveServerSettingsCalled = true
        saveServerSettingsCallCount += 1
        
        if saveServerSettingsShouldReturnFalse {
            return false
        }
        
        // Encode and store settings
        if let data = try? JSONEncoder().encode(settings) {
            storedItems["serverSettings"] = data
            return true
        }
        return false
    }
    
    public func loadServerSettings() -> ServerSettings? {
        loadServerSettingsCalled = true
        loadServerSettingsCallCount += 1
        
        if let settings = serverSettingsToReturn {
            return settings
        }
        
        if let data = storedItems["serverSettings"] as? Data {
            return try? JSONDecoder().decode(ServerSettings.self, from: data)
        }
        
        return nil
    }
    
    // MARK: - Alternative API Methods (for backward compatibility)
    
    public func save(key: String, value: String) -> Bool {
        storedItems[key] = value
        saveCallCount += 1
        return !shouldThrowError
    }
    
    public func load(key: String) -> String? {
        loadCallCount += 1
        return storedItems[key] as? String
    }
    
    public func delete(key: String) -> Bool {
        deleteCallCount += 1
        storedItems.removeValue(forKey: key)
        return true
    }
    
    public func setAuthToken(_ token: String) {
        storedItems["authToken"] = token
    }
    
    public func getAllStoredData() -> [String: Any] {
        return storedItems
    }
    
    // Additional test control properties
    public var loadAuthTokenShouldReturnNil = false
    public var saveAuthTokenShouldFail = false
    
    // MARK: - Test Helper Methods
    
    public func reset() {
        storedItems.removeAll()
        saveCallCount = 0
        loadCallCount = 0
        deleteCallCount = 0
        shouldThrowError = false
        errorToThrow = nil
        dataToReturn = nil
        stringToReturn = nil
        authTokenToReturn = nil
        serverSettingsToReturn = nil
        saveAuthTokenShouldReturnFalse = false
        saveServerSettingsShouldReturnFalse = false
        
        // Reset auth token tracking
        saveAuthTokenCalled = false
        saveAuthTokenCallCount = 0
        loadAuthTokenCalled = false
        loadAuthTokenCallCount = 0
        deleteAuthTokenCalled = false
        deleteAuthTokenCallCount = 0
        
        // Reset server settings tracking
        saveServerSettingsCalled = false
        saveServerSettingsCallCount = 0
        loadServerSettingsCalled = false
        loadServerSettingsCallCount = 0
        
        // Reset additional test control flags
        loadAuthTokenShouldReturnNil = false
        saveAuthTokenShouldFail = false
    }
    
    public func preloadItem(_ value: Any, for key: String) {
        storedItems[key] = value
    }
}

// MARK: - Server Settings (for testing)

public struct ServerSettings: Codable {
    public var port: Int
    public var autoStart: Bool
    public var authToken: String?
    
    public init(port: Int = 3001, autoStart: Bool = false, authToken: String? = nil) {
        self.port = port
        self.autoStart = autoStart
        self.authToken = authToken
    }
}

// MARK: - Keychain Errors

public enum KeychainError: LocalizedError {
    case itemNotFound
    case unableToSave
    case unableToDelete
    case invalidData
    
    public var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "The requested item was not found in the keychain."
        case .unableToSave:
            return "Unable to save item to keychain."
        case .unableToDelete:
            return "Unable to delete item from keychain."
        case .invalidData:
            return "The data in the keychain is invalid."
        }
    }
}