//
//  KeychainManager.swift
//  AICLICompanionHost
//
//  Manages secure storage of authentication tokens in the macOS Keychain
//

import Foundation
import Security
import LocalAuthentication

class KeychainManager {
    static let shared = KeychainManager()

    private let service = "com.aicli.companion.host"
    private let authTokenKey = "auth_token"

    private init() {}

    // MARK: - Public Methods
    func saveAuthToken(_ token: String) {
        let data = token.data(using: .utf8)!

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: authTokenKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        // Delete existing item first
        SecItemDelete(query as CFDictionary)

        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)

        if status != errSecSuccess {
            print("Failed to save auth token to keychain: \(status)")
        }
    }

    func loadAuthToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: authTokenKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }

        return token
    }

    func deleteAuthToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: authTokenKey
        ]

        let status = SecItemDelete(query as CFDictionary)

        if status != errSecSuccess && status != errSecItemNotFound {
            print("Failed to delete auth token from keychain: \(status)")
        }
    }

    func authenticateWithTouchID(reason: String) async -> Bool {
        guard await SettingsManager.shared.enableTouchID else {
            return true // Skip Touch ID if disabled
        }

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
}
