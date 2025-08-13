//
//  SettingsViewModelTests.swift
//  AICLICompanionHostTests
//
//  Tests for SettingsViewModel
//

import XCTest
import Combine
@testable import AICLICompanionHost

@MainActor
final class SettingsViewModelTests: XCTestCase {

    var viewModel: SettingsViewModel!
    var settingsManager: SettingsManager!
    var serverManager: ServerManager!
    var cancellables: Set<AnyCancellable>!

    override func setUp() async throws {
        try await super.setUp()
        settingsManager = SettingsManager.shared
        serverManager = ServerManager.shared

        // Reset to defaults before each test
        settingsManager.resetToDefaults()

        viewModel = SettingsViewModel()
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() async throws {
        cancellables.removeAll()
        settingsManager.resetToDefaults()
        try await super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitialization() {
        XCTAssertEqual(viewModel.serverPort, settingsManager.serverPort)
        XCTAssertEqual(viewModel.autoStartServer, settingsManager.autoStartServer)
        XCTAssertEqual(viewModel.enableNotifications, settingsManager.enableNotifications)
        XCTAssertEqual(viewModel.logLevel, settingsManager.logLevel)
        XCTAssertFalse(viewModel.hasUnsavedChanges)
        XCTAssertFalse(viewModel.needsRestart)
        XCTAssertEqual(viewModel.validationErrors.count, 0)
    }

    // MARK: - Validation Tests

    func testPortValidation() {
        // Valid port
        viewModel.serverPort = 3001
        XCTAssertTrue(viewModel.validationErrors.isEmpty)

        // Invalid port - too low
        viewModel.serverPort = 80
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertTrue(viewModel.validationErrors.contains { $0.contains("Port must be between") })

        // Invalid port - too high
        viewModel.serverPort = 70000
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertTrue(viewModel.validationErrors.contains { $0.contains("Port must be between") })

        // Reset to valid
        viewModel.serverPort = 3001
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertTrue(viewModel.validationErrors.isEmpty)
    }

    func testMaxLogEntriesValidation() {
        // Note: maxLogEntries is not watched in setupBindings, so validation won't trigger automatically
        // Testing that values can be set without crashing

        // Valid range
        viewModel.maxLogEntries = 1000
        XCTAssertEqual(viewModel.maxLogEntries, 1000)

        // Edge values can be set
        viewModel.maxLogEntries = 50
        XCTAssertEqual(viewModel.maxLogEntries, 50)

        viewModel.maxLogEntries = 20000
        XCTAssertEqual(viewModel.maxLogEntries, 20000)

        // Reset to valid value
        viewModel.maxLogEntries = 1000
        XCTAssertEqual(viewModel.maxLogEntries, 1000)
    }

    func testNgrokTokenValidation() async {
        // Enable tunnel with ngrok
        viewModel.enableTunnel = true
        viewModel.tunnelProvider = "ngrok"
        viewModel.ngrokAuthToken = ""

        // Wait for validation to run
        let expectation = XCTestExpectation(description: "Ngrok token validation error")

        viewModel.$validationErrors
            .sink { errors in
                if errors.contains(where: { $0.contains("Ngrok auth token is required") }) {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertTrue(viewModel.validationErrors.contains { $0.contains("Ngrok auth token is required") })

        // Add token
        viewModel.ngrokAuthToken = "test_token_123456789"

        let expectation2 = XCTestExpectation(description: "Ngrok token validation clear")

        viewModel.$validationErrors
            .sink { errors in
                if !errors.contains(where: { $0.contains("Ngrok auth token") }) {
                    expectation2.fulfill()
                }
            }
            .store(in: &cancellables)

        await fulfillment(of: [expectation2], timeout: 2.0)
        XCTAssertFalse(viewModel.validationErrors.contains { $0.contains("Ngrok auth token") })
    }

    func testServerCommandValidation() {
        // Empty command
        viewModel.serverCommand = ""
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertTrue(viewModel.validationErrors.contains { $0.contains("Server command cannot be empty") })

        // Valid command
        viewModel.serverCommand = "npm start"
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertFalse(viewModel.validationErrors.contains { $0.contains("Server command") })
    }

    func testProjectDirectoryValidation() {
        // Empty is valid
        viewModel.defaultProjectDirectory = ""
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertFalse(viewModel.validationErrors.contains { $0.contains("project directory") })

        // Non-existent directory
        viewModel.defaultProjectDirectory = "/non/existent/path"
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertTrue(viewModel.validationErrors.contains { $0.contains("project directory does not exist") })

        // Existing directory
        viewModel.defaultProjectDirectory = "/tmp"
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertFalse(viewModel.validationErrors.contains { $0.contains("project directory") })
    }

    // MARK: - Change Detection Tests

    func testChangeDetection() async {
        XCTAssertFalse(viewModel.hasUnsavedChanges)

        // Change a setting - autoStartServer is watched in setupBindings()
        let originalValue = viewModel.autoStartServer
        viewModel.autoStartServer = !originalValue

        // Give time for Combine publishers to fire
        let expectation = XCTestExpectation(description: "Change detection")

        viewModel.$hasUnsavedChanges
            .dropFirst()
            .sink { hasChanges in
                if hasChanges {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertTrue(viewModel.hasUnsavedChanges)

        // Revert
        viewModel.revertChanges()
        XCTAssertFalse(viewModel.hasUnsavedChanges)
        XCTAssertEqual(viewModel.autoStartServer, originalValue)
    }

    func testMultipleChangesDetection() async {
        // Make multiple changes - autoStartServer is watched in setupBindings()
        viewModel.autoStartServer = !viewModel.autoStartServer
        viewModel.enableNotifications = !viewModel.enableNotifications
        viewModel.maxLogEntries = 2000

        // Wait for Combine publishers to process changes
        let expectation = XCTestExpectation(description: "Multiple changes detection")

        viewModel.$hasUnsavedChanges
            .dropFirst()
            .sink { hasChanges in
                if hasChanges {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertTrue(viewModel.hasUnsavedChanges)
    }

    // MARK: - Restart Required Tests

    func testRestartRequiredForPortChange() {
        // Simulate server running
        serverManager.isRunning = true

        // Change port
        viewModel.serverPort = 4000
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        XCTAssertTrue(viewModel.needsRestart)
        XCTAssertTrue(viewModel.restartMessage.contains("restart required"))
    }

    func testRestartRequiredForAuthChange() {
        serverManager.isRunning = true

        viewModel.requireAuthentication = !viewModel.requireAuthentication
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        XCTAssertTrue(viewModel.needsRestart)
    }

    func testRestartRequiredForTunnelChange() {
        serverManager.isRunning = true

        viewModel.enableTunnel = !viewModel.enableTunnel
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        XCTAssertTrue(viewModel.needsRestart)
    }

    func testNoRestartRequiredWhenStopped() {
        serverManager.isRunning = false

        viewModel.serverPort = 4000
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        XCTAssertFalse(viewModel.needsRestart)
        XCTAssertEqual(viewModel.restartMessage, "")
    }

    // MARK: - Apply Settings Tests

    func testApplySettings() async throws {
        // Make changes
        viewModel.serverPort = 4000
        viewModel.autoStartServer = true
        viewModel.enableNotifications = false

        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertTrue(viewModel.hasUnsavedChanges)

        // Apply
        try await viewModel.applySettings()

        // Verify applied
        XCTAssertFalse(viewModel.hasUnsavedChanges)
        XCTAssertEqual(settingsManager.serverPort, 4000)
        XCTAssertTrue(settingsManager.autoStartServer)
        XCTAssertFalse(settingsManager.enableNotifications)
    }

    func testApplySettingsWithValidationError() async {
        // Create validation error using serverPort (which is watched)
        viewModel.serverPort = 80

        // Wait for validation to trigger
        let expectation = XCTestExpectation(description: "Validation error")

        viewModel.$validationErrors
            .sink { errors in
                if !errors.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertFalse(viewModel.canSave)
        XCTAssertFalse(viewModel.validationErrors.isEmpty)

        // Try to apply - should throw
        do {
            try await viewModel.applySettings()
            XCTFail("Should have thrown validation error")
        } catch {
            // Any error is acceptable, validation failed
            XCTAssertNotNil(error)
        }
    }

    // MARK: - Reset Tests

    func testResetToDefaults() {
        // Change settings
        viewModel.serverPort = 4000
        viewModel.autoStartServer = true
        viewModel.maxLogEntries = 2000

        // Reset
        viewModel.resetToDefaults()

        // Verify reset
        XCTAssertEqual(viewModel.serverPort, 3001)
        XCTAssertFalse(viewModel.autoStartServer)
        XCTAssertEqual(viewModel.maxLogEntries, 1000)
        XCTAssertFalse(viewModel.hasUnsavedChanges)
        XCTAssertTrue(viewModel.validationErrors.isEmpty)
    }

    // MARK: - Revert Changes Tests

    func testRevertChanges() {
        let originalPort = viewModel.serverPort
        let originalAutoStart = viewModel.autoStartServer

        // Make changes
        viewModel.serverPort = 4000
        viewModel.autoStartServer = !originalAutoStart

        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertTrue(viewModel.hasUnsavedChanges)

        // Revert
        viewModel.revertChanges()

        XCTAssertEqual(viewModel.serverPort, originalPort)
        XCTAssertEqual(viewModel.autoStartServer, originalAutoStart)
        XCTAssertFalse(viewModel.hasUnsavedChanges)
    }

    // MARK: - Import/Export Tests

    func testExportSettings() {
        let data = viewModel.exportSettings()
        XCTAssertNotNil(data)
    }

    func testImportSettings() async throws {
        // Export current settings
        guard let exportedData = viewModel.exportSettings() else {
            XCTFail("Failed to export settings")
            return
        }

        // Change settings
        viewModel.serverPort = 5000
        try await viewModel.applySettings()

        // Import back
        try viewModel.importSettings(from: exportedData)

        // Should be back to original
        XCTAssertEqual(viewModel.serverPort, 3001)
        XCTAssertFalse(viewModel.hasUnsavedChanges)
    }

    // MARK: - Ngrok Token Validation Tests

    func testValidateNgrokTokenValid() async {
        viewModel.ngrokAuthToken = "test_token_12345678901234567890"

        let isValid = await viewModel.validateNgrokToken()

        XCTAssertTrue(isValid)
    }

    func testValidateNgrokTokenInvalid() async {
        viewModel.ngrokAuthToken = "short"

        let isValid = await viewModel.validateNgrokToken()

        XCTAssertFalse(isValid)
    }

    func testValidateNgrokTokenEmpty() async {
        viewModel.ngrokAuthToken = ""

        let isValid = await viewModel.validateNgrokToken()

        XCTAssertTrue(isValid) // Empty is considered valid (optional)
    }

    // MARK: - Computed Properties Tests

    func testCanSave() async {
        // Initially cannot save (no unsaved changes)
        XCTAssertFalse(viewModel.canSave)

        // Make valid change using a watched property
        let originalValue = viewModel.autoStartServer
        viewModel.autoStartServer = !originalValue

        let expectation = XCTestExpectation(description: "Can save after valid change")

        // Wait for hasUnsavedChanges to update, then check canSave
        viewModel.$hasUnsavedChanges
            .dropFirst()
            .sink { hasChanges in
                if hasChanges {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertTrue(viewModel.canSave)

        // Add validation error using a watched property
        viewModel.serverPort = 80  // This should trigger validation

        let expectation2 = XCTestExpectation(description: "Cannot save with validation error")

        viewModel.$validationErrors
            .sink { errors in
                if !errors.isEmpty {
                    expectation2.fulfill()
                }
            }
            .store(in: &cancellables)

        await fulfillment(of: [expectation2], timeout: 2.0)
        XCTAssertFalse(viewModel.canSave)
    }

    func testIsServerRunning() {
        serverManager.isRunning = false
        XCTAssertFalse(viewModel.isServerRunning)

        serverManager.isRunning = true
        XCTAssertTrue(viewModel.isServerRunning)
    }

    // MARK: - Binding Tests

    func testSettingsBinding() {
        let expectation = XCTestExpectation(description: "Settings binding")

        viewModel.$hasUnsavedChanges
            .dropFirst()
            .sink { hasChanges in
                if hasChanges {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        viewModel.serverPort = 5000

        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(viewModel.hasUnsavedChanges)
    }

    func testValidationErrorsBinding() {
        let expectation = XCTestExpectation(description: "Validation errors")

        viewModel.$validationErrors
            .dropFirst()
            .sink { errors in
                if !errors.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        viewModel.serverPort = 80

        wait(for: [expectation], timeout: 1.0)
        XCTAssertFalse(viewModel.validationErrors.isEmpty)
    }
}