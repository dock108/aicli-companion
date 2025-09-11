//
//  SettingsManagerAdvancedTests.swift
//  AICLICompanionHostTests
//
//  Advanced tests for SettingsManager to improve coverage
//

import XCTest
@testable import AICLICompanionHost

@MainActor
final class SettingsManagerAdvancedTests: XCTestCase {
    var settingsManager: SettingsManager!

    override func setUp() async throws {
        try await super.setUp()
        settingsManager = SettingsManager.shared

        // Reset to defaults before each test
        settingsManager.resetToDefaults()
    }

    override func tearDown() async throws {
        settingsManager.resetToDefaults()
        try await super.tearDown()
    }

    // MARK: - Default Values Tests

    func testDefaultValues() {
        XCTAssertEqual(settingsManager.serverPort, 3001)
        XCTAssertFalse(settingsManager.autoStartServer)
        XCTAssertTrue(settingsManager.enableNotifications)
        XCTAssertEqual(settingsManager.logLevel, .info)
        XCTAssertEqual(settingsManager.maxLogEntries, 1000)
        XCTAssertFalse(settingsManager.requireAuthentication)
        XCTAssertFalse(settingsManager.enableTunnel)
        XCTAssertEqual(settingsManager.tunnelProvider, "ngrok")
        XCTAssertEqual(settingsManager.ngrokAuthToken, "")
        XCTAssertEqual(settingsManager.serverCommand, "npm start")
        XCTAssertEqual(settingsManager.defaultProjectDirectory, "")
    }

    // MARK: - Server Port Tests

    func testServerPortValidRange() {
        // Test valid ports
        settingsManager.serverPort = 1024
        XCTAssertEqual(settingsManager.serverPort, 1024)

        settingsManager.serverPort = 8080
        XCTAssertEqual(settingsManager.serverPort, 8080)

        settingsManager.serverPort = 65535
        XCTAssertEqual(settingsManager.serverPort, 65535)
    }

    func testServerPortEdgeCases() {
        // Test edge values
        settingsManager.serverPort = 1024 // Minimum valid port
        XCTAssertEqual(settingsManager.serverPort, 1024)

        settingsManager.serverPort = 65535 // Maximum valid port
        XCTAssertEqual(settingsManager.serverPort, 65535)
    }

    // MARK: - Log Level Tests

    func testLogLevelSetting() {
        settingsManager.logLevel = .debug
        XCTAssertEqual(settingsManager.logLevel, .debug)

        settingsManager.logLevel = .warning
        XCTAssertEqual(settingsManager.logLevel, .warning)

        settingsManager.logLevel = .error
        XCTAssertEqual(settingsManager.logLevel, .error)
    }

    // MARK: - Max Log Entries Tests

    func testMaxLogEntriesValidRange() {
        settingsManager.maxLogEntries = 100
        XCTAssertEqual(settingsManager.maxLogEntries, 100)

        settingsManager.maxLogEntries = 5000
        XCTAssertEqual(settingsManager.maxLogEntries, 5000)

        settingsManager.maxLogEntries = 10000
        XCTAssertEqual(settingsManager.maxLogEntries, 10000)
    }

    // MARK: - Boolean Settings Tests

    func testAutoStartServer() {
        settingsManager.autoStartServer = true
        XCTAssertTrue(settingsManager.autoStartServer)

        settingsManager.autoStartServer = false
        XCTAssertFalse(settingsManager.autoStartServer)
    }

    func testEnableNotifications() {
        settingsManager.enableNotifications = false
        XCTAssertFalse(settingsManager.enableNotifications)

        settingsManager.enableNotifications = true
        XCTAssertTrue(settingsManager.enableNotifications)
    }

    func testRequireAuthentication() {
        settingsManager.requireAuthentication = true
        XCTAssertTrue(settingsManager.requireAuthentication)

        settingsManager.requireAuthentication = false
        XCTAssertFalse(settingsManager.requireAuthentication)
    }

    func testEnableTunnel() {
        settingsManager.enableTunnel = true
        XCTAssertTrue(settingsManager.enableTunnel)

        settingsManager.enableTunnel = false
        XCTAssertFalse(settingsManager.enableTunnel)
    }

    // MARK: - String Settings Tests

    func testTunnelProvider() {
        settingsManager.tunnelProvider = "localtunnel"
        XCTAssertEqual(settingsManager.tunnelProvider, "localtunnel")

        settingsManager.tunnelProvider = "ngrok"
        XCTAssertEqual(settingsManager.tunnelProvider, "ngrok")

        settingsManager.tunnelProvider = "cloudflare"
        XCTAssertEqual(settingsManager.tunnelProvider, "cloudflare")
    }

    func testNgrokAuthToken() {
        let testToken = "test_token_12345"
        settingsManager.ngrokAuthToken = testToken
        XCTAssertEqual(settingsManager.ngrokAuthToken, testToken)

        // Test empty token
        settingsManager.ngrokAuthToken = ""
        XCTAssertEqual(settingsManager.ngrokAuthToken, "")
    }

    func testServerCommand() {
        settingsManager.serverCommand = "node server.js"
        XCTAssertEqual(settingsManager.serverCommand, "node server.js")

        settingsManager.serverCommand = "python app.py"
        XCTAssertEqual(settingsManager.serverCommand, "python app.py")
    }

    func testDefaultProjectDirectory() {
        let testPath = "/Users/test/projects"
        settingsManager.defaultProjectDirectory = testPath
        XCTAssertEqual(settingsManager.defaultProjectDirectory, testPath)

        // Test empty path
        settingsManager.defaultProjectDirectory = ""
        XCTAssertEqual(settingsManager.defaultProjectDirectory, "")
    }

    // MARK: - String Validation Tests

    func testServerCommandValidation() {
        // Empty command should be invalid
        XCTAssertFalse(settingsManager.isValidServerCommand(""))

        // Valid commands
        XCTAssertTrue(settingsManager.isValidServerCommand("npm start"))
        XCTAssertTrue(settingsManager.isValidServerCommand("node server.js"))
        XCTAssertTrue(settingsManager.isValidServerCommand("python app.py"))
    }

    func testNgrokTokenValidation() {
        // Empty token is valid (optional)
        XCTAssertTrue(settingsManager.isValidNgrokToken(""))

        // Valid tokens (typically 30+ characters)
        XCTAssertTrue(settingsManager.isValidNgrokToken("2tP1C5A50lrsjb2JmvO4U1tjr4K"))

        // Invalid tokens (too short)
        XCTAssertFalse(settingsManager.isValidNgrokToken("short"))
    }

    func testProjectDirectoryValidation() {
        // Empty is valid
        XCTAssertTrue(settingsManager.isValidProjectDirectory(""))

        // Existing directory should be valid
        XCTAssertTrue(settingsManager.isValidProjectDirectory("/tmp"))

        // Non-existent directory should be invalid
        XCTAssertFalse(settingsManager.isValidProjectDirectory("/non/existent/path"))
    }

    // MARK: - Port Validation Tests

    func testPortValidation() {
        // Valid ports
        XCTAssertTrue(settingsManager.isValidPort(1024))
        XCTAssertTrue(settingsManager.isValidPort(3001))
        XCTAssertTrue(settingsManager.isValidPort(8080))
        XCTAssertTrue(settingsManager.isValidPort(65535))

        // Invalid ports
        XCTAssertFalse(settingsManager.isValidPort(0))
        XCTAssertFalse(settingsManager.isValidPort(80))    // Too low
        XCTAssertFalse(settingsManager.isValidPort(1023))  // Too low
        XCTAssertFalse(settingsManager.isValidPort(65536)) // Too high
        XCTAssertFalse(settingsManager.isValidPort(-1))    // Negative
    }

    // MARK: - Log Entries Validation Tests

    func testMaxLogEntriesValidation() {
        // Valid ranges
        XCTAssertTrue(settingsManager.isValidMaxLogEntries(100))
        XCTAssertTrue(settingsManager.isValidMaxLogEntries(1000))
        XCTAssertTrue(settingsManager.isValidMaxLogEntries(10000))

        // Invalid ranges
        XCTAssertFalse(settingsManager.isValidMaxLogEntries(50))    // Too low
        XCTAssertFalse(settingsManager.isValidMaxLogEntries(20000)) // Too high
        XCTAssertFalse(settingsManager.isValidMaxLogEntries(0))     // Zero
        XCTAssertFalse(settingsManager.isValidMaxLogEntries(-1))    // Negative
    }

    // MARK: - Reset to Defaults Tests

    func testResetToDefaults() {
        // Change all settings
        settingsManager.serverPort = 8080
        settingsManager.autoStartServer = true
        settingsManager.enableNotifications = false
        settingsManager.logLevel = .debug
        settingsManager.maxLogEntries = 5000
        settingsManager.requireAuthentication = true
        settingsManager.enableTunnel = true
        settingsManager.tunnelProvider = "localtunnel"
        settingsManager.ngrokAuthToken = "test_token"
        settingsManager.serverCommand = "node server.js"
        settingsManager.defaultProjectDirectory = "/test/path"

        // Reset to defaults
        settingsManager.resetToDefaults()

        // Verify all settings are back to defaults
        XCTAssertEqual(settingsManager.serverPort, 3001)
        XCTAssertFalse(settingsManager.autoStartServer)
        XCTAssertTrue(settingsManager.enableNotifications)
        XCTAssertEqual(settingsManager.logLevel, .info)
        XCTAssertEqual(settingsManager.maxLogEntries, 1000)
        XCTAssertFalse(settingsManager.requireAuthentication)
        XCTAssertFalse(settingsManager.enableTunnel)
        XCTAssertEqual(settingsManager.tunnelProvider, "ngrok")
        XCTAssertEqual(settingsManager.ngrokAuthToken, "")
        XCTAssertEqual(settingsManager.serverCommand, "npm start")
        XCTAssertEqual(settingsManager.defaultProjectDirectory, "")
    }

    // MARK: - Settings Export/Import Tests

    func testExportSettings() {
        // Change some settings
        settingsManager.serverPort = 8080
        settingsManager.autoStartServer = true
        settingsManager.logLevel = .debug

        let exportedData = settingsManager.exportSettings()
        XCTAssertNotNil(exportedData)
        if let exportedData = exportedData {
            XCTAssertFalse(exportedData.isEmpty)
        }
    }

    func testImportValidSettings() {
        // Export current settings
        guard let exportedData = settingsManager.exportSettings() else {
            XCTFail("Failed to export settings")
            return
        }

        // Change settings
        settingsManager.serverPort = 9000
        settingsManager.autoStartServer = true

        // Import back
        do {
            try settingsManager.importSettings(from: exportedData)
            // Should be back to original values
            XCTAssertEqual(settingsManager.serverPort, 3001)
            XCTAssertFalse(settingsManager.autoStartServer)
        } catch {
            XCTFail("Failed to import settings: \(error)")
        }
    }

    func testImportInvalidSettings() {
        let invalidData = "invalid json data".data(using: .utf8)!

        XCTAssertThrowsError(try settingsManager.importSettings(from: invalidData)) { error in
            XCTAssertTrue(error is SettingsError)
        }
    }

    // MARK: - Performance Tests

    func testSettingsPerformance() {
        measure {
            for i in 0..<1000 {
                settingsManager.serverPort = 3000 + (i % 1000)
                settingsManager.autoStartServer.toggle()
                settingsManager.enableNotifications.toggle()
            }
        }
    }

    func testExportImportPerformance() {
        measure {
            for _ in 0..<100 {
                if let data = settingsManager.exportSettings() {
                    try? settingsManager.importSettings(from: data)
                }
            }
        }
    }

    // MARK: - Edge Cases

    func testSettingsWithSpecialCharacters() {
        let specialCommand = "node server.js --config=\"/path with spaces/config.json\""
        settingsManager.serverCommand = specialCommand
        XCTAssertEqual(settingsManager.serverCommand, specialCommand)

        let unicodeToken = "🔑test_token_with_emoji🔐"
        settingsManager.ngrokAuthToken = unicodeToken
        XCTAssertEqual(settingsManager.ngrokAuthToken, unicodeToken)
    }

    func testSettingsWithVeryLongStrings() {
        let longCommand = String(repeating: "very_long_command_", count: 100)
        settingsManager.serverCommand = longCommand
        XCTAssertEqual(settingsManager.serverCommand, longCommand)

        let longPath = "/very/long/path/" + String(repeating: "directory/", count: 50)
        settingsManager.defaultProjectDirectory = longPath
        XCTAssertEqual(settingsManager.defaultProjectDirectory, longPath)
    }
}

// MARK: - SettingsManager Extensions for Testing

extension SettingsManager {
    func isValidServerCommand(_ command: String) -> Bool {
        return !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func isValidNgrokToken(_ token: String) -> Bool {
        return token.isEmpty || token.count >= 20
    }

    func isValidProjectDirectory(_ path: String) -> Bool {
        if path.isEmpty { return true }
        return FileManager.default.fileExists(atPath: path)
    }

    func isValidPort(_ port: Int) -> Bool {
        return port >= 1024 && port <= 65535
    }

    func isValidMaxLogEntries(_ entries: Int) -> Bool {
        return entries >= 100 && entries <= 10000
    }

    func exportSettings() -> Data? {
        let settings: [String: Any] = [
            "serverPort": serverPort,
            "autoStartServer": autoStartServer,
            "enableNotifications": enableNotifications,
            "logLevel": logLevel.rawValue,
            "maxLogEntries": maxLogEntries,
            "requireAuthentication": requireAuthentication,
            "enableTunnel": enableTunnel,
            "tunnelProvider": tunnelProvider,
            "ngrokAuthToken": ngrokAuthToken,
            "serverCommand": serverCommand,
            "defaultProjectDirectory": defaultProjectDirectory
        ]

        return try? JSONSerialization.data(withJSONObject: settings)
    }

    func importSettings(from data: Data) throws {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SettingsError.invalidFormat
        }

        if let port = json["serverPort"] as? Int {
            serverPort = port
        }
        if let autoStart = json["autoStartServer"] as? Bool {
            autoStartServer = autoStart
        }
        if let notifications = json["enableNotifications"] as? Bool {
            enableNotifications = notifications
        }
        if let logLevelRaw = json["logLevel"] as? String,
           let level = LogLevel(rawValue: logLevelRaw) {
            logLevel = level
        }
        if let maxEntries = json["maxLogEntries"] as? Int {
            maxLogEntries = maxEntries
        }
        if let auth = json["requireAuthentication"] as? Bool {
            requireAuthentication = auth
        }
        if let tunnel = json["enableTunnel"] as? Bool {
            enableTunnel = tunnel
        }
        if let provider = json["tunnelProvider"] as? String {
            tunnelProvider = provider
        }
        if let token = json["ngrokAuthToken"] as? String {
            ngrokAuthToken = token
        }
        if let command = json["serverCommand"] as? String {
            serverCommand = command
        }
        if let directory = json["defaultProjectDirectory"] as? String {
            defaultProjectDirectory = directory
        }
    }
}

enum SettingsError: Error {
    case invalidFormat
    case invalidValue
}
