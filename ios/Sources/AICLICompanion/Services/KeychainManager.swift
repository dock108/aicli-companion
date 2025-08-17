import Foundation
import Security

/// Keychain manager for secure storage of sensitive data
@available(iOS 16.0, *)
public class KeychainManager {
    static let shared = KeychainManager()
    
    private let service = "com.aicli.companion"
    private let accessGroup: String? = nil // Can be configured for app groups if needed
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Save data to keychain
    public func save(_ data: Data, for key: String) -> Bool {
        delete(for: key) // Delete any existing item first
        
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    /// Save string to keychain
    public func save(_ string: String, for key: String) -> Bool {
        guard let data = string.data(using: .utf8) else { return false }
        return save(data, for: key)
    }
    
    /// Retrieve data from keychain
    public func retrieve(for key: String) -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        
        return data
    }
    
    /// Retrieve string from keychain
    public func retrieveString(for key: String) -> String? {
        guard let data = retrieve(for: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    /// Delete item from keychain
    @discardableResult
    public func delete(for key: String) -> Bool {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    /// Delete all items from keychain
    @discardableResult
    public func deleteAll() -> Bool {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    /// Check if a key exists in keychain
    public func exists(for key: String) -> Bool {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    // MARK: - Convenience Methods
    
    /// Save authentication token
    public func saveAuthToken(_ token: String) -> Bool {
        return save(token, for: "authToken")
    }
    
    /// Retrieve authentication token
    public func getAuthToken() -> String? {
        return retrieveString(for: "authToken")
    }
    
    /// Delete authentication token
    @discardableResult
    public func deleteAuthToken() -> Bool {
        return delete(for: "authToken")
    }
    
    /// Save server URL
    public func saveServerURL(_ url: String) -> Bool {
        return save(url, for: "serverURL")
    }
    
    /// Retrieve server URL
    public func getServerURL() -> String? {
        return retrieveString(for: "serverURL")
    }
}