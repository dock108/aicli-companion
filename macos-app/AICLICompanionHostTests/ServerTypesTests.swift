//
//  ServerTypesTests.swift
//  AICLICompanionHostTests
//
//  Unit tests for ServerTypes models
//

import XCTest
import SwiftUI
@testable import AICLICompanionHost

final class ServerTypesTests: XCTestCase {
    // MARK: - ServerHealth Tests

    func testServerHealthCases() throws {
        let healthy = ServerHealth.healthy
        let unhealthy = ServerHealth.unhealthy
        let unknown = ServerHealth.unknown

        // Verify they are distinct
        XCTAssertNotEqual(healthy, unhealthy)
        XCTAssertNotEqual(healthy, unknown)
        XCTAssertNotEqual(unhealthy, unknown)
    }

    // MARK: - ServerError Tests

    func testServerErrorDescriptions() throws {
        // Test each error case has appropriate description
        XCTAssertEqual(ServerError.serverNotRunning.errorDescription, "Server is not running")
        XCTAssertEqual(ServerError.serverAlreadyRunning.errorDescription, "Server is already running")
        XCTAssertEqual(ServerError.invalidDirectory.errorDescription, "Invalid server directory")
        XCTAssertEqual(ServerError.portInUse.errorDescription, "Port is already in use")
        XCTAssertEqual(ServerError.processSpawnFailed.errorDescription, "Failed to start server process")
        XCTAssertEqual(ServerError.authenticationFailed.errorDescription, "Authentication failed")
        XCTAssertEqual(ServerError.nodeNotFound.errorDescription, "Node.js executable not found")
        XCTAssertEqual(ServerError.npmNotFound.errorDescription, "npm executable not found")
        XCTAssertEqual(ServerError.restartTimeout.errorDescription, "Server restart timed out")
    }

    func testServerErrorWithAssociatedValues() throws {
        let networkError = ServerError.networkError("Connection failed")
        XCTAssertEqual(networkError.errorDescription, "Network error: Connection failed")

        let keychainError = ServerError.keychainError("Access denied")
        XCTAssertEqual(keychainError.errorDescription, "Keychain error: Access denied")

        let installationError = ServerError.installationFailed("Missing dependencies")
        XCTAssertEqual(installationError.errorDescription, "Installation failed: Missing dependencies")

        let tunnelError = ServerError.tunnelError("Invalid auth token")
        XCTAssertEqual(tunnelError.errorDescription, "Tunnel error: Invalid auth token")
    }

    // MARK: - Session Tests

    func testSessionCreation() throws {
        let session = Session(
            sessionId: "test-123",
            deviceName: "Test Device",
            connectedAt: Date(),
            signalStrength: 0.75
        )

        XCTAssertEqual(session.sessionId, "test-123")
        XCTAssertEqual(session.deviceName, "Test Device")
        XCTAssertEqual(session.signalStrength, 0.75)
        XCTAssertNotNil(session.id) // UUID should be auto-generated
    }

    func testSessionIdentifiable() throws {
        let session1 = Session(
            sessionId: "test-1",
            deviceName: "Device 1",
            connectedAt: Date(),
            signalStrength: 0.5
        )

        let session2 = Session(
            sessionId: "test-2",
            deviceName: "Device 2",
            connectedAt: Date(),
            signalStrength: 0.8
        )

        // Each session should have unique ID
        XCTAssertNotEqual(session1.id, session2.id)
    }

    func testSessionSignalStrengthBounds() throws {
        // Test with various signal strengths
        let weakSignal = Session(
            sessionId: "weak",
            deviceName: "Weak Device",
            connectedAt: Date(),
            signalStrength: 0.1
        )

        let strongSignal = Session(
            sessionId: "strong",
            deviceName: "Strong Device",
            connectedAt: Date(),
            signalStrength: 1.0
        )

        XCTAssertEqual(weakSignal.signalStrength, 0.1)
        XCTAssertEqual(strongSignal.signalStrength, 1.0)
    }

    // MARK: - LogEntry Tests

    func testLogEntryCreation() throws {
        let logEntry = LogEntry(
            level: .info,
            message: "Test message",
            category: "Test"
        )

        XCTAssertNotNil(logEntry.id)
        XCTAssertNotNil(logEntry.timestamp)
        XCTAssertEqual(logEntry.level, .info)
        XCTAssertEqual(logEntry.message, "Test message")
        XCTAssertEqual(logEntry.category, "Test")
    }

    func testLogEntryDefaultCategory() throws {
        let logEntry = LogEntry(
            level: .debug,
            message: "Debug message"
        )

        XCTAssertEqual(logEntry.category, "")
    }

    func testLogEntryIdentifiable() throws {
        let log1 = LogEntry(level: .info, message: "Message 1")
        let log2 = LogEntry(level: .info, message: "Message 2")

        // Each log entry should have unique ID
        XCTAssertNotEqual(log1.id, log2.id)
    }

    func testLogEntryTimestamp() throws {
        let before = Date()
        let logEntry = LogEntry(level: .info, message: "Test")
        let after = Date()

        // Timestamp should be between before and after
        XCTAssertGreaterThanOrEqual(logEntry.timestamp, before)
        XCTAssertLessThanOrEqual(logEntry.timestamp, after)
    }

    // MARK: - LogLevel Tests

    func testLogLevelCases() throws {
        let levels = LogLevel.allCases

        XCTAssertEqual(levels.count, 4)
        XCTAssertTrue(levels.contains(.debug))
        XCTAssertTrue(levels.contains(.info))
        XCTAssertTrue(levels.contains(.warning))
        XCTAssertTrue(levels.contains(.error))
    }

    func testLogLevelIcons() throws {
        XCTAssertEqual(LogLevel.debug.icon, "ladybug")
        XCTAssertEqual(LogLevel.info.icon, "info.circle")
        XCTAssertEqual(LogLevel.warning.icon, "exclamationmark.triangle")
        XCTAssertEqual(LogLevel.error.icon, "xmark.circle")
    }

    func testLogLevelColors() throws {
        // Test that each level has a distinct color
        XCTAssertEqual(LogLevel.debug.color, Color(.systemGray))
        XCTAssertEqual(LogLevel.info.color, Color(.systemBlue))
        XCTAssertEqual(LogLevel.warning.color, Color(.systemOrange))
        XCTAssertEqual(LogLevel.error.color, Color(.systemRed))
    }

    func testLogLevelDisplayNames() throws {
        XCTAssertEqual(LogLevel.debug.displayName, "Debug")
        XCTAssertEqual(LogLevel.info.displayName, "Info")
        XCTAssertEqual(LogLevel.warning.displayName, "Warning")
        XCTAssertEqual(LogLevel.error.displayName, "Error")
    }

    // MARK: - HealthResponse Tests

    func testHealthResponseCodable() throws {
        let healthResponse = HealthResponse(
            status: "ok",
            uptime: 3600.5,
            sessions: 3
        )

        // Encode
        let encoder = JSONEncoder()
        let data = try encoder.encode(healthResponse)

        // Decode
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(HealthResponse.self, from: data)

        XCTAssertEqual(decoded.status, "ok")
        XCTAssertEqual(decoded.uptime, 3600.5)
        XCTAssertEqual(decoded.sessions, 3)
    }

    func testHealthResponseFromJSON() throws {
        let json = """
        {
            "status": "healthy",
            "uptime": 7200.0,
            "sessions": 5
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let healthResponse = try decoder.decode(HealthResponse.self, from: json)

        XCTAssertEqual(healthResponse.status, "healthy")
        XCTAssertEqual(healthResponse.uptime, 7200.0)
        XCTAssertEqual(healthResponse.sessions, 5)
    }

    // MARK: - ServerStatus Tests

    func testServerStatusCodable() throws {
        let serverStatus = ServerStatus(
            running: true,
            health: "healthy",
            port: 3001
        )

        // Encode
        let encoder = JSONEncoder()
        let data = try encoder.encode(serverStatus)

        // Decode
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ServerStatus.self, from: data)

        XCTAssertTrue(decoded.running)
        XCTAssertEqual(decoded.health, "healthy")
        XCTAssertEqual(decoded.port, 3001)
    }

    // MARK: - SessionData Tests

    func testSessionDataCodable() throws {
        let sessionData = SessionData(
            sessionId: "session-abc",
            deviceId: "device-123"
        )

        // Encode
        let encoder = JSONEncoder()
        let data = try encoder.encode(sessionData)

        // Decode
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SessionData.self, from: data)

        XCTAssertEqual(decoded.sessionId, "session-abc")
        XCTAssertEqual(decoded.deviceId, "device-123")
    }

    // MARK: - SessionInfo Tests

    func testSessionInfoCodable() throws {
        let sessions = [
            SessionData(sessionId: "session-1", deviceId: "device-1"),
            SessionData(sessionId: "session-2", deviceId: "device-2"),
            SessionData(sessionId: "session-3", deviceId: "device-3")
        ]

        let sessionInfo = SessionInfo(sessions: sessions)

        // Encode
        let encoder = JSONEncoder()
        let data = try encoder.encode(sessionInfo)

        // Decode
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SessionInfo.self, from: data)

        XCTAssertEqual(decoded.sessions.count, 3)
        XCTAssertEqual(decoded.sessions[0].sessionId, "session-1")
        XCTAssertEqual(decoded.sessions[1].deviceId, "device-2")
        XCTAssertEqual(decoded.sessions[2].sessionId, "session-3")
    }

    func testSessionInfoEmptySessions() throws {
        let sessionInfo = SessionInfo(sessions: [])

        // Encode
        let encoder = JSONEncoder()
        let data = try encoder.encode(sessionInfo)

        // Decode
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SessionInfo.self, from: data)

        XCTAssertTrue(decoded.sessions.isEmpty)
    }
}
