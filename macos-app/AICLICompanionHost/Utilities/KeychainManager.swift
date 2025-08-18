import Foundation
import Security

/// Keychain manager for secure storage of sensitive data
/// This is a copy for the macOS app until we properly integrate the shared package
public class KeychainManager {
    static let shared = KeychainManager()

    private let service = "com.aicli.companion.host"
    private let accessGroup: String? = nil // macOS doesn't use access groups the same way

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
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

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

    /// Save ngrok auth token
    public func saveNgrokToken(_ token: String) -> Bool {
        return save(token, for: "ngrokAuthToken")
    }

    /// Retrieve ngrok auth token
    public func getNgrokToken() -> String? {
        return retrieveString(for: "ngrokAuthToken")
    }

    /// Delete ngrok auth token
    @discardableResult
    public func deleteNgrokToken() -> Bool {
        return delete(for: "ngrokAuthToken")
    }
}
