import Foundation
import Security
#if os(macOS)
import LocalAuthentication
#endif

/// Unified KeychainManager for both iOS and macOS platforms
public class KeychainManager {
    // MARK: - Singleton
    public static let shared = KeychainManager()
    
    // MARK: - Properties
    private let serviceName: String
    private let authTokenKey = "auth_token"
    
    // MARK: - Initialization
    private init() {
        #if os(iOS)
        self.serviceName = "AICLICompanion"
        #else
        self.serviceName = "com.aicli.companion.host"
        #endif
    }
    
    // MARK: - Generic Keychain Operations
    
    public func save(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        // Add platform-specific accessibility
        #if os(macOS)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        #endif
        
        // Delete existing item first
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status != errSecSuccess {
            print("Keychain save failed for key '\(key)' with status: \(status)")
            return false
        }
        
        return true
    }
    
    public func load(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return string
    }
    
    public func delete(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        if status != errSecSuccess && status != errSecItemNotFound {
            print("Keychain delete failed for key '\(key)' with status: \(status)")
            return false
        }
        
        return true
    }
    
    public func deleteAll() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        if status != errSecSuccess && status != errSecItemNotFound {
            print("Keychain deleteAll failed with status: \(status)")
            return false
        }
        
        return true
    }
    
    public func exists(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    // MARK: - Auth Token Convenience Methods
    
    public func saveAuthToken(_ token: String) -> Bool {
        return save(token, forKey: authTokenKey)
    }
    
    public func loadAuthToken() -> String? {
        return load(forKey: authTokenKey)
    }
    
    public func deleteAuthToken() -> Bool {
        return delete(forKey: authTokenKey)
    }
    
    // MARK: - Platform-Specific Features
    
    #if os(macOS)
    public func authenticateWithTouchID(reason: String) async -> Bool {
        // Note: SettingsManager dependency needs to be injected or handled differently
        // For now, we'll check if Touch ID is available
        
        let context = LAContext()
        var error: NSError?
        
        // Check if Touch ID is available
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            print("Touch ID not available: \(error?.localizedDescription ?? "Unknown error")")
            return true // Fall back to no authentication
        }
        
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            return success
        } catch {
            print("Touch ID authentication failed: \(error.localizedDescription)")
            return false
        }
    }
    #endif
}