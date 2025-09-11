//
//  SettingsManagerProductionTests.swift
//  AICLICompanionHostTests
//
//  Tests for the actual SettingsManager implementation
//

import XCTest
import SwiftUI
import Combine
@testable import AICLICompanionHost

@MainActor
final class SettingsManagerProductionTests: XCTestCase {
    var settingsManager: SettingsManager!
    var cancellables: Set<AnyCancellable>!
    var originalValues: [String: Any] = [:]

    override func setUp() async throws {
        try await super.setUp()
        settingsManager = SettingsManager.shared
        cancellables = Set<AnyCancellable>()

        // Store original values to restore later
        originalValues = [
            "serverPort": settingsManager.serverPort,
            "autoStartServer": settingsManager.autoStartServer,
            "requireAuthentication": settingsManager.requireAuthentication,
            "enableTunnel": settingsManager.enableTunnel,
            "ngrokAuthToken": settingsManager.ngrokAuthToken,
            "logLevel": settingsManager.logLevel,
            "maxLogEntries": settingsManager.maxLogEntries
        ]
    }

    override func tearDown() async throws {
        // Restore original values
        settingsManager.serverPort = originalValues["serverPort"] as? Int ?? 3001
        settingsManager.autoStartServer = originalValues["autoStartServer"] as? Bool ?? false
        settingsManager.requireAuthentication = originalValues["requireAuthentication"] as? Bool ?? true
        settingsManager.enableTunnel = originalValues["enableTunnel"] as? Bool ?? false
        settingsManager.ngrokAuthToken = originalValues["ngrokAuthToken"] as? String ?? ""
        settingsManager.logLevel = originalValues["logLevel"] as? String ?? "info"
        settingsManager.maxLogEntries = originalValues["maxLogEntries"] as? Int ?? 1000

        cancellables.removeAll()
        try await super.tearDown()
    }

    // MARK: - Basic Settings Tests

    func testDefaultValues() {
        settingsManager.resetToDefaults()

        XCTAssertEqual(settingsManager.serverPort, 3001)
        XCTAssertFalse(settingsManager.autoStartServer)
        XCTAssertTrue(settingsManager.autoRestartOnCrash)
        XCTAssertFalse(settingsManager.launchAtLogin)
        XCTAssertFalse(settingsManager.showDockIcon)
        XCTAssertTrue(settingsManager.enableNotifications)
        XCTAssertTrue(settingsManager.enableSounds)
        XCTAssertEqual(settingsManager.logLevel, "info")
        XCTAssertEqual(settingsManager.maxLogEntries, 1000)
        XCTAssertTrue(settingsManager.enableBonjour)
        XCTAssertEqual(settingsManager.theme, "system")
    }

    func testServerPortUpdate() {
        settingsManager.serverPort = 8080
        XCTAssertEqual(settingsManager.serverPort, 8080)

        settingsManager.serverPort = 3000
        XCTAssertEqual(settingsManager.serverPort, 3000)
    }

    func testAutoStartServerToggle() {
        settingsManager.autoStartServer = true
        XCTAssertTrue(settingsManager.autoStartServer)

        settingsManager.autoStartServer = false
        XCTAssertFalse(settingsManager.autoStartServer)
    }

    // MARK: - Security Settings Tests

    func testSecuritySettings() {
        settingsManager.requireAuthentication = false
        XCTAssertFalse(settingsManager.requireAuthentication)

        settingsManager.requireAuthentication = true
        XCTAssertTrue(settingsManager.requireAuthentication)

        settingsManager.enableTouchID = false
        XCTAssertFalse(settingsManager.enableTouchID)

        settingsManager.enableTouchID = true
        XCTAssertTrue(settingsManager.enableTouchID)
    }

    // MARK: - Tunnel Settings Tests

    func testTunnelSettings() {
        settingsManager.enableTunnel = true
        XCTAssertTrue(settingsManager.enableTunnel)

        settingsManager.tunnelProvider = "cloudflare"
        XCTAssertEqual(settingsManager.tunnelProvider, "cloudflare")

        settingsManager.ngrokAuthToken = "test-token-123"
        XCTAssertEqual(settingsManager.ngrokAuthToken, "test-token-123")
    }

    // MARK: - Configuration Change Tracking Tests

    func testConfigurationChangeTracking() {
        // Reset configuration changed flag
        settingsManager.markConfigurationApplied()
        XCTAssertFalse(settingsManager.configurationChanged)

        // Change a setting that requires restart
        settingsManager.serverPort = 9999

        // Give time for change detection
        let expectation = XCTestExpectation(description: "Configuration change detected")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertTrue(self.settingsManager.configurationChanged)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testNeedsRestartWhenServerRunning() {
        // Setup: Server is running and configuration hasn't changed
        ServerManager.shared.isRunning = true
        settingsManager.markConfigurationApplied()
        XCTAssertFalse(settingsManager.needsRestart)

        // Change configuration
        settingsManager.serverPort = 5555

        // Give time for change detection
        let expectation = XCTestExpectation(description: "Needs restart detected")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertTrue(self.settingsManager.needsRestart)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        // Cleanup
        ServerManager.shared.isRunning = false
    }

    func testNeedsRestartWhenServerNotRunning() {
        // Setup: Server is not running
        ServerManager.shared.isRunning = false
        settingsManager.markConfigurationApplied()

        // Change configuration
        settingsManager.serverPort = 7777

        // Even with configuration changed, shouldn't need restart if server isn't running
        let expectation = XCTestExpectation(description: "Check needs restart")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertFalse(self.settingsManager.needsRestart)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Port Settings Tests

    func testPortBoundaryValues() {
        // Test minimum valid port
        settingsManager.serverPort = 1024
        XCTAssertEqual(settingsManager.serverPort, 1024)

        // Test maximum valid port
        settingsManager.serverPort = 65535
        XCTAssertEqual(settingsManager.serverPort, 65535)

        // Test common ports
        settingsManager.serverPort = 3000
        XCTAssertEqual(settingsManager.serverPort, 3000)

        settingsManager.serverPort = 8080
        XCTAssertEqual(settingsManager.serverPort, 8080)
    }

    func testLogLevelSettings() {
        let validLevels = ["debug", "info", "warning", "error"]

        for level in validLevels {
            settingsManager.logLevel = level
            XCTAssertEqual(settingsManager.logLevel, level)
        }
    }

    func testMaxLogEntriesSettings() {
        settingsManager.maxLogEntries = 100
        XCTAssertEqual(settingsManager.maxLogEntries, 100)

        settingsManager.maxLogEntries = 5000
        XCTAssertEqual(settingsManager.maxLogEntries, 5000)

        settingsManager.maxLogEntries = 10000
        XCTAssertEqual(settingsManager.maxLogEntries, 10000)
    }

    func testNgrokTokenSettings() {
        settingsManager.enableTunnel = true
        settingsManager.tunnelProvider = "ngrok"
        settingsManager.ngrokAuthToken = "test-token-12345"

        XCTAssertTrue(settingsManager.enableTunnel)
        XCTAssertEqual(settingsManager.tunnelProvider, "ngrok")
        XCTAssertEqual(settingsManager.ngrokAuthToken, "test-token-12345")

        // Test clearing token
        settingsManager.ngrokAuthToken = ""
        XCTAssertEqual(settingsManager.ngrokAuthToken, "")
    }

    // MARK: - Advanced Settings Tests

    func testAdvancedSettings() {
        settingsManager.serverCommand = "yarn start"
        XCTAssertEqual(settingsManager.serverCommand, "yarn start")

        settingsManager.nodeExecutable = "/usr/local/bin/node"
        XCTAssertEqual(settingsManager.nodeExecutable, "/usr/local/bin/node")

        settingsManager.npmExecutable = "/usr/local/bin/npm"
        XCTAssertEqual(settingsManager.npmExecutable, "/usr/local/bin/npm")

        settingsManager.defaultProjectDirectory = "/Users/test/projects"
        XCTAssertEqual(settingsManager.defaultProjectDirectory, "/Users/test/projects")
    }

    // MARK: - Export/Import Tests

    func testExportSettings() {
        // Set some custom values
        settingsManager.serverPort = 4444
        settingsManager.autoStartServer = true
        settingsManager.logLevel = "debug"

        let exportedData = settingsManager.exportSettings()
        XCTAssertNotNil(exportedData, "Export should produce data")

        if let data = exportedData,
           let exported = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            XCTAssertEqual(exported["serverPort"] as? Int, 4444)
            XCTAssertEqual(exported["autoStartServer"] as? Bool, true)
            XCTAssertEqual(exported["logLevel"] as? String, "debug")
        } else {
            XCTFail("Failed to parse exported settings")
        }
    }

    func testImportSettings() throws {
        let settingsToImport: [String: Any] = [
            "serverPort": 5555,
            "autoStartServer": true,
            "logLevel": "warning",
            "maxLogEntries": 2000,
            "enableTunnel": true,
            "tunnelProvider": "cloudflare"
        ]

        let data = try JSONSerialization.data(withJSONObject: settingsToImport)
        try settingsManager.importSettings(from: data)

        XCTAssertEqual(settingsManager.serverPort, 5555)
        XCTAssertTrue(settingsManager.autoStartServer)
        XCTAssertEqual(settingsManager.logLevel, "warning")
        XCTAssertEqual(settingsManager.maxLogEntries, 2000)
        XCTAssertTrue(settingsManager.enableTunnel)
        XCTAssertEqual(settingsManager.tunnelProvider, "cloudflare")
    }

    func testImportInvalidSettings() {
        // Store current values
        let originalPort = settingsManager.serverPort

        // Try to import invalid data
        let invalidData = "not json".data(using: .utf8)!

        do {
            try settingsManager.importSettings(from: invalidData)
            XCTFail("Should have thrown error for invalid data")
        } catch {
            // Expected error
            XCTAssertEqual(settingsManager.serverPort, originalPort, "Port should remain unchanged")
        }
    }

    // MARK: - Reset Tests

    func testResetToDefaults() {
        // Change multiple settings
        settingsManager.serverPort = 9999
        settingsManager.autoStartServer = true
        settingsManager.enableTunnel = true
        settingsManager.logLevel = "debug"
        settingsManager.maxLogEntries = 5000

        // Reset
        settingsManager.resetToDefaults()

        // Verify all reset to defaults
        XCTAssertEqual(settingsManager.serverPort, 3001)
        XCTAssertFalse(settingsManager.autoStartServer)
        XCTAssertFalse(settingsManager.enableTunnel)
        XCTAssertEqual(settingsManager.logLevel, "info")
        XCTAssertEqual(settingsManager.maxLogEntries, 1000)
    }

    // MARK: - Published Properties Tests

    func testConfigurationChangedPublisher() {
        let expectation = XCTestExpectation(description: "Configuration changed published")

        settingsManager.$configurationChanged
            .dropFirst()
            .sink { changed in
                if changed {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // Trigger a configuration change
        settingsManager.serverPort = 6666

        wait(for: [expectation], timeout: 2.0)
    }
}
