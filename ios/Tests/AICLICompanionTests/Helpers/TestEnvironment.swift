import Foundation

/// Helper to detect test environment
struct TestEnvironment {
    /// Check if tests are running in CI environment
    static var isCI: Bool {
        // Check common CI environment variables
        if ProcessInfo.processInfo.environment["CI"] != nil {
            return true
        }
        if ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] != nil {
            return true
        }
        if ProcessInfo.processInfo.environment["JENKINS"] != nil {
            return true
        }
        if ProcessInfo.processInfo.environment["TRAVIS"] != nil {
            return true
        }
        if ProcessInfo.processInfo.environment["CIRCLECI"] != nil {
            return true
        }
        return false
    }
    
    /// Check if keychain access is available (not available in CI)
    static var hasKeychainAccess: Bool {
        // In CI, keychain access is restricted
        return !isCI
    }
    
    /// Check if we should skip timing-sensitive tests
    static var shouldSkipTimingSensitiveTests: Bool {
        return isCI
    }
    
    /// Check if we should skip concurrent tests that may be flaky in CI
    static var shouldSkipConcurrencyTests: Bool {
        return isCI
    }
}
