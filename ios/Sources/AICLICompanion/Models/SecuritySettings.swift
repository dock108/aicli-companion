import Foundation

// MARK: - Security Preset
@available(iOS 16.0, macOS 13.0, *)
public enum SecurityPreset: String, CaseIterable, Codable {
    case unrestricted = "unrestricted"
    case standard = "standard"
    case restricted = "restricted"
    case custom = "custom"
    
    var displayName: String {
        switch self {
        case .unrestricted:
            return "Unrestricted"
        case .standard:
            return "Standard"
        case .restricted:
            return "Restricted"
        case .custom:
            return "Custom"
        }
    }
    
    var description: String {
        switch self {
        case .unrestricted:
            return "No restrictions - full access"
        case .standard:
            return "Balanced security - blocks dangerous commands"
        case .restricted:
            return "High security - read-only with minimal tools"
        case .custom:
            return "User-defined security settings"
        }
    }
    
    var icon: String {
        switch self {
        case .unrestricted:
            return "shield.slash"
        case .standard:
            return "shield"
        case .restricted:
            return "lock.shield"
        case .custom:
            return "slider.horizontal.3"
        }
    }
}

// MARK: - Security Configuration
@available(iOS 16.0, macOS 13.0, *)
public struct SecurityConfiguration: Codable, Equatable {
    var preset: SecurityPreset
    var safeDirectories: [String]
    var blockedCommands: [String]
    var destructiveCommands: [String]
    var requireConfirmation: Bool
    var maxFileSize: Int
    var readOnlyMode: Bool
    var enableAudit: Bool
    
    init(
        preset: SecurityPreset = .standard,
        safeDirectories: [String] = [],
        blockedCommands: [String] = [],
        destructiveCommands: [String] = ["rm -rf", "format", "diskutil erase"],
        requireConfirmation: Bool = true,
        maxFileSize: Int = 10485760, // 10MB
        readOnlyMode: Bool = false,
        enableAudit: Bool = true
    ) {
        self.preset = preset
        self.safeDirectories = safeDirectories
        self.blockedCommands = blockedCommands
        self.destructiveCommands = destructiveCommands
        self.requireConfirmation = requireConfirmation
        self.maxFileSize = maxFileSize
        self.readOnlyMode = readOnlyMode
        self.enableAudit = enableAudit
    }
    
    static var `default`: SecurityConfiguration {
        SecurityConfiguration()
    }
}

// MARK: - Directory Access Rule
@available(iOS 16.0, macOS 13.0, *)
public struct DirectoryAccessRule: Identifiable, Codable {
    public let id = UUID()
    var path: String
    var permissions: DirectoryPermissions
    var recursive: Bool
    
    init(path: String, permissions: DirectoryPermissions = .readWrite, recursive: Bool = true) {
        self.path = path
        self.permissions = permissions
        self.recursive = recursive
    }
}

// MARK: - Directory Permissions
@available(iOS 16.0, macOS 13.0, *)
public enum DirectoryPermissions: String, CaseIterable, Codable {
    case readOnly = "read"
    case writeOnly = "write"
    case readWrite = "readWrite"
    case denied = "denied"
    
    var displayName: String {
        switch self {
        case .readOnly:
            return "Read Only"
        case .writeOnly:
            return "Write Only"
        case .readWrite:
            return "Read & Write"
        case .denied:
            return "Denied"
        }
    }
    
    var icon: String {
        switch self {
        case .readOnly:
            return "doc.text"
        case .writeOnly:
            return "pencil"
        case .readWrite:
            return "pencil.and.outline"
        case .denied:
            return "xmark.circle"
        }
    }
}

// MARK: - Audit Log Entry
@available(iOS 16.0, macOS 13.0, *)
public struct AuditLogEntry: Identifiable, Codable {
    public let id: String
    let timestamp: Date
    let command: String
    let workingDirectory: String?
    let allowed: Bool
    let reason: String?
    let sessionId: String?
    let code: String?
    
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: timestamp)
    }
    
    var statusIcon: String {
        allowed ? "checkmark.circle.fill" : "xmark.circle.fill"
    }
    
    var statusColor: String {
        allowed ? "green" : "red"
    }
}

// MARK: - Permission Request
@available(iOS 16.0, macOS 13.0, *)
public struct PermissionRequest: Identifiable, Codable {
    public let id: String
    let command: String
    let workingDirectory: String
    let timestamp: Date
    var status: PermissionStatus
    var reason: String?
    
    enum PermissionStatus: String, Codable {
        case pending = "pending"
        case approved = "approved"
        case denied = "denied"
        case timeout = "timeout"
    }
}

// MARK: - Security API Response
@available(iOS 16.0, macOS 13.0, *)
struct SecurityAPIResponse: Codable {
    let success: Bool
    let config: SecurityConfiguration?
    let message: String?
    let error: String?
}

// MARK: - Audit API Response
@available(iOS 16.0, macOS 13.0, *)
struct AuditAPIResponse: Codable {
    let success: Bool
    let count: Int
    let entries: [AuditLogEntry]
}

// MARK: - Test Command Response
@available(iOS 16.0, macOS 13.0, *)
struct TestCommandResponse: Codable {
    let success: Bool
    let command: String
    let workingDirectory: String
    let allowed: Bool
    let reason: String?
    let requiresConfirmation: Bool
}