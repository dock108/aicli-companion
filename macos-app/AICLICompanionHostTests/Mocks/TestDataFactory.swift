//
//  TestDataFactory.swift
//  AICLICompanionHostTests
//
//  Factory for generating consistent test data
//

import Foundation
@testable import AICLICompanionHost

class TestDataFactory {

    // MARK: - LogEntry Factory

    static func createLogEntry(
        level: LogLevel = .info,
        message: String = "Test log message",
        category: String = "Test"
    ) -> LogEntry {
        return LogEntry(
            level: level,
            message: message,
            category: category
        )
    }

    static func createLogEntries(count: Int) -> [LogEntry] {
        return (0..<count).map { index in
            let levels: [LogLevel] = [.debug, .info, .warning, .error]
            let level = levels[index % levels.count]
            return createLogEntry(
                level: level,
                message: "Test log message \(index + 1)"
            )
        }
    }

    // MARK: - Session Factory

    static func createSession(
        sessionId: String? = nil,
        deviceName: String = "Test Device",
        connectedAt: Date = Date(),
        signalStrength: Double = 0.8
    ) -> Session {
        return Session(
            sessionId: sessionId ?? UUID().uuidString,
            deviceName: deviceName,
            connectedAt: connectedAt,
            signalStrength: signalStrength
        )
    }

    static func createSessions(count: Int) -> [Session] {
        return (0..<count).map { index in
            createSession(
                sessionId: "session-\(index + 1)",
                deviceName: "Device \(index + 1)",
                signalStrength: Double(index % 10) / 10.0
            )
        }
    }

    // MARK: - HealthResponse Factory

    static func createHealthResponse(
        status: String = "ok",
        uptime: Double = 3600.0,
        sessions: Int = 2
    ) -> HealthResponse {
        return HealthResponse(
            status: status,
            uptime: uptime,
            sessions: sessions
        )
    }

    // MARK: - ServerStatus Factory

    static func createServerStatus(
        running: Bool = true,
        health: String = "healthy",
        port: Int = 3001
    ) -> ServerStatus {
        return ServerStatus(
            running: running,
            health: health,
            port: port
        )
    }

    // MARK: - SessionData Factory

    static func createSessionData(
        sessionId: String? = nil,
        deviceId: String = "test-device-001"
    ) -> SessionData {
        return SessionData(
            sessionId: sessionId ?? UUID().uuidString,
            deviceId: deviceId
        )
    }

    static func createSessionInfo(sessions: [SessionData]? = nil) -> SessionInfo {
        let defaultSessions = sessions ?? [
            createSessionData(sessionId: "session-1", deviceId: "device-1"),
            createSessionData(sessionId: "session-2", deviceId: "device-2")
        ]
        return SessionInfo(sessions: defaultSessions)
    }

    // MARK: - ServerError Factory

    static func createServerError(type: ServerErrorType = .processSpawnFailed) -> ServerError {
        switch type {
        case .processSpawnFailed:
            return .processSpawnFailed
        case .networkError(let message):
            return .networkError(message)
        case .authenticationFailed:
            return .authenticationFailed
        case .portInUse:
            return .portInUse
        case .serverNotRunning:
            return .serverNotRunning
        case .serverAlreadyRunning:
            return .serverAlreadyRunning
        case .invalidDirectory:
            return .invalidDirectory
        case .nodeNotFound:
            return .nodeNotFound
        case .npmNotFound:
            return .npmNotFound
        case .keychainError(let message):
            return .keychainError(message)
        case .installationFailed(let message):
            return .installationFailed(message)
        case .tunnelError(let message):
            return .tunnelError(message)
        case .restartTimeout:
            return .restartTimeout
        }
    }

    // MARK: - Settings Configuration Factory

    static func createSettingsConfiguration(
        port: Int = 3001,
        requireAuth: Bool = true,
        enableTunnel: Bool = false
    ) -> [String: Any] {
        return [
            "serverPort": port,
            "autoStartServer": false,
            "autoRestartOnCrash": true,
            "launchAtLogin": false,
            "showDockIcon": false,
            "enableNotifications": true,
            "enableSounds": true,
            "logLevel": "info",
            "maxLogEntries": 1000,
            "enableBonjour": true,
            "theme": "system",
            "requireAuthentication": requireAuth,
            "enableTouchID": true,
            "enableTunnel": enableTunnel,
            "tunnelProvider": "ngrok",
            "ngrokAuthToken": enableTunnel ? "test-token-123" : "",
            "defaultProjectDirectory": "",
            "serverCommand": "npm start",
            "serverDirectory": "",
            "nodeExecutable": "",
            "npmExecutable": ""
        ]
    }

    // MARK: - Auth Token Factory

    static func createAuthToken() -> String {
        return UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    // MARK: - URL Factory

    static func createWebSocketURL(
        host: String = "localhost",
        port: Int = 3001,
        token: String? = nil,
        useSSL: Bool = false
    ) -> String {
        let scheme = useSSL ? "wss" : "ws"
        var url = "\(scheme)://\(host):\(port)/ws"

        if let token = token {
            url += "?token=\(token)"
        }

        return url
    }

    static func createHTTPURL(
        host: String = "localhost",
        port: Int = 3001,
        path: String = "/",
        useSSL: Bool = false
    ) -> String {
        let scheme = useSSL ? "https" : "http"
        return "\(scheme)://\(host):\(port)\(path)"
    }
}

// MARK: - Helper Enums for Factory

enum ServerErrorType {
    case processSpawnFailed
    case networkError(String)
    case authenticationFailed
    case portInUse
    case serverNotRunning
    case serverAlreadyRunning
    case invalidDirectory
    case nodeNotFound
    case npmNotFound
    case keychainError(String)
    case installationFailed(String)
    case tunnelError(String)
    case restartTimeout
}