//
//  AICLICompanionHostTests.swift
//  AICLICompanionHostTests
//
//  Basic tests for AICLI Companion Host macOS app
//

import XCTest
@testable import AICLICompanionHost

final class AICLICompanionHostTests: XCTestCase {

    @MainActor
    func testServerManagerInitialization() throws {
        let manager = ServerManager.shared

        XCTAssertNotNil(manager)
        XCTAssertFalse(manager.isRunning)
        XCTAssertEqual(manager.port, SettingsManager.shared.serverPort)
        // localIP is set dynamically, just check it's not empty
        XCTAssertFalse(manager.localIP.isEmpty)
    }

    @MainActor
    func testSettingsManagerInitialization() throws {
        let settings = SettingsManager.shared

        XCTAssertNotNil(settings)
        // requireAuthentication may be true or false, just verify it can be accessed
        _ = settings.requireAuthentication
    }

    func testKeychainManagerInitialization() throws {
        let keychain = KeychainManager.shared

        XCTAssertNotNil(keychain)
        // Test keychain operations don't crash
        _ = keychain.getAuthToken()
    }

    @MainActor
    func testNetworkMonitorInitialization() throws {
        let monitor = NetworkMonitor.shared

        XCTAssertNotNil(monitor)
        XCTAssertFalse(monitor.localIP.isEmpty)
    }

    func testLogEntryCreation() throws {
        let logEntry = LogEntry(
            level: .info,
            message: "Test message"
        )

        XCTAssertNotNil(logEntry)
        XCTAssertEqual(logEntry.level, .info)
        XCTAssertEqual(logEntry.message, "Test message")
    }

    func testServerHealthEnum() throws {
        let healthy = ServerHealth.healthy
        let unhealthy = ServerHealth.unhealthy
        let unknown = ServerHealth.unknown

        XCTAssertNotEqual(healthy, unhealthy)
        XCTAssertNotEqual(healthy, unknown)
        XCTAssertNotEqual(unhealthy, unknown)
    }

    func testLogLevelEnum() throws {
        let debug = LogLevel.debug
        let info = LogLevel.info
        let warning = LogLevel.warning
        let error = LogLevel.error

        XCTAssertEqual(debug.icon, "ladybug")
        XCTAssertEqual(info.icon, "info.circle")
        XCTAssertEqual(warning.icon, "exclamationmark.triangle")
        XCTAssertEqual(error.icon, "xmark.circle")
    }

    func testAppBuildSuccess() throws {
        // This test simply verifies that the app builds and imports successfully
        XCTAssertTrue(true, "App builds and imports successfully")
    }
}
