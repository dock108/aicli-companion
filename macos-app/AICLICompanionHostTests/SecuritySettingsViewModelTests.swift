//
//  SecuritySettingsViewModelTests.swift
//  AICLICompanionHostTests
//
//  Tests for SecuritySettingsViewModel
//

import XCTest
import Combine
@testable import AICLICompanionHost

@MainActor
final class SecuritySettingsViewModelTests: XCTestCase {
    
    var viewModel: SecuritySettingsViewModel!
    var settingsManager: SettingsManager!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() async throws {
        try await super.setUp()
        settingsManager = SettingsManager.shared
        settingsManager.resetToDefaults()
        
        viewModel = SecuritySettingsViewModel()
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() async throws {
        cancellables.removeAll()
        settingsManager.resetToDefaults()
        try await super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitialization() {
        XCTAssertNotNil(viewModel.blockedCommands)
        XCTAssertNotNil(viewModel.safeDirectories)
        XCTAssertNotNil(viewModel.allowedTools)
        XCTAssertEqual(viewModel.securityPreset, "standard")
        XCTAssertFalse(viewModel.hasUnsavedChanges)
        XCTAssertEqual(viewModel.newBlockedCommand, "")
        XCTAssertEqual(viewModel.newSafeDirectory, "")
    }
    
    func testAvailablePresets() {
        XCTAssertEqual(viewModel.availablePresets.count, 4)
        XCTAssertNotNil(viewModel.availablePresets["unrestricted"])
        XCTAssertNotNil(viewModel.availablePresets["standard"])
        XCTAssertNotNil(viewModel.availablePresets["restricted"])
        XCTAssertNotNil(viewModel.availablePresets["custom"])
    }
    
    func testDangerousCommandsList() {
        XCTAssertTrue(viewModel.dangerousCommands.contains("rm -rf /"))
        XCTAssertTrue(viewModel.dangerousCommands.contains("format"))
        XCTAssertTrue(viewModel.dangerousCommands.contains(":(){ :|:& };:"))
        XCTAssertTrue(viewModel.dangerousCommands.count > 5)
    }
    
    func testAvailableToolsList() {
        XCTAssertTrue(viewModel.availableTools.contains("Read"))
        XCTAssertTrue(viewModel.availableTools.contains("Write"))
        XCTAssertTrue(viewModel.availableTools.contains("Bash"))
        XCTAssertTrue(viewModel.availableTools.contains("WebSearch"))
    }
    
    // MARK: - Preset Application Tests
    
    func testApplyUnrestrictedPreset() {
        viewModel.applyPreset("unrestricted")
        
        XCTAssertEqual(viewModel.securityPreset, "unrestricted")
        XCTAssertEqual(viewModel.blockedCommands.count, 0)
        XCTAssertFalse(viewModel.requireConfirmation)
        XCTAssertFalse(viewModel.readOnlyMode)
        XCTAssertFalse(viewModel.blockDestructiveCommands)
        XCTAssertTrue(viewModel.skipPermissions)
        XCTAssertEqual(viewModel.allowedCLITools.count, viewModel.availableTools.count)
        XCTAssertTrue(viewModel.hasUnsavedChanges)
    }
    
    func testApplyStandardPreset() {
        viewModel.applyPreset("standard")
        
        XCTAssertEqual(viewModel.securityPreset, "standard")
        XCTAssertEqual(viewModel.blockedCommands, viewModel.dangerousCommands)
        XCTAssertTrue(viewModel.requireConfirmation)
        XCTAssertFalse(viewModel.readOnlyMode)
        XCTAssertTrue(viewModel.blockDestructiveCommands)
        XCTAssertFalse(viewModel.skipPermissions)
        XCTAssertEqual(viewModel.allowedCLITools.count, viewModel.availableTools.count)
        XCTAssertTrue(viewModel.hasUnsavedChanges)
    }
    
    func testApplyRestrictedPreset() {
        viewModel.applyPreset("restricted")
        
        XCTAssertEqual(viewModel.securityPreset, "restricted")
        XCTAssertEqual(viewModel.blockedCommands, ["*"])
        XCTAssertTrue(viewModel.requireConfirmation)
        XCTAssertTrue(viewModel.readOnlyMode)
        XCTAssertTrue(viewModel.blockDestructiveCommands)
        XCTAssertFalse(viewModel.skipPermissions)
        XCTAssertEqual(viewModel.allowedCLITools, Set(["Read", "List", "Grep"]))
        XCTAssertTrue(viewModel.hasUnsavedChanges)
    }
    
    func testApplyCustomPreset() {
        // Set some custom values
        viewModel.blockedCommands = ["custom_cmd"]
        viewModel.requireConfirmation = true
        
        viewModel.applyPreset("custom")
        
        XCTAssertEqual(viewModel.securityPreset, "custom")
        // Custom preset should not change settings
        XCTAssertEqual(viewModel.blockedCommands, ["custom_cmd"])
        XCTAssertTrue(viewModel.requireConfirmation)
        XCTAssertTrue(viewModel.hasUnsavedChanges)
    }
    
    // MARK: - Command Validation Tests
    
    func testValidateBlockedCommand() {
        viewModel.blockedCommands = ["rm -rf", "format"]
        
        let result1 = viewModel.validateCommand("rm -rf /home")
        XCTAssertFalse(result1.isAllowed)
        XCTAssertTrue(result1.reason.contains("blocked pattern"))
        
        let result2 = viewModel.validateCommand("format c:")
        XCTAssertFalse(result2.isAllowed)
        XCTAssertTrue(result2.reason.contains("blocked pattern"))
        
        let result3 = viewModel.validateCommand("ls -la")
        XCTAssertTrue(result3.isAllowed)
    }
    
    func testValidateAllCommandsBlocked() {
        viewModel.blockedCommands = ["*"]
        
        let result = viewModel.validateCommand("any_command")
        XCTAssertFalse(result.isAllowed)
        XCTAssertTrue(result.reason.contains("All commands are blocked"))
    }
    
    func testValidateDangerousPatterns() {
        viewModel.blockDestructiveCommands = true
        
        let result1 = viewModel.validateCommand("rm -rf /some/path")
        XCTAssertFalse(result1.isAllowed)
        XCTAssertTrue(result1.reason.contains("dangerous pattern"))
        
        let result2 = viewModel.validateCommand("chmod 777 /etc")
        XCTAssertFalse(result2.isAllowed)
        XCTAssertTrue(result2.reason.contains("dangerous pattern"))
        
        viewModel.blockDestructiveCommands = false
        let result3 = viewModel.validateCommand("rm -rf /some/path")
        XCTAssertTrue(result3.isAllowed)
    }
    
    func testValidateReadOnlyMode() {
        viewModel.readOnlyMode = true
        
        let writeCommands = [
            "touch newfile",
            "mkdir newdir",
            "echo > file",
            "cat > file",
            "cp source dest",
            "mv source dest",
            "rm file"
        ]
        
        for cmd in writeCommands {
            let result = viewModel.validateCommand(cmd)
            XCTAssertFalse(result.isAllowed)
            XCTAssertTrue(result.reason.contains("read-only mode"))
        }
        
        // Read commands should be allowed
        let result = viewModel.validateCommand("ls -la")
        XCTAssertTrue(result.isAllowed)
    }
    
    // MARK: - Blocked Commands Management Tests
    
    func testAddBlockedCommand() {
        viewModel.newBlockedCommand = "dangerous_cmd"
        viewModel.addBlockedCommand()
        
        XCTAssertTrue(viewModel.blockedCommands.contains("dangerous_cmd"))
        XCTAssertEqual(viewModel.newBlockedCommand, "")
        XCTAssertTrue(viewModel.hasUnsavedChanges)
    }
    
    func testAddDuplicateBlockedCommand() {
        viewModel.blockedCommands = ["existing_cmd"]
        viewModel.hasUnsavedChanges = false
        
        viewModel.newBlockedCommand = "existing_cmd"
        viewModel.addBlockedCommand()
        
        XCTAssertEqual(viewModel.blockedCommands.count, 1)
        XCTAssertFalse(viewModel.hasUnsavedChanges)
    }
    
    func testAddEmptyBlockedCommand() {
        let initialCount = viewModel.blockedCommands.count
        
        viewModel.newBlockedCommand = "   "
        viewModel.addBlockedCommand()
        
        XCTAssertEqual(viewModel.blockedCommands.count, initialCount)
    }
    
    func testRemoveBlockedCommand() {
        viewModel.blockedCommands = ["cmd1", "cmd2", "cmd3"]
        viewModel.hasUnsavedChanges = false
        
        viewModel.removeBlockedCommand("cmd2")
        
        XCTAssertEqual(viewModel.blockedCommands, ["cmd1", "cmd3"])
        XCTAssertTrue(viewModel.hasUnsavedChanges)
    }
    
    // MARK: - Safe Directories Management Tests
    
    func testAddSafeDirectory() {
        // Create a temp directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test_dir_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        viewModel.newSafeDirectory = tempDir.path
        viewModel.addSafeDirectory()
        
        XCTAssertTrue(viewModel.safeDirectories.contains(tempDir.path))
        XCTAssertEqual(viewModel.newSafeDirectory, "")
        XCTAssertTrue(viewModel.hasUnsavedChanges)
        
        // Clean up
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    func testAddSafeDirectoryWithTilde() {
        viewModel.newSafeDirectory = "~/Documents"
        viewModel.addSafeDirectory()
        
        let expandedPath = NSString(string: "~/Documents").expandingTildeInPath
        if FileManager.default.fileExists(atPath: expandedPath) {
            XCTAssertTrue(viewModel.safeDirectories.contains(expandedPath))
        }
    }
    
    func testAddNonExistentDirectory() {
        viewModel.newSafeDirectory = "/non/existent/path"
        viewModel.addSafeDirectory()
        
        XCTAssertFalse(viewModel.safeDirectories.contains("/non/existent/path"))
        XCTAssertEqual(viewModel.newSafeDirectory, "")
    }
    
    func testRemoveSafeDirectory() {
        viewModel.safeDirectories = ["/path1", "/path2", "/path3"]
        viewModel.hasUnsavedChanges = false
        
        viewModel.removeSafeDirectory("/path2")
        
        XCTAssertEqual(viewModel.safeDirectories, ["/path1", "/path3"])
        XCTAssertTrue(viewModel.hasUnsavedChanges)
    }
    
    // MARK: - Tools Management Tests
    
    func testToggleTool() {
        viewModel.allowedCLITools = Set(["Read", "Write"])
        viewModel.hasUnsavedChanges = false
        
        // Add tool
        viewModel.toggleTool("Bash")
        XCTAssertTrue(viewModel.allowedCLITools.contains("Bash"))
        XCTAssertTrue(viewModel.allowedTools.contains("Bash"))
        XCTAssertTrue(viewModel.hasUnsavedChanges)
        
        // Remove tool
        viewModel.hasUnsavedChanges = false
        viewModel.toggleTool("Read")
        XCTAssertFalse(viewModel.allowedCLITools.contains("Read"))
        XCTAssertFalse(viewModel.allowedTools.contains("Read"))
        XCTAssertTrue(viewModel.hasUnsavedChanges)
    }
    
    // MARK: - Save and Revert Tests
    
    func testSaveSettings() {
        viewModel.blockedCommands = ["test_cmd"]
        viewModel.safeDirectories = ["/test/path"]
        viewModel.allowedTools = ["Read", "Write"]
        viewModel.requireConfirmation = true
        viewModel.readOnlyMode = true
        viewModel.skipPermissions = true
        viewModel.securityPreset = "custom"
        
        viewModel.saveSettings()
        
        XCTAssertFalse(viewModel.hasUnsavedChanges)
        
        // Verify environment variables were set
        XCTAssertNotNil(settingsManager.getEnvironmentVariable("BLOCKED_COMMANDS"))
        XCTAssertNotNil(settingsManager.getEnvironmentVariable("SAFE_DIRECTORIES"))
        XCTAssertNotNil(settingsManager.getEnvironmentVariable("ALLOWED_TOOLS"))
        XCTAssertNotNil(settingsManager.getEnvironmentVariable("CLAUDE_ALLOWED_TOOLS"))
        XCTAssertEqual(settingsManager.getEnvironmentVariable("REQUIRE_CONFIRMATION"), "true")
        XCTAssertEqual(settingsManager.getEnvironmentVariable("READ_ONLY_MODE"), "true")
        XCTAssertEqual(settingsManager.getEnvironmentVariable("CLAUDE_SKIP_PERMISSIONS"), "true")
        XCTAssertEqual(settingsManager.getEnvironmentVariable("SECURITY_PRESET"), "custom")
    }
    
    func testRevertChanges() {
        // Capture original state
        let originalCommands = viewModel.blockedCommands
        let originalPreset = viewModel.securityPreset
        
        // Make changes
        viewModel.blockedCommands = ["new_cmd"]
        viewModel.securityPreset = "unrestricted"
        viewModel.requireConfirmation = !viewModel.requireConfirmation
        
        XCTAssertTrue(viewModel.hasUnsavedChanges)
        
        // Revert
        viewModel.revertChanges()
        
        XCTAssertEqual(viewModel.blockedCommands, originalCommands)
        XCTAssertEqual(viewModel.securityPreset, originalPreset)
        XCTAssertFalse(viewModel.hasUnsavedChanges)
    }
    
    // MARK: - Change Detection Tests
    
    func testChangeDetection() {
        let expectation = XCTestExpectation(description: "Change detection")
        
        viewModel.$hasUnsavedChanges
            .dropFirst()
            .sink { hasChanges in
                if hasChanges {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        viewModel.blockedCommands.append("new_command")
        
        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(viewModel.hasUnsavedChanges)
    }
    
    func testMultipleChangesDetection() {
        viewModel.blockedCommands = ["cmd1"]
        viewModel.safeDirectories = ["/path1"]
        viewModel.requireConfirmation = !viewModel.requireConfirmation
        
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertTrue(viewModel.hasUnsavedChanges)
    }
    
    // MARK: - Directory Selection Tests
    
    func testSelectDirectoryCallback() {
        let expectation = XCTestExpectation(description: "Directory selection")
        expectation.isInverted = true // We expect this not to be called in test
        
        viewModel.selectDirectory { path in
            if path != nil {
                expectation.fulfill()
            }
        }
        
        // In test environment, the panel won't actually open
        wait(for: [expectation], timeout: 0.5)
    }
    
    // MARK: - Command Validation State Tests
    
    func testValidationState() {
        XCTAssertFalse(viewModel.isValidatingCommand)
        
        let _ = viewModel.validateCommand("test_command")
        
        // After validation completes, should be false again
        XCTAssertFalse(viewModel.isValidatingCommand)
    }
    
    // MARK: - Environment Variable Loading Tests
    
    func testLoadFromEnvironmentVariables() {
        // Set environment variables
        settingsManager.setEnvironmentVariable("BLOCKED_COMMANDS", value: "cmd1,cmd2")
        settingsManager.setEnvironmentVariable("SAFE_DIRECTORIES", value: "/path1,/path2")
        settingsManager.setEnvironmentVariable("ALLOWED_TOOLS", value: "Read,Write,Bash")
        settingsManager.setEnvironmentVariable("REQUIRE_CONFIRMATION", value: "true")
        settingsManager.setEnvironmentVariable("READ_ONLY_MODE", value: "true")
        settingsManager.setEnvironmentVariable("CLAUDE_SKIP_PERMISSIONS", value: "true")
        settingsManager.setEnvironmentVariable("SECURITY_PRESET", value: "custom")
        
        // Create new view model to test loading
        let newViewModel = SecuritySettingsViewModel()
        
        XCTAssertEqual(newViewModel.blockedCommands, ["cmd1", "cmd2"])
        XCTAssertEqual(newViewModel.safeDirectories, ["/path1", "/path2"])
        XCTAssertEqual(Set(newViewModel.allowedTools), Set(["Read", "Write", "Bash"]))
        XCTAssertTrue(newViewModel.requireConfirmation)
        XCTAssertTrue(newViewModel.readOnlyMode)
        XCTAssertTrue(newViewModel.skipPermissions)
        XCTAssertEqual(newViewModel.securityPreset, "custom")
    }
}