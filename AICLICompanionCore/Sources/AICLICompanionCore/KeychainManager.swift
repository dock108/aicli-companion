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
    private let authTokenKey = "authToken" // Updated to match iOS/macOS versions
    private let serverURLKey = "serverURL"
    private let ngrokTokenKey = "ngrokAuthToken"

    // MARK: - Initialization
    private init() {
        // Use consistent service names across platforms
        #if os(iOS)
        self.serviceName = "com.aicli.companion"
        #else
        self.serviceName = "com.aicli.companion.host"
        #endif
    }

    // MARK: - Custom Initialization (for testing or specific configurations)
    public init(serviceName: String) {
        self.serviceName = serviceName
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
        #if os(iOS)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        #else
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
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

    @discardableResult
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

    @discardableResult
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

    // MARK: - Data Operations (matching iOS/macOS interface)

    public func save(_ data: Data, for key: String) -> Bool {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        // Add platform-specific accessibility
        #if os(iOS)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        #else
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
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

    public func save(_ string: String, for key: String) -> Bool {
        guard let data = string.data(using: .utf8) else { return false }
        return save(data, for: key)
    }

    public func retrieve(for key: String) -> Data? {
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
              let data = result as? Data else {
            return nil
        }

        return data
    }

    public func retrieveString(for key: String) -> String? {
        guard let data = retrieve(for: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func exists(for key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    // MARK: - Auth Token Convenience Methods

    public func saveAuthToken(_ token: String) -> Bool {
        return save(token, for: authTokenKey)
    }

    public func getAuthToken() -> String? {
        return retrieveString(for: authTokenKey)
    }

    public func loadAuthToken() -> String? {
        return getAuthToken() // Alias for backward compatibility
    }

    @discardableResult
    public func deleteAuthToken() -> Bool {
        return delete(forKey: authTokenKey)
    }

    // MARK: - Server URL Convenience Methods

    public func saveServerURL(_ url: String) -> Bool {
        return save(url, for: serverURLKey)
    }

    public func getServerURL() -> String? {
        return retrieveString(for: serverURLKey)
    }

    // MARK: - Ngrok Token Convenience Methods (primarily for macOS)

    public func saveNgrokToken(_ token: String) -> Bool {
        return save(token, for: ngrokTokenKey)
    }

    public func getNgrokToken() -> String? {
        return retrieveString(for: ngrokTokenKey)
    }

    @discardableResult
    public func deleteNgrokToken() -> Bool {
        return delete(forKey: ngrokTokenKey)
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
