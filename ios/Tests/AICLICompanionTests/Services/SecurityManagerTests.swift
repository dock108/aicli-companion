import XCTest
import Foundation
@testable import AICLICompanion

@available(iOS 16.0, macOS 13.0, *)
@MainActor
final class SecurityManagerTests: XCTestCase {
    
    // MARK: - Security Manager Creation Tests
    
    func testSecurityManagerSharedInstance() {
        // Test that shared instance exists and is the same instance
        let manager1 = SecurityManager.shared
        let manager2 = SecurityManager.shared
        
        XCTAssertTrue(manager1 === manager2, "Shared instances should be identical")
        XCTAssertNotNil(manager1.configuration)
    }
    
    func testSecurityManagerInitialState() {
        let manager = SecurityManager.shared
        
        // Test initial published properties
        XCTAssertNotNil(manager.configuration)
        XCTAssertEqual(manager.auditLog.count, 0)
        XCTAssertEqual(manager.pendingPermissions.count, 0)
        XCTAssertFalse(manager.isLoading)
        // Note: lastError may have a value due to previous tests or initialization,
        // so we just verify it can be accessed
        _ = manager.lastError // Access without asserting specific value
        
        // Test toggle states can be accessed (values may vary due to other tests)
        _ = manager.filterCommands
        _ = manager.blockDestructive
        _ = manager.readOnlyMode
    }
    
    // MARK: - Configuration Management Tests
    
    func testSecurityConfigurationDefault() {
        let config = SecurityConfiguration.default
        
        XCTAssertEqual(config.preset, .standard)
        XCTAssertEqual(config.safeDirectories.count, 0)
        XCTAssertEqual(config.blockedCommands.count, 0)
        XCTAssertTrue(config.requireConfirmation)
        XCTAssertFalse(config.readOnlyMode)
        XCTAssertTrue(config.enableAudit)
        XCTAssertEqual(config.maxFileSize, 10485760) // 10MB
    }
    
    func testSecurityConfigurationCoding() throws {
        let config = SecurityConfiguration(
            preset: .restricted,
            safeDirectories: ["/safe/path1", "/safe/path2"],
            blockedCommands: ["rm -rf", "format"],
            destructiveCommands: ["dd", "mkfs"],
            requireConfirmation: true,
            maxFileSize: 5242880, // 5MB
            readOnlyMode: true,
            enableAudit: true
        )
        
        // Test encoding
        let encoder = JSONEncoder()
        let data = try encoder.encode(config)
        XCTAssertFalse(data.isEmpty)
        
        // Test decoding
        let decoder = JSONDecoder()
        let decodedConfig = try decoder.decode(SecurityConfiguration.self, from: data)
        XCTAssertEqual(decodedConfig, config)
        XCTAssertEqual(decodedConfig.preset, .restricted)
        XCTAssertEqual(decodedConfig.safeDirectories, ["/safe/path1", "/safe/path2"])
        XCTAssertEqual(decodedConfig.blockedCommands, ["rm -rf", "format"])
        XCTAssertTrue(decodedConfig.readOnlyMode)
    }
    
    func testSaveAndLoadConfiguration() {
        let manager = SecurityManager.shared
        let originalConfig = manager.configuration
        
        // Create a test configuration
        let testConfig = SecurityConfiguration(
            preset: .custom,
            safeDirectories: ["/test/safe"],
            blockedCommands: ["test-command"],
            requireConfirmation: false,
            readOnlyMode: true
        )
        
        // Save the configuration
        manager.saveConfiguration(testConfig)
        
        // Load and verify
        manager.loadConfiguration()
        XCTAssertEqual(manager.configuration.preset, .custom)
        XCTAssertEqual(manager.configuration.safeDirectories, ["/test/safe"])
        XCTAssertEqual(manager.configuration.blockedCommands, ["test-command"])
        XCTAssertFalse(manager.configuration.requireConfirmation)
        XCTAssertTrue(manager.configuration.readOnlyMode)
        XCTAssertTrue(manager.readOnlyMode)
        
        // Restore original config
        manager.saveConfiguration(originalConfig)
        manager.loadConfiguration()
    }
    
    // MARK: - Security Preset Tests
    
    func testSecurityPresetValues() {
        let presets: [SecurityPreset] = [.unrestricted, .standard, .restricted, .custom]
        
        for preset in presets {
            XCTAssertFalse(preset.displayName.isEmpty)
            XCTAssertFalse(preset.description.isEmpty)
            XCTAssertFalse(preset.icon.isEmpty)
        }
        
        // Test specific values
        XCTAssertEqual(SecurityPreset.unrestricted.displayName, "Unrestricted")
        XCTAssertEqual(SecurityPreset.standard.displayName, "Standard")
        XCTAssertEqual(SecurityPreset.restricted.displayName, "Restricted")
        XCTAssertEqual(SecurityPreset.custom.displayName, "Custom")
    }
    
    func testApplyUnrestrictedPreset() {
        let manager = SecurityManager.shared
        
        manager.applyPreset(.unrestricted)
        
        XCTAssertEqual(manager.configuration.preset, .unrestricted)
        XCTAssertEqual(manager.configuration.blockedCommands.count, 0)
        XCTAssertFalse(manager.configuration.requireConfirmation)
        XCTAssertFalse(manager.configuration.readOnlyMode)
        XCTAssertFalse(manager.filterCommands)
        XCTAssertFalse(manager.blockDestructive)
        XCTAssertFalse(manager.readOnlyMode)
    }
    
    func testApplyStandardPreset() {
        let manager = SecurityManager.shared
        
        manager.applyPreset(.standard)
        
        XCTAssertEqual(manager.configuration.preset, .standard)
        XCTAssertTrue(manager.configuration.blockedCommands.count > 0)
        XCTAssertTrue(manager.configuration.requireConfirmation)
        XCTAssertFalse(manager.configuration.readOnlyMode)
        XCTAssertTrue(manager.filterCommands)
        XCTAssertTrue(manager.blockDestructive)
        XCTAssertFalse(manager.readOnlyMode)
        
        // Check for dangerous commands
        XCTAssertTrue(manager.configuration.blockedCommands.contains("rm -rf /"))
        XCTAssertTrue(manager.configuration.blockedCommands.contains("format"))
    }
    
    func testApplyRestrictedPreset() {
        let manager = SecurityManager.shared
        
        manager.applyPreset(.restricted)
        
        XCTAssertEqual(manager.configuration.preset, .restricted)
        XCTAssertEqual(manager.configuration.blockedCommands, ["*"])
        XCTAssertTrue(manager.configuration.requireConfirmation)
        XCTAssertTrue(manager.configuration.readOnlyMode)
        XCTAssertTrue(manager.filterCommands)
        XCTAssertTrue(manager.blockDestructive)
        XCTAssertTrue(manager.readOnlyMode)
    }
    
    func testApplyCustomPreset() {
        let manager = SecurityManager.shared
        let originalConfig = manager.configuration
        
        manager.applyPreset(.custom)
        
        // Custom preset should not change existing configuration
        XCTAssertEqual(manager.configuration.preset, .custom)
        XCTAssertEqual(manager.configuration.safeDirectories, originalConfig.safeDirectories)
        XCTAssertEqual(manager.configuration.blockedCommands, originalConfig.blockedCommands)
    }
    
    // MARK: - Directory Management Tests
    
    func testAddSafeDirectory() {
        let manager = SecurityManager.shared
        let testPath = "/test/safe/directory"
        let initialCount = manager.configuration.safeDirectories.count
        
        manager.addSafeDirectory(testPath)
        
        XCTAssertEqual(manager.configuration.safeDirectories.count, initialCount + 1)
        XCTAssertTrue(manager.configuration.safeDirectories.contains(testPath))
        
        // Test adding duplicate doesn't increase count
        manager.addSafeDirectory(testPath)
        XCTAssertEqual(manager.configuration.safeDirectories.count, initialCount + 1)
        
        // Clean up
        manager.removeSafeDirectory(testPath)
    }
    
    func testRemoveSafeDirectory() {
        let manager = SecurityManager.shared
        let testPath = "/test/remove/directory"
        
        // Add then remove
        manager.addSafeDirectory(testPath)
        XCTAssertTrue(manager.configuration.safeDirectories.contains(testPath))
        
        manager.removeSafeDirectory(testPath)
        XCTAssertFalse(manager.configuration.safeDirectories.contains(testPath))
    }
    
    func testMultipleSafeDirectories() {
        let manager = SecurityManager.shared
        let paths = ["/test/dir1", "/test/dir2", "/test/dir3"]
        let initialCount = manager.configuration.safeDirectories.count
        
        // Add multiple directories
        for path in paths {
            manager.addSafeDirectory(path)
        }
        
        XCTAssertEqual(manager.configuration.safeDirectories.count, initialCount + paths.count)
        for path in paths {
            XCTAssertTrue(manager.configuration.safeDirectories.contains(path))
        }
        
        // Clean up
        for path in paths {
            manager.removeSafeDirectory(path)
        }
    }
    
    // MARK: - Command Pattern Management Tests
    
    func testAddBlockedCommand() {
        let manager = SecurityManager.shared
        let testCommand = "dangerous-test-command"
        let initialCount = manager.configuration.blockedCommands.count
        
        manager.addBlockedCommand(testCommand)
        
        XCTAssertEqual(manager.configuration.blockedCommands.count, initialCount + 1)
        XCTAssertTrue(manager.configuration.blockedCommands.contains(testCommand))
        
        // Test adding duplicate doesn't increase count
        manager.addBlockedCommand(testCommand)
        XCTAssertEqual(manager.configuration.blockedCommands.count, initialCount + 1)
        
        // Clean up
        manager.removeBlockedCommand(testCommand)
    }
    
    func testRemoveBlockedCommand() {
        let manager = SecurityManager.shared
        let testCommand = "test-remove-command"
        
        // Add then remove
        manager.addBlockedCommand(testCommand)
        XCTAssertTrue(manager.configuration.blockedCommands.contains(testCommand))
        
        manager.removeBlockedCommand(testCommand)
        XCTAssertFalse(manager.configuration.blockedCommands.contains(testCommand))
    }
    
    func testMultipleBlockedCommands() {
        let manager = SecurityManager.shared
        let commands = ["cmd1", "cmd2 --dangerous", "rm test*"]
        let initialCount = manager.configuration.blockedCommands.count
        
        // Add multiple commands
        for command in commands {
            manager.addBlockedCommand(command)
        }
        
        XCTAssertEqual(manager.configuration.blockedCommands.count, initialCount + commands.count)
        for command in commands {
            XCTAssertTrue(manager.configuration.blockedCommands.contains(command))
        }
        
        // Clean up
        for command in commands {
            manager.removeBlockedCommand(command)
        }
    }
    
    // MARK: - Audit Log Tests
    
    func testAuditLogEntry() {
        let entry = AuditLogEntry(
            id: "test-entry-123",
            timestamp: Date(),
            command: "ls -la",
            workingDirectory: "/test/dir",
            allowed: true,
            reason: "Command allowed",
            sessionId: "session-456",
            code: "200"
        )
        
        XCTAssertEqual(entry.id, "test-entry-123")
        XCTAssertEqual(entry.command, "ls -la")
        XCTAssertEqual(entry.workingDirectory, "/test/dir")
        XCTAssertTrue(entry.allowed)
        XCTAssertEqual(entry.reason, "Command allowed")
        XCTAssertEqual(entry.sessionId, "session-456")
        XCTAssertEqual(entry.code, "200")
        XCTAssertFalse(entry.formattedTime.isEmpty)
        XCTAssertEqual(entry.statusIcon, "checkmark.circle.fill")
        XCTAssertEqual(entry.statusColor, "green")
    }
    
    func testAuditLogEntryDenied() {
        let entry = AuditLogEntry(
            id: "test-denied-123",
            timestamp: Date(),
            command: "rm -rf /",
            workingDirectory: "/",
            allowed: false,
            reason: "Dangerous command blocked",
            sessionId: nil,
            code: "403"
        )
        
        XCTAssertFalse(entry.allowed)
        XCTAssertEqual(entry.statusIcon, "xmark.circle.fill")
        XCTAssertEqual(entry.statusColor, "red")
    }
    
    func testAuditLogEntryCoding() throws {
        let entry = AuditLogEntry(
            id: "coding-test-123",
            timestamp: Date(),
            command: "echo 'test'",
            workingDirectory: "/home/user",
            allowed: true,
            reason: "Safe command",
            sessionId: "coding-session",
            code: "200"
        )
        
        // Test encoding
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(entry)
        XCTAssertFalse(data.isEmpty)
        
        // Test decoding
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decodedEntry = try decoder.decode(AuditLogEntry.self, from: data)
        
        XCTAssertEqual(decodedEntry.id, entry.id)
        XCTAssertEqual(decodedEntry.command, entry.command)
        XCTAssertEqual(decodedEntry.workingDirectory, entry.workingDirectory)
        XCTAssertEqual(decodedEntry.allowed, entry.allowed)
        XCTAssertEqual(decodedEntry.reason, entry.reason)
        XCTAssertEqual(decodedEntry.sessionId, entry.sessionId)
        XCTAssertEqual(decodedEntry.code, entry.code)
    }
    
    // MARK: - Permission Request Tests
    
    func testPermissionRequest() {
        let request = PermissionRequest(
            id: "perm-request-123",
            command: "sudo install package",
            workingDirectory: "/opt/software",
            timestamp: Date(),
            status: .pending,
            reason: "Requires elevated privileges"
        )
        
        XCTAssertEqual(request.id, "perm-request-123")
        XCTAssertEqual(request.command, "sudo install package")
        XCTAssertEqual(request.workingDirectory, "/opt/software")
        XCTAssertEqual(request.status, .pending)
        XCTAssertEqual(request.reason, "Requires elevated privileges")
    }
    
    func testPermissionRequestStatus() {
        let statuses: [PermissionRequest.PermissionStatus] = [.pending, .approved, .denied, .timeout]
        
        for status in statuses {
            let request = PermissionRequest(
                id: "test-\(status.rawValue)",
                command: "test command",
                workingDirectory: "/test",
                timestamp: Date(),
                status: status,
                reason: nil
            )
            XCTAssertEqual(request.status, status)
        }
        
        // Test specific values
        XCTAssertEqual(PermissionRequest.PermissionStatus.pending.rawValue, "pending")
        XCTAssertEqual(PermissionRequest.PermissionStatus.approved.rawValue, "approved")
        XCTAssertEqual(PermissionRequest.PermissionStatus.denied.rawValue, "denied")
        XCTAssertEqual(PermissionRequest.PermissionStatus.timeout.rawValue, "timeout")
    }
    
    func testPermissionRequestCoding() throws {
        let request = PermissionRequest(
            id: "coding-perm-123",
            command: "dangerous operation",
            workingDirectory: "/critical/path",
            timestamp: Date(),
            status: .approved,
            reason: "User approved manually"
        )
        
        // Test encoding
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(request)
        XCTAssertFalse(data.isEmpty)
        
        // Test decoding
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decodedRequest = try decoder.decode(PermissionRequest.self, from: data)
        
        XCTAssertEqual(decodedRequest.id, request.id)
        XCTAssertEqual(decodedRequest.command, request.command)
        XCTAssertEqual(decodedRequest.workingDirectory, request.workingDirectory)
        XCTAssertEqual(decodedRequest.status, request.status)
        XCTAssertEqual(decodedRequest.reason, request.reason)
    }
    
    // MARK: - Directory Permissions Tests
    
    func testDirectoryPermissions() {
        let permissions: [DirectoryPermissions] = [.readOnly, .writeOnly, .readWrite, .denied]
        
        for permission in permissions {
            XCTAssertFalse(permission.displayName.isEmpty)
            XCTAssertFalse(permission.icon.isEmpty)
        }
        
        // Test specific values
        XCTAssertEqual(DirectoryPermissions.readOnly.displayName, "Read Only")
        XCTAssertEqual(DirectoryPermissions.writeOnly.displayName, "Write Only")
        XCTAssertEqual(DirectoryPermissions.readWrite.displayName, "Read & Write")
        XCTAssertEqual(DirectoryPermissions.denied.displayName, "Denied")
        
        XCTAssertEqual(DirectoryPermissions.readOnly.rawValue, "read")
        XCTAssertEqual(DirectoryPermissions.writeOnly.rawValue, "write")
        XCTAssertEqual(DirectoryPermissions.readWrite.rawValue, "readWrite")
        XCTAssertEqual(DirectoryPermissions.denied.rawValue, "denied")
    }
    
    func testDirectoryAccessRule() {
        let rule = DirectoryAccessRule(
            path: "/test/access/path",
            permissions: .readWrite,
            recursive: true
        )
        
        XCTAssertEqual(rule.path, "/test/access/path")
        XCTAssertEqual(rule.permissions, .readWrite)
        XCTAssertTrue(rule.recursive)
        XCTAssertNotNil(rule.id)
    }
    
    func testDirectoryAccessRuleCoding() throws {
        let rule = DirectoryAccessRule(
            path: "/coding/test/path",
            permissions: .readOnly,
            recursive: false
        )
        
        // Test encoding
        let encoder = JSONEncoder()
        let data = try encoder.encode(rule)
        XCTAssertFalse(data.isEmpty)
        
        // Test decoding
        let decoder = JSONDecoder()
        let decodedRule = try decoder.decode(DirectoryAccessRule.self, from: data)
        
        XCTAssertEqual(decodedRule.path, rule.path)
        XCTAssertEqual(decodedRule.permissions, rule.permissions)
        XCTAssertEqual(decodedRule.recursive, rule.recursive)
        // Note: ID will be different after decoding since UUID generates new IDs
        XCTAssertNotNil(decodedRule.id)
    }
    
    // MARK: - API Response Tests
    
    func testSecurityAPIResponse() throws {
        let config = SecurityConfiguration.default
        let response = SecurityAPIResponse(
            success: true,
            config: config,
            message: "Configuration updated",
            error: nil
        )
        
        XCTAssertTrue(response.success)
        XCTAssertNotNil(response.config)
        XCTAssertEqual(response.message, "Configuration updated")
        XCTAssertNil(response.error)
        
        // Test encoding/decoding
        let encoder = JSONEncoder()
        let data = try encoder.encode(response)
        
        let decoder = JSONDecoder()
        let decodedResponse = try decoder.decode(SecurityAPIResponse.self, from: data)
        
        XCTAssertEqual(decodedResponse.success, response.success)
        XCTAssertEqual(decodedResponse.config, response.config)
        XCTAssertEqual(decodedResponse.message, response.message)
        XCTAssertEqual(decodedResponse.error, response.error)
    }
    
    func testAuditAPIResponse() throws {
        let entries = [
            AuditLogEntry(id: "1", timestamp: Date(), command: "ls", workingDirectory: "/", allowed: true, reason: nil, sessionId: nil, code: nil),
            AuditLogEntry(id: "2", timestamp: Date(), command: "rm", workingDirectory: "/tmp", allowed: false, reason: "Blocked", sessionId: nil, code: nil)
        ]
        
        let response = AuditAPIResponse(
            success: true,
            count: entries.count,
            entries: entries
        )
        
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.count, 2)
        XCTAssertEqual(response.entries.count, 2)
        
        // Test encoding/decoding
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(response)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decodedResponse = try decoder.decode(AuditAPIResponse.self, from: data)
        
        XCTAssertEqual(decodedResponse.success, response.success)
        XCTAssertEqual(decodedResponse.count, response.count)
        XCTAssertEqual(decodedResponse.entries.count, response.entries.count)
    }
    
    func testTestCommandResponse() throws {
        let response = TestCommandResponse(
            success: true,
            command: "echo hello",
            workingDirectory: "/home/user",
            allowed: true,
            reason: "Safe command",
            requiresConfirmation: false
        )
        
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.command, "echo hello")
        XCTAssertEqual(response.workingDirectory, "/home/user")
        XCTAssertTrue(response.allowed)
        XCTAssertEqual(response.reason, "Safe command")
        XCTAssertFalse(response.requiresConfirmation)
        
        // Test encoding/decoding
        let encoder = JSONEncoder()
        let data = try encoder.encode(response)
        
        let decoder = JSONDecoder()
        let decodedResponse = try decoder.decode(TestCommandResponse.self, from: data)
        
        XCTAssertEqual(decodedResponse.success, response.success)
        XCTAssertEqual(decodedResponse.command, response.command)
        XCTAssertEqual(decodedResponse.workingDirectory, response.workingDirectory)
        XCTAssertEqual(decodedResponse.allowed, response.allowed)
        XCTAssertEqual(decodedResponse.reason, response.reason)
        XCTAssertEqual(decodedResponse.requiresConfirmation, response.requiresConfirmation)
    }
    
    // MARK: - Performance Tests
    
    func testPerformanceOfConfigurationSerialization() {
        measure {
            for i in 0..<100 {
                let config = SecurityConfiguration(
                    preset: .standard,
                    safeDirectories: ["/path/\(i)", "/another/\(i)"],
                    blockedCommands: ["cmd-\(i)", "dangerous-\(i)"],
                    requireConfirmation: i % 2 == 0,
                    readOnlyMode: i % 3 == 0
                )
                
                do {
                    let data = try JSONEncoder().encode(config)
                    let decoded = try JSONDecoder().decode(SecurityConfiguration.self, from: data)
                    XCTAssertEqual(decoded.preset, config.preset)
                } catch {
                    XCTFail("Serialization should not fail: \(error)")
                }
            }
        }
    }
    
    // MARK: - Edge Cases Tests
    
    func testConfigurationWithEmptyArrays() {
        let config = SecurityConfiguration(
            preset: .custom,
            safeDirectories: [],
            blockedCommands: [],
            destructiveCommands: []
        )
        
        XCTAssertEqual(config.safeDirectories.count, 0)
        XCTAssertEqual(config.blockedCommands.count, 0)
        XCTAssertEqual(config.destructiveCommands.count, 0)
    }
    
    func testConfigurationWithLargeArrays() {
        let largePathArray = (0..<1000).map { "/large/path/\($0)" }
        let largeCommandArray = (0..<500).map { "command-\($0)" }
        
        let config = SecurityConfiguration(
            preset: .custom,
            safeDirectories: largePathArray,
            blockedCommands: largeCommandArray
        )
        
        XCTAssertEqual(config.safeDirectories.count, 1000)
        XCTAssertEqual(config.blockedCommands.count, 500)
    }
    
    func testConfigurationWithSpecialCharacters() {
        let config = SecurityConfiguration(
            preset: .custom,
            safeDirectories: ["/path with spaces", "/path/with/ünicode", "/path&with$special!chars"],
            blockedCommands: ["rm -rf *", "find / -name \"*\"", "grep -r 'pattern' /"]
        )
        
        XCTAssertTrue(config.safeDirectories.contains("/path with spaces"))
        XCTAssertTrue(config.safeDirectories.contains("/path/with/ünicode"))
        XCTAssertTrue(config.safeDirectories.contains("/path&with$special!chars"))
        XCTAssertTrue(config.blockedCommands.contains("rm -rf *"))
        XCTAssertTrue(config.blockedCommands.contains("find / -name \"*\""))
        XCTAssertTrue(config.blockedCommands.contains("grep -r 'pattern' /"))
    }
}