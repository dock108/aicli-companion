//
//  SecuritySettingsViewTests.swift
//  AICLICompanionHostTests
//
//  Tests for SecuritySettingsView
//

import XCTest
import SwiftUI
@testable import AICLICompanionHost

@MainActor
final class SecuritySettingsViewTests: ViewTestCase {

    var securityView: SecuritySettingsView!
    var viewModel: SecuritySettingsViewModel!
    var hostingController: NSHostingController<SecuritySettingsView>!

    override func setUp() async throws {
        try await super.setUp()
        viewModel = SecuritySettingsViewModel()
        securityView = SecuritySettingsView()
        hostingController = NSHostingController(rootView: securityView)
    }

    override func tearDown() async throws {
        hostingController = nil
        securityView = nil
        viewModel = nil
        try await super.tearDown()
    }

    // MARK: - View Existence Tests

    func testSecuritySettingsViewExists() {
        XCTAssertNotNil(securityView)
        XCTAssertNotNil(hostingController.view)
    }

    func testViewCreatesViewModel() {
        let view = SecuritySettingsView()
        XCTAssertNotNil(view)

        let controller = NSHostingController(rootView: view)
        XCTAssertNotNil(controller.view)
    }

    // MARK: - Preset Picker Tests

    func testSecurityPresets() {
        let presets = ["unrestricted", "standard", "restricted", "custom"]

        for preset in presets {
            viewModel.applyPreset(preset)
            XCTAssertEqual(viewModel.securityPreset, preset)
            XCTAssertTrue(viewModel.hasUnsavedChanges)
        }
    }

    func testUnrestrictedPreset() {
        viewModel.applyPreset("unrestricted")

        XCTAssertEqual(viewModel.blockedCommands.count, 0)
        XCTAssertFalse(viewModel.requireConfirmation)
        XCTAssertFalse(viewModel.readOnlyMode)
        XCTAssertFalse(viewModel.blockDestructiveCommands)
        XCTAssertTrue(viewModel.skipPermissions)
    }

    func testStandardPreset() {
        viewModel.applyPreset("standard")

        XCTAssertTrue(viewModel.blockedCommands.count > 0)
        XCTAssertTrue(viewModel.requireConfirmation)
        XCTAssertFalse(viewModel.readOnlyMode)
        XCTAssertTrue(viewModel.blockDestructiveCommands)
        XCTAssertFalse(viewModel.skipPermissions)
    }

    func testRestrictedPreset() {
        viewModel.applyPreset("restricted")

        XCTAssertEqual(viewModel.blockedCommands, ["*"])
        XCTAssertTrue(viewModel.requireConfirmation)
        XCTAssertTrue(viewModel.readOnlyMode)
        XCTAssertTrue(viewModel.blockDestructiveCommands)
        XCTAssertEqual(viewModel.allowedCLITools, Set(["Read", "List", "Grep"]))
    }

    // MARK: - Command List Tests

    func testAddBlockedCommand() {
        let initialCount = viewModel.blockedCommands.count

        viewModel.newBlockedCommand = "dangerous_command"
        viewModel.addBlockedCommand()

        XCTAssertEqual(viewModel.blockedCommands.count, initialCount + 1)
        XCTAssertTrue(viewModel.blockedCommands.contains("dangerous_command"))
        XCTAssertEqual(viewModel.newBlockedCommand, "")
        XCTAssertTrue(viewModel.hasUnsavedChanges)
    }

    func testRemoveBlockedCommand() {
        viewModel.blockedCommands = ["cmd1", "cmd2", "cmd3"]
        viewModel.hasUnsavedChanges = false

        viewModel.removeBlockedCommand("cmd2")

        XCTAssertEqual(viewModel.blockedCommands, ["cmd1", "cmd3"])
        XCTAssertTrue(viewModel.hasUnsavedChanges)
    }

    func testBlockedCommandValidation() {
        // Test empty command
        viewModel.newBlockedCommand = "   "
        let initialCount = viewModel.blockedCommands.count
        viewModel.addBlockedCommand()
        XCTAssertEqual(viewModel.blockedCommands.count, initialCount)

        // Test duplicate command
        viewModel.blockedCommands = ["existing"]
        viewModel.newBlockedCommand = "existing"
        viewModel.addBlockedCommand()
        XCTAssertEqual(viewModel.blockedCommands.filter { $0 == "existing" }.count, 1)
    }

    // MARK: - Directory Picker Tests

    func testAddSafeDirectory() {
        // Create temp directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        viewModel.newSafeDirectory = tempDir.path
        viewModel.addSafeDirectory()

        XCTAssertTrue(viewModel.safeDirectories.contains(tempDir.path))
        XCTAssertEqual(viewModel.newSafeDirectory, "")
        XCTAssertTrue(viewModel.hasUnsavedChanges)

        // Clean up
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testRemoveSafeDirectory() {
        viewModel.safeDirectories = ["/path1", "/path2", "/path3"]
        viewModel.hasUnsavedChanges = false

        viewModel.removeSafeDirectory("/path2")

        XCTAssertEqual(viewModel.safeDirectories, ["/path1", "/path3"])
        XCTAssertTrue(viewModel.hasUnsavedChanges)
    }

    func testInvalidDirectoryNotAdded() {
        viewModel.newSafeDirectory = "/non/existent/directory"
        let initialCount = viewModel.safeDirectories.count

        viewModel.addSafeDirectory()

        XCTAssertEqual(viewModel.safeDirectories.count, initialCount)
    }

    // MARK: - Toggle States Tests

    func testRequireConfirmationToggle() {
        viewModel.requireConfirmation = false
        XCTAssertFalse(viewModel.requireConfirmation)

        viewModel.requireConfirmation = true
        XCTAssertTrue(viewModel.requireConfirmation)
        waitForAsync()
        XCTAssertTrue(viewModel.hasUnsavedChanges)
    }

    func testReadOnlyModeToggle() {
        viewModel.readOnlyMode = false
        XCTAssertFalse(viewModel.readOnlyMode)

        viewModel.readOnlyMode = true
        XCTAssertTrue(viewModel.readOnlyMode)
        waitForAsync()
        XCTAssertTrue(viewModel.hasUnsavedChanges)
    }

    func testBlockDestructiveCommandsToggle() {
        viewModel.blockDestructiveCommands = true
        XCTAssertTrue(viewModel.blockDestructiveCommands)

        viewModel.blockDestructiveCommands = false
        XCTAssertFalse(viewModel.blockDestructiveCommands)
        waitForAsync()
        XCTAssertTrue(viewModel.hasUnsavedChanges)
    }

    func testSkipPermissionsToggle() {
        viewModel.skipPermissions = false
        XCTAssertFalse(viewModel.skipPermissions)

        viewModel.skipPermissions = true
        XCTAssertTrue(viewModel.skipPermissions)
        waitForAsync()
        XCTAssertTrue(viewModel.hasUnsavedChanges)
    }

    // MARK: - Allowed Tools Tests

    func testToggleAllowedTool() {
        viewModel.allowedCLITools = Set(["Read", "Write"])

        // Add tool
        viewModel.toggleTool("Bash")
        XCTAssertTrue(viewModel.allowedCLITools.contains("Bash"))

        // Remove tool
        viewModel.toggleTool("Read")
        XCTAssertFalse(viewModel.allowedCLITools.contains("Read"))

        XCTAssertTrue(viewModel.hasUnsavedChanges)
    }

    func testAllToolsSelection() {
        // Select all tools
        for tool in viewModel.availableTools {
            if !viewModel.allowedCLITools.contains(tool) {
                viewModel.toggleTool(tool)
            }
        }

        XCTAssertEqual(viewModel.allowedCLITools.count, viewModel.availableTools.count)
    }

    // MARK: - Command Validation Tests

    func testCommandValidationDisplay() {
        // Test dangerous command
        let result1 = viewModel.validateCommand("rm -rf /")
        XCTAssertFalse(result1.isAllowed)
        XCTAssertFalse(result1.reason.isEmpty)

        // Test safe command
        let result2 = viewModel.validateCommand("ls -la")
        XCTAssertTrue(result2.isAllowed)
    }

    func testValidationWithReadOnlyMode() {
        viewModel.readOnlyMode = true

        let writeCommands = ["touch file", "mkdir dir", "rm file"]
        for cmd in writeCommands {
            let result = viewModel.validateCommand(cmd)
            XCTAssertFalse(result.isAllowed)
            XCTAssertTrue(result.reason.contains("read-only"))
        }
    }

    // MARK: - Save and Revert Tests

    func testSaveSettings() {
        viewModel.blockedCommands = ["test_cmd"]
        viewModel.requireConfirmation = true
        viewModel.hasUnsavedChanges = true

        viewModel.saveSettings()

        XCTAssertFalse(viewModel.hasUnsavedChanges)
    }

    func testRevertSettings() {
        let originalCommands = viewModel.blockedCommands

        viewModel.blockedCommands = ["new_cmd"]
        viewModel.requireConfirmation = !viewModel.requireConfirmation
        XCTAssertTrue(viewModel.hasUnsavedChanges)

        viewModel.revertChanges()

        XCTAssertEqual(viewModel.blockedCommands, originalCommands)
        XCTAssertFalse(viewModel.hasUnsavedChanges)
    }

    // MARK: - Dangerous Commands Tests

    func testDangerousCommandsList() {
        XCTAssertTrue(viewModel.dangerousCommands.count > 0)
        XCTAssertTrue(viewModel.dangerousCommands.contains("rm -rf /"))
        XCTAssertTrue(viewModel.dangerousCommands.contains("format"))
        XCTAssertTrue(viewModel.dangerousCommands.contains(":(){ :|:& };:"))
    }

    func testBlockAllCommands() {
        viewModel.blockedCommands = ["*"]

        let result = viewModel.validateCommand("any_command")
        XCTAssertFalse(result.isAllowed)
        XCTAssertTrue(result.reason.contains("All commands are blocked"))
    }

    // MARK: - Environment Variable Tests

    func testEnvironmentVariableSaving() {
        let settingsManager = SettingsManager.shared

        viewModel.blockedCommands = ["test1", "test2"]
        viewModel.skipPermissions = true
        viewModel.securityPreset = "custom"

        viewModel.saveSettings()

        // Verify environment variables are set
        XCTAssertNotNil(settingsManager.getEnvironmentVariable("BLOCKED_COMMANDS"))
        XCTAssertEqual(settingsManager.getEnvironmentVariable("CLAUDE_SKIP_PERMISSIONS"), "true")
        XCTAssertEqual(settingsManager.getEnvironmentVariable("SECURITY_PRESET"), "custom")
    }
}