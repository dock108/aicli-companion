import XCTest
@testable import AICLICompanion

@available(iOS 17.0, macOS 14.0, *)
final class SecuritySettingsTests: XCTestCase {
    // MARK: - SecurityPreset Tests
    
    func testSecurityPresetRawValues() {
        XCTAssertEqual(SecurityPreset.unrestricted.rawValue, "unrestricted")
        XCTAssertEqual(SecurityPreset.standard.rawValue, "standard")
        XCTAssertEqual(SecurityPreset.restricted.rawValue, "restricted")
        XCTAssertEqual(SecurityPreset.custom.rawValue, "custom")
    }
    
    func testSecurityPresetAllCases() {
        let allCases = SecurityPreset.allCases
        XCTAssertEqual(allCases.count, 4)
        XCTAssertTrue(allCases.contains(.unrestricted))
        XCTAssertTrue(allCases.contains(.standard))
        XCTAssertTrue(allCases.contains(.restricted))
        XCTAssertTrue(allCases.contains(.custom))
    }
    
    func testSecurityPresetDisplayNames() {
        XCTAssertEqual(SecurityPreset.unrestricted.displayName, "Unrestricted")
        XCTAssertEqual(SecurityPreset.standard.displayName, "Standard")
        XCTAssertEqual(SecurityPreset.restricted.displayName, "Restricted")
        XCTAssertEqual(SecurityPreset.custom.displayName, "Custom")
    }
    
    func testSecurityPresetDescriptions() {
        XCTAssertEqual(SecurityPreset.unrestricted.description, "No restrictions - full access")
        XCTAssertEqual(SecurityPreset.standard.description, "Balanced security - blocks dangerous commands")
        XCTAssertEqual(SecurityPreset.restricted.description, "High security - read-only with minimal tools")
        XCTAssertEqual(SecurityPreset.custom.description, "User-defined security settings")
    }
    
    func testSecurityPresetIcons() {
        XCTAssertEqual(SecurityPreset.unrestricted.icon, "shield.slash")
        XCTAssertEqual(SecurityPreset.standard.icon, "shield")
        XCTAssertEqual(SecurityPreset.restricted.icon, "lock.shield")
        XCTAssertEqual(SecurityPreset.custom.icon, "slider.horizontal.3")
    }
    
    func testSecurityPresetCodable() throws {
        let presets: [SecurityPreset] = [.unrestricted, .standard, .restricted, .custom]
        
        for preset in presets {
            let encoder = JSONEncoder()
            let data = try encoder.encode(preset)
            
            let decoder = JSONDecoder()
            let decoded = try decoder.decode(SecurityPreset.self, from: data)
            
            XCTAssertEqual(decoded, preset)
        }
    }
    
    // MARK: - SecurityConfiguration Tests
    
    func testSecurityConfigurationInitialization() {
        let config = SecurityConfiguration(
            preset: .restricted,
            safeDirectories: ["/Users/test", "/tmp"],
            blockedCommands: ["rm", "sudo"],
            destructiveCommands: ["format", "dd"],
            requireConfirmation: true,
            maxFileSize: 5242880,
            readOnlyMode: true,
            enableAudit: true
        )
        
        XCTAssertEqual(config.preset, .restricted)
        XCTAssertEqual(config.safeDirectories, ["/Users/test", "/tmp"])
        XCTAssertEqual(config.blockedCommands, ["rm", "sudo"])
        XCTAssertEqual(config.destructiveCommands, ["format", "dd"])
        XCTAssertTrue(config.requireConfirmation)
        XCTAssertEqual(config.maxFileSize, 5242880)
        XCTAssertTrue(config.readOnlyMode)
        XCTAssertTrue(config.enableAudit)
    }
    
    func testSecurityConfigurationDefaults() {
        let config = SecurityConfiguration()
        
        XCTAssertEqual(config.preset, .standard)
        XCTAssertTrue(config.safeDirectories.isEmpty)
        XCTAssertTrue(config.blockedCommands.isEmpty)
        XCTAssertEqual(config.destructiveCommands, ["rm -rf", "format", "diskutil erase"])
        XCTAssertTrue(config.requireConfirmation)
        XCTAssertEqual(config.maxFileSize, 10485760) // 10MB
        XCTAssertFalse(config.readOnlyMode)
        XCTAssertTrue(config.enableAudit)
    }
    
    func testSecurityConfigurationStaticDefault() {
        let config = SecurityConfiguration.default
        
        XCTAssertEqual(config.preset, .standard)
        XCTAssertTrue(config.requireConfirmation)
        XCTAssertEqual(config.maxFileSize, 10485760)
    }
    
    func testSecurityConfigurationEquality() {
        let config1 = SecurityConfiguration(
            preset: .standard,
            safeDirectories: ["/test"],
            requireConfirmation: true
        )
        
        let config2 = SecurityConfiguration(
            preset: .standard,
            safeDirectories: ["/test"],
            requireConfirmation: true
        )
        
        let config3 = SecurityConfiguration(
            preset: .restricted,
            safeDirectories: ["/test"],
            requireConfirmation: true
        )
        
        XCTAssertEqual(config1, config2)
        XCTAssertNotEqual(config1, config3)
    }
    
    func testSecurityConfigurationCodable() throws {
        let original = SecurityConfiguration(
            preset: .custom,
            safeDirectories: ["/home", "/projects"],
            blockedCommands: ["curl", "wget"],
            destructiveCommands: ["rm -rf /"],
            requireConfirmation: false,
            maxFileSize: 1024,
            readOnlyMode: true,
            enableAudit: false
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SecurityConfiguration.self, from: data)
        
        XCTAssertEqual(decoded, original)
    }
    
    // MARK: - DirectoryPermissions Tests
    
    func testDirectoryPermissionsRawValues() {
        XCTAssertEqual(DirectoryPermissions.readOnly.rawValue, "read")
        XCTAssertEqual(DirectoryPermissions.writeOnly.rawValue, "write")
        XCTAssertEqual(DirectoryPermissions.readWrite.rawValue, "readWrite")
        XCTAssertEqual(DirectoryPermissions.denied.rawValue, "denied")
    }
    
    func testDirectoryPermissionsAllCases() {
        let allCases = DirectoryPermissions.allCases
        XCTAssertEqual(allCases.count, 4)
        XCTAssertTrue(allCases.contains(.readOnly))
        XCTAssertTrue(allCases.contains(.writeOnly))
        XCTAssertTrue(allCases.contains(.readWrite))
        XCTAssertTrue(allCases.contains(.denied))
    }
    
    func testDirectoryPermissionsDisplayNames() {
        XCTAssertEqual(DirectoryPermissions.readOnly.displayName, "Read Only")
        XCTAssertEqual(DirectoryPermissions.writeOnly.displayName, "Write Only")
        XCTAssertEqual(DirectoryPermissions.readWrite.displayName, "Read & Write")
        XCTAssertEqual(DirectoryPermissions.denied.displayName, "Denied")
    }
    
    func testDirectoryPermissionsIcons() {
        XCTAssertEqual(DirectoryPermissions.readOnly.icon, "doc.text")
        XCTAssertEqual(DirectoryPermissions.writeOnly.icon, "pencil")
        XCTAssertEqual(DirectoryPermissions.readWrite.icon, "pencil.and.outline")
        XCTAssertEqual(DirectoryPermissions.denied.icon, "xmark.circle")
    }
    
    // MARK: - DirectoryAccessRule Tests
    
    func testDirectoryAccessRuleInitialization() {
        let rule = DirectoryAccessRule(
            path: "/Users/test/Documents",
            permissions: .readOnly,
            recursive: false
        )
        
        XCTAssertNotNil(rule.id)
        XCTAssertEqual(rule.path, "/Users/test/Documents")
        XCTAssertEqual(rule.permissions, .readOnly)
        XCTAssertFalse(rule.recursive)
    }
    
    func testDirectoryAccessRuleDefaults() {
        let rule = DirectoryAccessRule(path: "/tmp")
        
        XCTAssertEqual(rule.path, "/tmp")
        XCTAssertEqual(rule.permissions, .readWrite)
        XCTAssertTrue(rule.recursive)
    }
    
    func testDirectoryAccessRuleCodable() throws {
        let original = DirectoryAccessRule(
            path: "/var/log",
            permissions: .denied,
            recursive: true
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DirectoryAccessRule.self, from: data)
        
        XCTAssertEqual(decoded.path, original.path)
        XCTAssertEqual(decoded.permissions, original.permissions)
        XCTAssertEqual(decoded.recursive, original.recursive)
    }
    
    // MARK: - AuditLogEntry Tests
    
    func testAuditLogEntryInitialization() {
        let timestamp = Date()
        let entry = AuditLogEntry(
            id: "audit-001",
            timestamp: timestamp,
            command: "ls -la",
            workingDirectory: "/Users/test",
            allowed: true,
            reason: "Safe command",
            sessionId: "session-123",
            code: "0"
        )
        
        XCTAssertEqual(entry.id, "audit-001")
        XCTAssertEqual(entry.timestamp, timestamp)
        XCTAssertEqual(entry.command, "ls -la")
        XCTAssertEqual(entry.workingDirectory, "/Users/test")
        XCTAssertTrue(entry.allowed)
        XCTAssertEqual(entry.reason, "Safe command")
        XCTAssertEqual(entry.sessionId, "session-123")
        XCTAssertEqual(entry.code, "0")
    }
    
    func testAuditLogEntryStatusIcon() {
        let allowedEntry = AuditLogEntry(
            id: "1",
            timestamp: Date(),
            command: "test",
            workingDirectory: nil,
            allowed: true,
            reason: nil,
            sessionId: nil,
            code: nil
        )
        XCTAssertEqual(allowedEntry.statusIcon, "checkmark.circle.fill")
        
        let deniedEntry = AuditLogEntry(
            id: "2",
            timestamp: Date(),
            command: "test",
            workingDirectory: nil,
            allowed: false,
            reason: nil,
            sessionId: nil,
            code: nil
        )
        XCTAssertEqual(deniedEntry.statusIcon, "xmark.circle.fill")
    }
    
    func testAuditLogEntryStatusColor() {
        let allowedEntry = AuditLogEntry(
            id: "1",
            timestamp: Date(),
            command: "test",
            workingDirectory: nil,
            allowed: true,
            reason: nil,
            sessionId: nil,
            code: nil
        )
        XCTAssertEqual(allowedEntry.statusColor, "green")
        
        let deniedEntry = AuditLogEntry(
            id: "2",
            timestamp: Date(),
            command: "test",
            workingDirectory: nil,
            allowed: false,
            reason: nil,
            sessionId: nil,
            code: nil
        )
        XCTAssertEqual(deniedEntry.statusColor, "red")
    }
    
    func testAuditLogEntryFormattedTime() {
        let entry = AuditLogEntry(
            id: "1",
            timestamp: Date(),
            command: "test",
            workingDirectory: nil,
            allowed: true,
            reason: nil,
            sessionId: nil,
            code: nil
        )
        
        // Just verify the formatted time is not empty
        XCTAssertFalse(entry.formattedTime.isEmpty)
    }
    
    // MARK: - PermissionRequest Tests
    
    func testPermissionRequestInitialization() {
        let timestamp = Date()
        let request = PermissionRequest(
            id: "req-001",
            command: "rm file.txt",
            workingDirectory: "/tmp",
            timestamp: timestamp,
            status: .pending,
            reason: "Deleting temporary file"
        )
        
        XCTAssertEqual(request.id, "req-001")
        XCTAssertEqual(request.command, "rm file.txt")
        XCTAssertEqual(request.workingDirectory, "/tmp")
        XCTAssertEqual(request.timestamp, timestamp)
        XCTAssertEqual(request.status, .pending)
        XCTAssertEqual(request.reason, "Deleting temporary file")
    }
    
    func testPermissionStatusRawValues() {
        XCTAssertEqual(PermissionRequest.PermissionStatus.pending.rawValue, "pending")
        XCTAssertEqual(PermissionRequest.PermissionStatus.approved.rawValue, "approved")
        XCTAssertEqual(PermissionRequest.PermissionStatus.denied.rawValue, "denied")
        XCTAssertEqual(PermissionRequest.PermissionStatus.timeout.rawValue, "timeout")
    }
    
    func testPermissionRequestCodable() throws {
        let original = PermissionRequest(
            id: "req-002",
            command: "sudo apt update",
            workingDirectory: "/",
            timestamp: Date(),
            status: .denied,
            reason: "Sudo not allowed"
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(PermissionRequest.self, from: data)
        
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.command, original.command)
        XCTAssertEqual(decoded.workingDirectory, original.workingDirectory)
        XCTAssertEqual(decoded.status, original.status)
        XCTAssertEqual(decoded.reason, original.reason)
    }
    
    // MARK: - API Response Tests
    
    func testSecurityAPIResponseSuccess() {
        let config = SecurityConfiguration.default
        let response = SecurityAPIResponse(
            success: true,
            config: config,
            message: "Configuration loaded",
            error: nil
        )
        
        XCTAssertTrue(response.success)
        XCTAssertNotNil(response.config)
        XCTAssertEqual(response.message, "Configuration loaded")
        XCTAssertNil(response.error)
    }
    
    func testSecurityAPIResponseFailure() {
        let response = SecurityAPIResponse(
            success: false,
            config: nil,
            message: nil,
            error: "Failed to load configuration"
        )
        
        XCTAssertFalse(response.success)
        XCTAssertNil(response.config)
        XCTAssertNil(response.message)
        XCTAssertEqual(response.error, "Failed to load configuration")
    }
    
    func testAuditAPIResponse() {
        let entry = AuditLogEntry(
            id: "log-1",
            timestamp: Date(),
            command: "echo test",
            workingDirectory: "/tmp",
            allowed: true,
            reason: nil,
            sessionId: "session-1",
            code: "0"
        )
        
        let response = AuditAPIResponse(
            success: true,
            count: 1,
            entries: [entry]
        )
        
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.count, 1)
        XCTAssertEqual(response.entries.count, 1)
        XCTAssertEqual(response.entries[0].id, "log-1")
    }
    
    func testTestCommandResponse() {
        let response = TestCommandResponse(
            success: true,
            command: "cat file.txt",
            workingDirectory: "/home",
            allowed: true,
            reason: "Safe read operation",
            requiresConfirmation: false
        )
        
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.command, "cat file.txt")
        XCTAssertEqual(response.workingDirectory, "/home")
        XCTAssertTrue(response.allowed)
        XCTAssertEqual(response.reason, "Safe read operation")
        XCTAssertFalse(response.requiresConfirmation)
    }
}
