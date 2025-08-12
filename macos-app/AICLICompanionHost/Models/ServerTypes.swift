//
//  ServerTypes.swift
//  AICLICompanionHost
//
//  Supporting types for ServerManager
//

import Foundation
import SwiftUI

// MARK: - Server Health
enum ServerHealth {
    case healthy
    case unhealthy
    case unknown
}

// MARK: - Server Errors
enum ServerError: LocalizedError {
    case serverNotRunning
    case serverAlreadyRunning
    case invalidDirectory
    case portInUse
    case processSpawnFailed
    case authenticationFailed
    case networkError(String)
    case nodeNotFound
    case npmNotFound
    case keychainError(String)
    case installationFailed(String)
    case tunnelError(String)
    case restartTimeout

    var errorDescription: String? {
        switch self {
        case .serverNotRunning:
            return "Server is not running"
        case .serverAlreadyRunning:
            return "Server is already running"
        case .invalidDirectory:
            return "Invalid server directory"
        case .portInUse:
            return "Port is already in use"
        case .processSpawnFailed:
            return "Failed to start server process"
        case .authenticationFailed:
            return "Authentication failed"
        case .networkError(let message):
            return "Network error: \(message)"
        case .nodeNotFound:
            return "Node.js executable not found"
        case .npmNotFound:
            return "npm executable not found"
        case .keychainError(let message):
            return "Keychain error: \(message)"
        case .installationFailed(let message):
            return "Installation failed: \(message)"
        case .tunnelError(let message):
            return "Tunnel error: \(message)"
        case .restartTimeout:
            return "Server restart timed out"
        }
    }
}

// MARK: - Session Model
struct Session: Identifiable {
    let id = UUID()
    let sessionId: String
    let deviceName: String
    let connectedAt: Date
    let signalStrength: Double

    // New feature tracking
    var hasAttachments: Bool = false
    var attachmentCount: Int = 0
    var autoResponseActive: Bool = false
    var autoResponseIteration: Int = 0
    var isThinking: Bool = false
    var thinkingActivity: String?
    var thinkingDuration: Int = 0
    var tokenCount: Int = 0
}

// MARK: - Log Entry
struct LogEntry: Identifiable {
    let id: UUID
    let timestamp: Date
    let level: LogLevel
    let message: String
    let category: String

    init(level: LogLevel, message: String, category: String = "") {
        self.id = UUID()
        self.timestamp = Date()
        self.level = level
        self.message = message
        self.category = category
    }
}

enum LogLevel: CaseIterable {
    case debug
    case info
    case warning
    case error

    var icon: String {
        switch self {
        case .debug: return "ladybug"
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .debug: return Color(.systemGray)
        case .info: return Color(.systemBlue)
        case .warning: return Color(.systemOrange)
        case .error: return Color(.systemRed)
        }
    }

    var displayName: String {
        switch self {
        case .debug: return "Debug"
        case .info: return "Info"
        case .warning: return "Warning"
        case .error: return "Error"
        }
    }
}

// MARK: - API Response Types
struct HealthResponse: Codable {
    let status: String
    let uptime: Double
    let sessions: Int
}

struct ServerStatus: Codable {
    let running: Bool
    let health: String
    let port: Int
}

struct SessionData: Codable {
    let sessionId: String
    let deviceId: String
}

struct SessionInfo: Codable {
    let sessions: [SessionData]
}
