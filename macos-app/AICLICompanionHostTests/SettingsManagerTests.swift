//
//  SettingsManagerTests.swift
//  AICLICompanionHostTests
//
//  Unit tests for SettingsManager
//

import XCTest
import Combine
@testable import AICLICompanionHost

@MainActor
final class SettingsManagerTests: XCTestCase {
    
    var mockSettingsManager: MockSettingsManager!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        mockSettingsManager = MockSettingsManager()
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() {
        mockSettingsManager.reset()
        cancellables.removeAll()
        mockSettingsManager = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testSettingsManagerInitialState() throws {
        XCTAssertEqual(mockSettingsManager.serverPort, 3001)
        XCTAssertFalse(mockSettingsManager.autoStartServer)
        XCTAssertTrue(mockSettingsManager.autoRestartOnCrash)
        XCTAssertFalse(mockSettingsManager.launchAtLogin)
        XCTAssertFalse(mockSettingsManager.showDockIcon)
        XCTAssertTrue(mockSettingsManager.enableNotifications)
        XCTAssertTrue(mockSettingsManager.enableSounds)
        XCTAssertEqual(mockSettingsManager.logLevel, "info")
        XCTAssertEqual(mockSettingsManager.maxLogEntries, 1000)
        XCTAssertTrue(mockSettingsManager.enableBonjour)
        XCTAssertEqual(mockSettingsManager.theme, "system")
        XCTAssertTrue(mockSettingsManager.requireAuthentication)
        XCTAssertTrue(mockSettingsManager.enableTouchID)
        XCTAssertFalse(mockSettingsManager.enableTunnel)
        XCTAssertEqual(mockSettingsManager.tunnelProvider, "ngrok")
        XCTAssertEqual(mockSettingsManager.ngrokAuthToken, "")
        XCTAssertEqual(mockSettingsManager.defaultProjectDirectory, "")
        XCTAssertEqual(mockSettingsManager.serverCommand, "npm start")
        XCTAssertFalse(mockSettingsManager.configurationChanged)
    }
    
    // MARK: - Reset to Defaults Tests
    
    func testResetToDefaults() throws {
        // Change some settings
        mockSettingsManager.serverPort = 8080
        mockSettingsManager.autoStartServer = true
        mockSettingsManager.enableNotifications = false
        mockSettingsManager.logLevel = "debug"
        mockSettingsManager.configurationChanged = true
        
        // Reset
        mockSettingsManager.resetToDefaults()
        
        // Verify reset
        XCTAssertTrue(mockSettingsManager.resetToDefaultsCalled)
        XCTAssertEqual(mockSettingsManager.serverPort, 3001)
        XCTAssertFalse(mockSettingsManager.autoStartServer)
        XCTAssertTrue(mockSettingsManager.enableNotifications)
        XCTAssertEqual(mockSettingsManager.logLevel, "info")
        XCTAssertFalse(mockSettingsManager.configurationChanged)
    }
    
    // MARK: - Export/Import Tests
    
    func testExportSettings() throws {
        // Modify some settings
        mockSettingsManager.serverPort = 8080
        mockSettingsManager.autoStartServer = true
        mockSettingsManager.enableTunnel = true
        mockSettingsManager.ngrokAuthToken = "test-token"
        
        // Export
        let data = mockSettingsManager.exportSettings()
        
        XCTAssertTrue(mockSettingsManager.exportSettingsCalled)
        XCTAssertNotNil(data)
        
        // Verify exported data
        if let data = data,
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            XCTAssertEqual(dict["serverPort"] as? Int, 8080)
            XCTAssertEqual(dict["autoStartServer"] as? Bool, true)
            XCTAssertEqual(dict["enableTunnel"] as? Bool, true)
            XCTAssertEqual(dict["ngrokAuthToken"] as? String, "test-token")
        } else {
            XCTFail("Failed to decode exported settings")
        }
    }
    
    func testImportSettings() throws {
        // Create settings data
        let settings: [String: Any] = [
            "serverPort": 9090,
            "autoStartServer": true,
            "enableNotifications": false,
            "logLevel": "debug",
            "maxLogEntries": 5000,
            "enableTunnel": true,
            "ngrokAuthToken": "imported-token"
        ]
        
        let data = try JSONSerialization.data(withJSONObject: settings)
        
        // Import
        let success = mockSettingsManager.importSettings(from: data)
        
        // Verify
        XCTAssertTrue(mockSettingsManager.importSettingsCalled)
        XCTAssertTrue(success)
        XCTAssertEqual(mockSettingsManager.serverPort, 9090)
        XCTAssertTrue(mockSettingsManager.autoStartServer)
        XCTAssertFalse(mockSettingsManager.enableNotifications)
        XCTAssertEqual(mockSettingsManager.logLevel, "debug")
        XCTAssertEqual(mockSettingsManager.maxLogEntries, 5000)
        XCTAssertTrue(mockSettingsManager.enableTunnel)
        XCTAssertEqual(mockSettingsManager.ngrokAuthToken, "imported-token")
        XCTAssertTrue(mockSettingsManager.configurationChanged)
    }
    
    func testImportInvalidSettings() throws {
        let invalidData = "not json".data(using: .utf8)!
        
        let success = mockSettingsManager.importSettings(from: invalidData)
        
        XCTAssertTrue(mockSettingsManager.importSettingsCalled)
        XCTAssertFalse(success)
    }
    
    // MARK: - Configuration Change Tests
    
    func testConfigurationChangeDetection() throws {
        // Initial state should not be changed
        XCTAssertFalse(mockSettingsManager.configurationChanged)
        
        // Change a setting
        mockSettingsManager.serverPort = 8080
        mockSettingsManager.checkForConfigurationChanges()
        
        XCTAssertTrue(mockSettingsManager.configurationChanged)
    }
    
    func testMarkConfigurationApplied() throws {
        // Set configuration as changed
        mockSettingsManager.configurationChanged = true
        
        // Mark as applied
        mockSettingsManager.markConfigurationApplied()
        
        XCTAssertTrue(mockSettingsManager.markConfigurationAppliedCalled)
        XCTAssertFalse(mockSettingsManager.configurationChanged)
    }
    
    func testNeedsRestart() throws {
        // Should not need restart initially
        XCTAssertFalse(mockSettingsManager.needsRestart)
        
        // Change configuration
        mockSettingsManager.configurationChanged = true
        
        // Should need restart when configuration changed
        XCTAssertTrue(mockSettingsManager.needsRestart)
    }
    
    // MARK: - Validation Tests
    
    func testValidateSettingsWithValidConfig() throws {
        // Setup valid configuration
        mockSettingsManager.serverPort = 3001
        mockSettingsManager.maxLogEntries = 1000
        mockSettingsManager.logLevel = "info"
        
        let (isValid, errors) = mockSettingsManager.validateSettings()
        
        XCTAssertTrue(mockSettingsManager.validateSettingsCalled)
        XCTAssertTrue(isValid)
        XCTAssertTrue(errors.isEmpty)
    }
    
    func testValidateSettingsWithInvalidPort() throws {
        mockSettingsManager.serverPort = 500 // Too low
        
        let (isValid, errors) = mockSettingsManager.validateSettings()
        
        XCTAssertFalse(isValid)
        XCTAssertFalse(errors.isEmpty)
        XCTAssertTrue(errors.contains { $0.contains("port") })
    }
    
    func testValidateSettingsWithInvalidMaxLogEntries() throws {
        mockSettingsManager.maxLogEntries = 50 // Too low
        
        let (isValid, errors) = mockSettingsManager.validateSettings()
        
        XCTAssertFalse(isValid)
        XCTAssertTrue(errors.contains { $0.contains("log entries") })
    }
    
    func testValidateSettingsWithInvalidLogLevel() throws {
        mockSettingsManager.logLevel = "invalid"
        
        let (isValid, errors) = mockSettingsManager.validateSettings()
        
        XCTAssertFalse(isValid)
        XCTAssertTrue(errors.contains { $0.contains("log level") })
    }
    
    func testValidateSettingsWithMissingNgrokToken() throws {
        mockSettingsManager.enableTunnel = true
        mockSettingsManager.tunnelProvider = "ngrok"
        mockSettingsManager.ngrokAuthToken = ""
        
        let (isValid, errors) = mockSettingsManager.validateSettings()
        
        XCTAssertFalse(isValid)
        XCTAssertTrue(errors.contains { $0.contains("ngrok auth token") })
    }
    
    func testValidateSettingsWithMultipleErrors() throws {
        mockSettingsManager.serverPort = 100000 // Too high
        mockSettingsManager.maxLogEntries = 20000 // Too high
        mockSettingsManager.logLevel = "invalid"
        
        let (isValid, errors) = mockSettingsManager.validateSettings()
        
        XCTAssertFalse(isValid)
        XCTAssertEqual(errors.count, 3)
    }
    
    // MARK: - Security Settings Tests
    
    func testSecuritySettings() throws {
        // Test authentication settings
        mockSettingsManager.requireAuthentication = false
        XCTAssertFalse(mockSettingsManager.requireAuthentication)
        
        mockSettingsManager.requireAuthentication = true
        XCTAssertTrue(mockSettingsManager.requireAuthentication)
        
        // Test Touch ID settings
        mockSettingsManager.enableTouchID = false
        XCTAssertFalse(mockSettingsManager.enableTouchID)
        
        mockSettingsManager.enableTouchID = true
        XCTAssertTrue(mockSettingsManager.enableTouchID)
    }
    
    // MARK: - Tunnel Settings Tests
    
    func testTunnelSettings() throws {
        // Test tunnel configuration
        mockSettingsManager.enableTunnel = true
        mockSettingsManager.tunnelProvider = "cloudflare"
        mockSettingsManager.ngrokAuthToken = "test-auth-token"
        
        XCTAssertTrue(mockSettingsManager.enableTunnel)
        XCTAssertEqual(mockSettingsManager.tunnelProvider, "cloudflare")
        XCTAssertEqual(mockSettingsManager.ngrokAuthToken, "test-auth-token")
    }
    
    // MARK: - Advanced Settings Tests
    
    func testAdvancedSettings() throws {
        mockSettingsManager.serverCommand = "yarn start"
        mockSettingsManager.serverDirectory = "/custom/server/path"
        mockSettingsManager.nodeExecutable = "/usr/local/bin/node"
        mockSettingsManager.npmExecutable = "/usr/local/bin/npm"
        
        XCTAssertEqual(mockSettingsManager.serverCommand, "yarn start")
        XCTAssertEqual(mockSettingsManager.serverDirectory, "/custom/server/path")
        XCTAssertEqual(mockSettingsManager.nodeExecutable, "/usr/local/bin/node")
        XCTAssertEqual(mockSettingsManager.npmExecutable, "/usr/local/bin/npm")
    }
    
    // MARK: - Published Properties Tests
    
    func testPublishedPropertiesUpdate() throws {
        let expectation = XCTestExpectation(description: "serverPort should publish changes")
        var receivedValues: [Int] = []
        
        mockSettingsManager.$serverPort
            .sink { value in
                receivedValues.append(value)
                if receivedValues.count >= 2 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // Change port
        mockSettingsManager.serverPort = 8080
        
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertEqual(receivedValues.first, 3001) // Initial value
        XCTAssertEqual(receivedValues.last, 8080)  // Changed value
    }
    
    // MARK: - Reset State Tests
    
    func testResetClearsAllTrackingFlags() throws {
        // Trigger all tracking flags
        mockSettingsManager.resetToDefaults()
        _ = mockSettingsManager.exportSettings()
        _ = mockSettingsManager.importSettings(from: Data())
        mockSettingsManager.markConfigurationApplied()
        _ = mockSettingsManager.validateSettings()
        
        // Verify flags are set
        XCTAssertTrue(mockSettingsManager.resetToDefaultsCalled)
        XCTAssertTrue(mockSettingsManager.exportSettingsCalled)
        XCTAssertTrue(mockSettingsManager.importSettingsCalled)
        XCTAssertTrue(mockSettingsManager.markConfigurationAppliedCalled)
        XCTAssertTrue(mockSettingsManager.validateSettingsCalled)
        
        // Reset
        mockSettingsManager.reset()
        
        // Verify all flags are cleared
        XCTAssertFalse(mockSettingsManager.resetToDefaultsCalled)
        XCTAssertFalse(mockSettingsManager.exportSettingsCalled)
        XCTAssertFalse(mockSettingsManager.importSettingsCalled)
        XCTAssertFalse(mockSettingsManager.markConfigurationAppliedCalled)
        XCTAssertFalse(mockSettingsManager.validateSettingsCalled)
        XCTAssertFalse(mockSettingsManager.configurationChanged)
    }
}