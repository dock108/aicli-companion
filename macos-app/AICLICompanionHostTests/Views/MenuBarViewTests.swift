//
//  MenuBarViewTests.swift
//  AICLICompanionHostTests
//
//  Tests for MenuBarView and Menu Bar functionality
//

import XCTest
import SwiftUI
import AppKit
@testable import AICLICompanionHost

@MainActor
final class MenuBarViewTests: ViewTestCase {
    var menuBarViewModel: MenuBarViewModel!
    var serverManager: ServerManager!
    var settingsManager: SettingsManager!

    override func setUp() async throws {
        try await super.setUp()
        serverManager = ServerManager.shared
        settingsManager = SettingsManager.shared
        menuBarViewModel = MenuBarViewModel()

        // Reset state
        serverManager.isRunning = false
        // connectionString is computed, can't set directly
        serverManager.publicURL = nil
    }

    override func tearDown() async throws {
        menuBarViewModel = nil
        serverManager.isRunning = false
        try await super.tearDown()
    }

    // MARK: - Menu Bar Status Tests

    func testMenuBarStatusDisplay() {
        // Test stopped state
        menuBarViewModel.serverStatus = .stopped
        XCTAssertEqual(menuBarViewModel.statusIcon, "circle")
        XCTAssertEqual(menuBarViewModel.statusColor, .gray)
        XCTAssertEqual(menuBarViewModel.statusText, "Server Stopped")

        // Test running healthy state
        menuBarViewModel.serverStatus = .running
        menuBarViewModel.serverHealth = .healthy
        XCTAssertEqual(menuBarViewModel.statusIcon, "circle.fill")
        XCTAssertEqual(menuBarViewModel.statusColor, .green)
        XCTAssertEqual(menuBarViewModel.statusText, "Server Running")

        // Test running unhealthy state
        menuBarViewModel.serverStatus = .running
        menuBarViewModel.serverHealth = .unhealthy
        XCTAssertEqual(menuBarViewModel.statusIcon, "exclamationmark.circle.fill")
        XCTAssertEqual(menuBarViewModel.statusColor, .orange)
        XCTAssertEqual(menuBarViewModel.statusText, "Server Running (Issues)")

        // Test starting state
        menuBarViewModel.serverStatus = .starting
        XCTAssertEqual(menuBarViewModel.statusIcon, "circle.dotted")
        XCTAssertEqual(menuBarViewModel.statusColor, .yellow)
        XCTAssertEqual(menuBarViewModel.statusText, "Starting Server...")

        // Test stopping state
        menuBarViewModel.serverStatus = .stopping
        XCTAssertEqual(menuBarViewModel.statusIcon, "circle.dotted")
        XCTAssertEqual(menuBarViewModel.statusColor, .yellow)
        XCTAssertEqual(menuBarViewModel.statusText, "Stopping Server...")
    }

    // MARK: - Quick Actions Tests

    func testQuickActionsAvailability() {
        XCTAssertEqual(menuBarViewModel.quickActions.count, 6)

        let actionIds = menuBarViewModel.quickActions.map { $0.id }
        XCTAssertTrue(actionIds.contains("toggle"))
        XCTAssertTrue(actionIds.contains("copy"))
        XCTAssertTrue(actionIds.contains("qr"))
        XCTAssertTrue(actionIds.contains("activity"))
        XCTAssertTrue(actionIds.contains("settings"))
        XCTAssertTrue(actionIds.contains("logs"))
    }

    func testCopyActionEnablement() {
        let copyAction = menuBarViewModel.quickActions.first { $0.id == "copy" }

        // Disabled when no connection
        menuBarViewModel.connectionString = ""
        menuBarViewModel.serverStatus = .stopped
        XCTAssertFalse(copyAction?.isEnabled() ?? true)

        // Enabled when has connection and running
        menuBarViewModel.connectionString = "http://localhost:3001"
        menuBarViewModel.serverStatus = .running
        XCTAssertTrue(copyAction?.isEnabled() ?? false)
    }

    func testQRCodeActionEnablement() {
        let qrAction = menuBarViewModel.quickActions.first { $0.id == "qr" }

        // Disabled when no connection
        menuBarViewModel.connectionString = ""
        XCTAssertFalse(qrAction?.isEnabled() ?? true)

        // Enabled when has connection
        menuBarViewModel.connectionString = "http://localhost:3001"
        menuBarViewModel.serverStatus = .running
        XCTAssertTrue(qrAction?.isEnabled() ?? false)
    }

    // MARK: - Server Toggle Tests

    func testToggleServerButton() {
        // When stopped
        menuBarViewModel.serverStatus = .stopped
        XCTAssertEqual(menuBarViewModel.toggleServerTitle, "Start Server")

        // When running
        menuBarViewModel.serverStatus = .running
        XCTAssertEqual(menuBarViewModel.toggleServerTitle, "Stop Server")

        // When starting
        menuBarViewModel.serverStatus = .starting
        XCTAssertEqual(menuBarViewModel.toggleServerTitle, "Starting...")

        // When stopping
        menuBarViewModel.serverStatus = .stopping
        XCTAssertEqual(menuBarViewModel.toggleServerTitle, "Stopping...")
    }

    func testCanToggleServer() {
        menuBarViewModel.isProcessing = false
        XCTAssertTrue(menuBarViewModel.canToggleServer)

        menuBarViewModel.isProcessing = true
        XCTAssertFalse(menuBarViewModel.canToggleServer)
    }

    func testToggleServerAction() async {
        // Test starting server
        serverManager.isRunning = false
        menuBarViewModel.serverStatus = .stopped

        await menuBarViewModel.toggleServer()

        // Will be stopped after failed start in test environment
        XCTAssertEqual(menuBarViewModel.serverStatus, .stopped)
    }

    // MARK: - Connection String Tests

    func testConnectionStringDisplay() {
        // Set properties that connectionString depends on
        serverManager.isRunning = true
        serverManager.port = 3001
        serverManager.isRunning = true

        // Trigger update
        serverManager.isRunning = false
        serverManager.isRunning = true
        waitForAsync()

        XCTAssertEqual(menuBarViewModel.connectionString, "http://localhost:3001")
        XCTAssertTrue(menuBarViewModel.hasConnection)
    }

    func testLocalURLGeneration() {
        serverManager.localIP = "192.168.1.100"
        serverManager.port = 3001
        serverManager.isRunning = true

        // Trigger update
        serverManager.isRunning = false
        serverManager.isRunning = true
        waitForAsync()

        XCTAssertEqual(menuBarViewModel.localURL, "http://192.168.1.100:3001")
    }

    func testPublicURLDisplay() {
        serverManager.publicURL = "https://test.ngrok.io"
        waitForAsync()

        XCTAssertEqual(menuBarViewModel.publicURL, "https://test.ngrok.io")
    }

    // MARK: - Copy Connection Tests

    func testCopyConnectionString() {
        menuBarViewModel.connectionString = "http://localhost:3001"
        settingsManager.enableNotifications = false

        menuBarViewModel.copyConnectionString()

        let pasteboard = NSPasteboard.general
        let copied = pasteboard.string(forType: .string)
        XCTAssertEqual(copied, "http://localhost:3001")
    }

    func testCopyEmptyConnection() {
        menuBarViewModel.connectionString = ""

        let pasteboard = NSPasteboard.general
        let initialContent = pasteboard.string(forType: .string)

        menuBarViewModel.copyConnectionString()

        let afterContent = pasteboard.string(forType: .string)
        XCTAssertEqual(initialContent, afterContent)
    }

    // MARK: - QR Code Tests

    func testShowQRCode() {
        XCTAssertFalse(menuBarViewModel.showingQRCode)

        menuBarViewModel.showQRCode()

        XCTAssertTrue(menuBarViewModel.showingQRCode)
    }

    // MARK: - Session Display Tests

    func testSessionCountDisplay() {
        serverManager.activeSessions = [
            TestDataGenerator.createTestSession(id: "1"),
            TestDataGenerator.createTestSession(id: "2"),
            TestDataGenerator.createTestSession(id: "3")
        ]
        waitForAsync()

        XCTAssertEqual(menuBarViewModel.sessionCount, 3)
    }

    func testEmptySessionCount() {
        serverManager.activeSessions.removeAll()
        waitForAsync()

        XCTAssertEqual(menuBarViewModel.sessionCount, 0)
    }

    // MARK: - Recent Logs Tests

    func testRecentLogsDisplay() {
        // Add more than 5 logs
        for i in 1...10 {
            serverManager.logs.append(
                LogEntry(level: .info, message: "Log \(i)")
            )
        }
        waitForAsync()

        // Should only show last 5
        XCTAssertEqual(menuBarViewModel.recentLogs.count, 5)
        XCTAssertEqual(menuBarViewModel.recentLogs.last?.message, "Log 10")
    }

    // MARK: - Restart Server Tests

    func testRestartServer() async {
        serverManager.isRunning = true
        menuBarViewModel.serverStatus = .running

        await menuBarViewModel.restartServer()

        // Should end in stopped state in test environment
        XCTAssertEqual(menuBarViewModel.serverStatus, .stopped)
    }

    func testRestartServerWhenStopped() async {
        serverManager.isRunning = false
        menuBarViewModel.serverStatus = .stopped

        await menuBarViewModel.restartServer()

        // Should remain stopped
        XCTAssertEqual(menuBarViewModel.serverStatus, .stopped)
    }

    // MARK: - Refresh Status Tests

    func testRefreshStatus() {
        // Just verify it doesn't crash
        menuBarViewModel.refreshStatus()
        XCTAssertNotNil(menuBarViewModel)
    }

    // MARK: - Navigation Tests

    func testOpenSettings() {
        // Just verify it doesn't crash
        menuBarViewModel.openSettings()
        XCTAssertNotNil(menuBarViewModel)
    }

    func testOpenActivityMonitor() {
        // Just verify it doesn't crash
        menuBarViewModel.openActivityMonitor()
        XCTAssertNotNil(menuBarViewModel)
    }

    func testOpenLogs() {
        // Just verify it doesn't crash
        menuBarViewModel.openLogs()
        XCTAssertNotNil(menuBarViewModel)
    }

    // MARK: - Server Binding Tests

    func testServerRunningBinding() {
        let expectation = XCTestExpectation(description: "Server status update")

        menuBarViewModel.$serverStatus
            .dropFirst()
            .sink { status in
                if status == .running {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        serverManager.isRunning = true

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(menuBarViewModel.serverStatus, .running)
    }

    func testServerHealthBinding() {
        let expectation = XCTestExpectation(description: "Health update")

        menuBarViewModel.$serverHealth
            .dropFirst()
            .sink { health in
                if health == .healthy {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        serverManager.serverHealth = .healthy

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(menuBarViewModel.serverHealth, .healthy)
    }

    func testProcessingBinding() {
        let expectation = XCTestExpectation(description: "Processing update")

        menuBarViewModel.$isProcessing
            .dropFirst()
            .sink { isProcessing in
                if isProcessing {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        serverManager.isProcessing = true

        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(menuBarViewModel.isProcessing)
    }
}
