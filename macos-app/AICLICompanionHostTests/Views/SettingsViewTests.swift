//
//  SettingsViewTests.swift
//  AICLICompanionHostTests
//
//  Tests for SettingsView
//

import XCTest
import SwiftUI
@testable import AICLICompanionHost

@MainActor
final class SettingsViewTests: ViewTestCase {

    var settingsView: SettingsView!
    var viewModel: SettingsViewModel!
    var hostingController: NSHostingController<SettingsView>!

    override func setUp() async throws {
        try await super.setUp()
        viewModel = SettingsViewModel()
        settingsView = SettingsView()
        hostingController = NSHostingController(rootView: settingsView)
    }

    override func tearDown() async throws {
        hostingController = nil
        settingsView = nil
        viewModel = nil
        try await super.tearDown()
    }

    // MARK: - View Existence Tests

    func testSettingsViewExists() {
        XCTAssertNotNil(settingsView)
        XCTAssertNotNil(hostingController.view)
    }

    func testSettingsViewHasViewModel() {
        // The view should create its own view model
        let view = SettingsView()
        XCTAssertNotNil(view)

        // Test that view can be hosted
        let controller = NSHostingController(rootView: view)
        XCTAssertNotNil(controller.view)
    }

    // MARK: - Tab Structure Tests

    func testTabViewStructure() {
        // Settings should have multiple tabs
        // We test this through the ViewModel since we can't inspect SwiftUI views directly

        // General tab settings
        XCTAssertNotNil(viewModel.serverPort)
        XCTAssertNotNil(viewModel.autoStartServer)

        // Advanced tab settings
        XCTAssertNotNil(viewModel.nodeExecutable)
        XCTAssertNotNil(viewModel.npmExecutable)

        // Security tab (through separate view model)
        let securityVM = SecuritySettingsViewModel()
        XCTAssertNotNil(securityVM.blockedCommands)
        XCTAssertNotNil(securityVM.securityPreset)
    }

    // MARK: - Form Validation Tests

    func testPortValidation() {
        // Test port validation through view model
        viewModel.serverPort = 80
        waitForAsync()
        XCTAssertFalse(viewModel.validationErrors.isEmpty)

        viewModel.serverPort = 3001
        waitForAsync()
        XCTAssertTrue(viewModel.validationErrors.isEmpty)
    }

    func testMaxLogEntriesValidation() {
        viewModel.maxLogEntries = 50
        waitForAsync()
        XCTAssertFalse(viewModel.validationErrors.isEmpty)

        viewModel.maxLogEntries = 1000
        waitForAsync()
        XCTAssertTrue(viewModel.validationErrors.isEmpty)
    }

    // MARK: - Save/Cancel Action Tests

    func testSaveButtonEnablement() {
        // Initially no changes, can't save
        XCTAssertFalse(viewModel.canSave)

        // Make a valid change
        viewModel.serverPort = 4000
        waitForAsync()
        XCTAssertTrue(viewModel.hasUnsavedChanges)
        XCTAssertTrue(viewModel.canSave)

        // Make invalid change
        viewModel.serverPort = 80
        waitForAsync()
        XCTAssertTrue(viewModel.hasUnsavedChanges)
        XCTAssertFalse(viewModel.canSave) // Can't save with validation errors
    }

    func testCancelAction() {
        let originalPort = viewModel.serverPort

        // Make changes
        viewModel.serverPort = 4000
        waitForAsync()
        XCTAssertTrue(viewModel.hasUnsavedChanges)

        // Cancel (revert)
        viewModel.revertChanges()
        XCTAssertEqual(viewModel.serverPort, originalPort)
        XCTAssertFalse(viewModel.hasUnsavedChanges)
    }

    // MARK: - Theme Tests

    func testThemeOptions() {
        let themes = ["auto", "light", "dark"]

        for theme in themes {
            viewModel.theme = theme
            XCTAssertEqual(viewModel.theme, theme)
        }
    }

    // MARK: - Notification Settings Tests

    func testNotificationSettings() {
        viewModel.enableNotifications = true
        XCTAssertTrue(viewModel.enableNotifications)

        viewModel.enableNotifications = false
        XCTAssertFalse(viewModel.enableNotifications)

        viewModel.enableSounds = true
        XCTAssertTrue(viewModel.enableSounds)
    }

    // MARK: - Tunnel Settings Tests

    func testTunnelSettings() {
        // Test tunnel provider options
        viewModel.tunnelProvider = "ngrok"
        XCTAssertEqual(viewModel.tunnelProvider, "ngrok")

        viewModel.tunnelProvider = "cloudflare"
        XCTAssertEqual(viewModel.tunnelProvider, "cloudflare")

        // Test ngrok token requirement
        viewModel.enableTunnel = true
        viewModel.tunnelProvider = "ngrok"
        viewModel.ngrokAuthToken = ""
        waitForAsync()
        XCTAssertFalse(viewModel.validationErrors.isEmpty)

        viewModel.ngrokAuthToken = "test_token_12345"
        waitForAsync()
        XCTAssertTrue(viewModel.validationErrors.filter { $0.contains("Ngrok") }.isEmpty)
    }

    // MARK: - Auto Start Settings Tests

    func testAutoStartSettings() {
        viewModel.autoStartServer = true
        XCTAssertTrue(viewModel.autoStartServer)

        viewModel.autoRestartOnCrash = true
        XCTAssertTrue(viewModel.autoRestartOnCrash)

        viewModel.launchAtLogin = true
        XCTAssertTrue(viewModel.launchAtLogin)
    }

    // MARK: - Log Settings Tests

    func testLogSettings() {
        let logLevels = ["debug", "info", "warning", "error"]

        for level in logLevels {
            viewModel.logLevel = level
            XCTAssertEqual(viewModel.logLevel, level)
        }

        viewModel.maxLogEntries = 2000
        XCTAssertEqual(viewModel.maxLogEntries, 2000)
    }

    // MARK: - Server Configuration Tests

    func testServerConfiguration() {
        viewModel.serverCommand = "npm start"
        XCTAssertEqual(viewModel.serverCommand, "npm start")

        viewModel.defaultProjectDirectory = "/Users/test/projects"
        XCTAssertEqual(viewModel.defaultProjectDirectory, "/Users/test/projects")
    }

    // MARK: - Restart Detection Tests

    func testRestartDetection() {
        let serverManager = ServerManager.shared
        serverManager.isRunning = true

        // Change critical setting
        viewModel.serverPort = 4000
        waitForAsync()

        XCTAssertTrue(viewModel.needsRestart)
        XCTAssertFalse(viewModel.restartMessage.isEmpty)

        // Stop server
        serverManager.isRunning = false
        waitForAsync()

        XCTAssertFalse(viewModel.needsRestart)
    }

    // MARK: - Import/Export Tests

    func testExportSettings() {
        let exportData = viewModel.exportSettings()
        XCTAssertNotNil(exportData)
    }

    func testResetToDefaults() {
        // Change settings
        viewModel.serverPort = 5000
        viewModel.autoStartServer = true

        // Reset
        viewModel.resetToDefaults()

        // Verify defaults
        XCTAssertEqual(viewModel.serverPort, 3001)
        XCTAssertFalse(viewModel.autoStartServer)
        XCTAssertFalse(viewModel.hasUnsavedChanges)
    }

    // MARK: - Appearance Tests

    func testDockIconSetting() {
        viewModel.showDockIcon = true
        XCTAssertTrue(viewModel.showDockIcon)

        viewModel.showDockIcon = false
        XCTAssertFalse(viewModel.showDockIcon)
    }

    // MARK: - Authentication Tests

    func testAuthenticationSettings() {
        viewModel.requireAuthentication = true
        XCTAssertTrue(viewModel.requireAuthentication)

        viewModel.enableTouchID = true
        XCTAssertTrue(viewModel.enableTouchID)
    }

    // MARK: - Bonjour Tests

    func testBonjourSetting() {
        viewModel.enableBonjour = true
        XCTAssertTrue(viewModel.enableBonjour)

        viewModel.enableBonjour = false
        XCTAssertFalse(viewModel.enableBonjour)
    }
}
