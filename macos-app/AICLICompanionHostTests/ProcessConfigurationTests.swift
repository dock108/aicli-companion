//
//  ProcessConfigurationTests.swift
//  AICLICompanionHostTests
//
//  Tests for ProcessConfiguration extension of ServerManager
//

import XCTest
@testable import AICLICompanionHost

@MainActor
final class ProcessConfigurationTests: XCTestCase {

    var serverManager: ServerManager!
    var originalSettings: [String: Any] = [:]

    override func setUp() async throws {
        try await super.setUp()
        serverManager = ServerManager.shared

        // Store original settings
        originalSettings = [
            "requireAuthentication": SettingsManager.shared.requireAuthentication,
            "enableTunnel": SettingsManager.shared.enableTunnel,
            "tunnelProvider": SettingsManager.shared.tunnelProvider,
            "ngrokAuthToken": SettingsManager.shared.ngrokAuthToken,
            "defaultProjectDirectory": SettingsManager.shared.defaultProjectDirectory
        ]

        // Reset server manager state
        serverManager.authToken = nil
        serverManager.port = 3001
        serverManager.logs.removeAll()
    }

    override func tearDown() async throws {
        // Restore original settings
        SettingsManager.shared.requireAuthentication = originalSettings["requireAuthentication"] as? Bool ?? true
        SettingsManager.shared.enableTunnel = originalSettings["enableTunnel"] as? Bool ?? false
        SettingsManager.shared.tunnelProvider = originalSettings["tunnelProvider"] as? String ?? "ngrok"
        SettingsManager.shared.ngrokAuthToken = originalSettings["ngrokAuthToken"] as? String ?? ""
        SettingsManager.shared.defaultProjectDirectory = originalSettings["defaultProjectDirectory"] as? String ?? ""

        try await super.tearDown()
    }

    // MARK: - Environment Setup Tests

    func testBasicEnvironmentSetup() async throws {
        serverManager.port = 8080
        let environment = try await serverManager.setupServerEnvironment()

        XCTAssertEqual(environment["PORT"], "8080")
        XCTAssertEqual(environment["NODE_ENV"], "production")
        XCTAssertEqual(environment["APNS_PRODUCTION"], "false")
        XCTAssertNotNil(environment["PATH"])
    }

    func testPathIncludesStandardDirectories() async throws {
        let environment = try await serverManager.setupServerEnvironment()
        let path = environment["PATH"] ?? ""

        XCTAssertTrue(path.contains("/usr/local/bin"))
        XCTAssertTrue(path.contains("/usr/bin"))
        XCTAssertTrue(path.contains("/bin"))
        XCTAssertTrue(path.contains("/opt/homebrew/bin"))
    }

    func testConfigPathWithDefaultProjectDirectory() async throws {
        SettingsManager.shared.defaultProjectDirectory = "/Users/test/projects"

        let environment = try await serverManager.setupServerEnvironment()

        XCTAssertEqual(environment["CONFIG_PATH"], "/Users/test/projects")
    }

    func testConfigPathDefaultsToHomeDirectory() async throws {
        SettingsManager.shared.defaultProjectDirectory = ""

        let environment = try await serverManager.setupServerEnvironment()

        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertEqual(environment["CONFIG_PATH"], homePath)
    }

    // MARK: - Authentication Configuration Tests

    func testAuthenticationEnabled() async throws {
        SettingsManager.shared.requireAuthentication = true
        serverManager.authToken = nil

        let environment = try await serverManager.setupServerEnvironment()

        XCTAssertEqual(environment["AUTH_REQUIRED"], "true")
        XCTAssertNotNil(environment["AUTH_TOKEN"])
        XCTAssertNotNil(serverManager.authToken)

        // Token should be generated and stored
        let token = serverManager.authToken!
        XCTAssertFalse(token.isEmpty)
        XCTAssertEqual(token.count, 64) // 32 bytes hex encoded = 64 chars
    }

    func testAuthenticationDisabled() async throws {
        SettingsManager.shared.requireAuthentication = false
        serverManager.authToken = "existing-token"

        let environment = try await serverManager.setupServerEnvironment()

        XCTAssertEqual(environment["AUTH_REQUIRED"], "false")
        XCTAssertNil(environment["AUTH_TOKEN"])
        XCTAssertNil(serverManager.authToken) // Should be cleared
    }

    func testAuthenticationPreservesExistingToken() async throws {
        SettingsManager.shared.requireAuthentication = true
        let existingToken = "existing-secure-token-123"
        serverManager.authToken = existingToken

        let environment = try await serverManager.setupServerEnvironment()

        XCTAssertEqual(environment["AUTH_REQUIRED"], "true")
        XCTAssertEqual(environment["AUTH_TOKEN"], existingToken)
        XCTAssertEqual(serverManager.authToken, existingToken)
    }

    // MARK: - Tunnel Configuration Tests

    func testTunnelEnabledWithNgrok() async throws {
        SettingsManager.shared.enableTunnel = true
        SettingsManager.shared.tunnelProvider = "ngrok"
        SettingsManager.shared.ngrokAuthToken = "test-ngrok-token"

        let environment = try await serverManager.setupServerEnvironment()

        XCTAssertEqual(environment["ENABLE_TUNNEL"], "true")
        XCTAssertEqual(environment["TUNNEL_PROVIDER"], "ngrok")
        XCTAssertEqual(environment["NGROK_AUTH_TOKEN"], "test-ngrok-token")
    }

    func testTunnelEnabledWithoutToken() async throws {
        SettingsManager.shared.enableTunnel = true
        SettingsManager.shared.tunnelProvider = "ngrok"
        SettingsManager.shared.ngrokAuthToken = ""

        let environment = try await serverManager.setupServerEnvironment()

        XCTAssertEqual(environment["ENABLE_TUNNEL"], "true")
        XCTAssertEqual(environment["TUNNEL_PROVIDER"], "ngrok")
        XCTAssertNil(environment["NGROK_AUTH_TOKEN"])
    }

    func testTunnelDisabled() async throws {
        SettingsManager.shared.enableTunnel = false
        SettingsManager.shared.tunnelProvider = "ngrok"
        SettingsManager.shared.ngrokAuthToken = "token-that-shouldnt-be-used"

        let environment = try await serverManager.setupServerEnvironment()

        XCTAssertEqual(environment["ENABLE_TUNNEL"], "false")
        XCTAssertNil(environment["NGROK_AUTH_TOKEN"])
    }

    func testTunnelWithAlternativeProvider() async throws {
        SettingsManager.shared.enableTunnel = true
        SettingsManager.shared.tunnelProvider = "cloudflare"

        let environment = try await serverManager.setupServerEnvironment()

        XCTAssertEqual(environment["ENABLE_TUNNEL"], "true")
        XCTAssertEqual(environment["TUNNEL_PROVIDER"], "cloudflare")
        XCTAssertNil(environment["NGROK_AUTH_TOKEN"]) // Shouldn't set ngrok token for other providers
    }

    // MARK: - Port Configuration Tests

    func testPortConfiguration() async throws {
        let testPorts = [3001, 8080, 5000, 9999]

        for testPort in testPorts {
            serverManager.port = testPort
            let environment = try await serverManager.setupServerEnvironment()

            XCTAssertEqual(environment["PORT"], String(testPort))
        }
    }

    // MARK: - Logging Tests

    func testLoggingDuringSetup() async throws {
        serverManager.logs.removeAll()
        SettingsManager.shared.requireAuthentication = true
        SettingsManager.shared.enableTunnel = true
        SettingsManager.shared.tunnelProvider = "ngrok"
        SettingsManager.shared.ngrokAuthToken = "test-token"
        SettingsManager.shared.defaultProjectDirectory = "/test/path"

        _ = try await serverManager.setupServerEnvironment()

        // Check that appropriate logs were created
        XCTAssertTrue(serverManager.logs.contains { $0.message.contains("CONFIG_PATH") })
        XCTAssertTrue(serverManager.logs.contains { $0.message.contains("Authentication enabled") })
        XCTAssertTrue(serverManager.logs.contains { $0.message.contains("Tunnel enabled") })
    }

    // MARK: - Complex Configuration Tests

    func testFullConfigurationWithAllFeatures() async throws {
        // Setup all features
        serverManager.port = 4567
        SettingsManager.shared.requireAuthentication = true
        SettingsManager.shared.enableTunnel = true
        SettingsManager.shared.tunnelProvider = "ngrok"
        SettingsManager.shared.ngrokAuthToken = "full-test-token"
        SettingsManager.shared.defaultProjectDirectory = "/Users/test/full-project"

        let environment = try await serverManager.setupServerEnvironment()

        // Verify all settings are present
        XCTAssertEqual(environment["PORT"], "4567")
        XCTAssertEqual(environment["NODE_ENV"], "production")
        XCTAssertEqual(environment["APNS_PRODUCTION"], "false")
        XCTAssertEqual(environment["CONFIG_PATH"], "/Users/test/full-project")
        XCTAssertEqual(environment["AUTH_REQUIRED"], "true")
        XCTAssertNotNil(environment["AUTH_TOKEN"])
        XCTAssertEqual(environment["ENABLE_TUNNEL"], "true")
        XCTAssertEqual(environment["TUNNEL_PROVIDER"], "ngrok")
        XCTAssertEqual(environment["NGROK_AUTH_TOKEN"], "full-test-token")
        XCTAssertNotNil(environment["PATH"])
    }

    func testMinimalConfiguration() async throws {
        // Disable all optional features
        SettingsManager.shared.requireAuthentication = false
        SettingsManager.shared.enableTunnel = false
        SettingsManager.shared.defaultProjectDirectory = ""

        let environment = try await serverManager.setupServerEnvironment()

        // Verify minimal setup
        XCTAssertEqual(environment["AUTH_REQUIRED"], "false")
        XCTAssertEqual(environment["ENABLE_TUNNEL"], "false")
        XCTAssertNil(environment["AUTH_TOKEN"])
        XCTAssertNil(environment["NGROK_AUTH_TOKEN"])

        // But essential vars should still be present
        XCTAssertNotNil(environment["PORT"])
        XCTAssertNotNil(environment["NODE_ENV"])
        XCTAssertNotNil(environment["CONFIG_PATH"])
        XCTAssertNotNil(environment["PATH"])
    }
}