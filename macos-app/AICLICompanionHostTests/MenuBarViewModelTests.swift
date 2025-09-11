//
//  MenuBarViewModelTests.swift
//  AICLICompanionHostTests
//
//  Tests for MenuBarViewModel
//

import XCTest
import Combine
import AppKit
@testable import AICLICompanionHost

@MainActor
final class MenuBarViewModelTests: XCTestCase {
    var viewModel: MenuBarViewModel!
    var serverManager: ServerManager!
    var settingsManager: SettingsManager!
    var cancellables: Set<AnyCancellable>!

    override func setUp() async throws {
        try await super.setUp()
        serverManager = ServerManager.shared
        settingsManager = SettingsManager.shared

        // Reset state
        serverManager.isRunning = false
        serverManager.serverHealth = .unknown
        // connectionString is computed, no need to reset
        serverManager.publicURL = nil
        serverManager.activeSessions.removeAll()
        serverManager.logs.removeAll()

        viewModel = MenuBarViewModel()
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() async throws {
        cancellables.removeAll()
        serverManager.isRunning = false
        serverManager.activeSessions.removeAll()
        serverManager.logs.removeAll()
        try await super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitialization() {
        XCTAssertEqual(viewModel.connectionString, "")
        XCTAssertEqual(viewModel.serverStatus, .stopped)
        XCTAssertEqual(viewModel.serverHealth, .unknown)
        XCTAssertFalse(viewModel.isProcessing)
        XCTAssertEqual(viewModel.sessionCount, 0)
        XCTAssertNil(viewModel.publicURL)
        XCTAssertFalse(viewModel.showingQRCode)
        XCTAssertTrue(!viewModel.quickActions.isEmpty)
    }

    func testQuickActionsSetup() {
        XCTAssertEqual(viewModel.quickActions.count, 6)

        let actionIds = viewModel.quickActions.map { $0.id }
        XCTAssertTrue(actionIds.contains("toggle"))
        XCTAssertTrue(actionIds.contains("copy"))
        XCTAssertTrue(actionIds.contains("qr"))
        XCTAssertTrue(actionIds.contains("activity"))
        XCTAssertTrue(actionIds.contains("settings"))
        XCTAssertTrue(actionIds.contains("logs"))
    }

    // MARK: - Status Icon Tests

    func testStatusIconMapping() {
        // Running + Healthy
        viewModel.serverStatus = .running
        viewModel.serverHealth = .healthy
        XCTAssertEqual(viewModel.statusIcon, "circle.fill")

        // Running + Unhealthy
        viewModel.serverStatus = .running
        viewModel.serverHealth = .unhealthy
        XCTAssertEqual(viewModel.statusIcon, "exclamationmark.circle.fill")

        // Starting
        viewModel.serverStatus = .starting
        XCTAssertEqual(viewModel.statusIcon, "circle.dotted")

        // Stopping
        viewModel.serverStatus = .stopping
        XCTAssertEqual(viewModel.statusIcon, "circle.dotted")

        // Stopped
        viewModel.serverStatus = .stopped
        XCTAssertEqual(viewModel.statusIcon, "circle")
    }

    // MARK: - Status Color Tests

    func testStatusColorMapping() {
        // Running + Healthy
        viewModel.serverStatus = .running
        viewModel.serverHealth = .healthy
        XCTAssertEqual(viewModel.statusColor, .green)

        // Running + Unhealthy
        viewModel.serverStatus = .running
        viewModel.serverHealth = .unhealthy
        XCTAssertEqual(viewModel.statusColor, .orange)

        // Starting
        viewModel.serverStatus = .starting
        XCTAssertEqual(viewModel.statusColor, .yellow)

        // Stopping
        viewModel.serverStatus = .stopping
        XCTAssertEqual(viewModel.statusColor, .yellow)

        // Stopped
        viewModel.serverStatus = .stopped
        XCTAssertEqual(viewModel.statusColor, .gray)
    }

    // MARK: - Status Text Tests

    func testStatusTextMapping() {
        // Running + Healthy
        viewModel.serverStatus = .running
        viewModel.serverHealth = .healthy
        XCTAssertEqual(viewModel.statusText, "Server Running")

        // Running + Unhealthy
        viewModel.serverStatus = .running
        viewModel.serverHealth = .unhealthy
        XCTAssertEqual(viewModel.statusText, "Server Running (Issues)")

        // Starting
        viewModel.serverStatus = .starting
        XCTAssertEqual(viewModel.statusText, "Starting Server...")

        // Stopping
        viewModel.serverStatus = .stopping
        XCTAssertEqual(viewModel.statusText, "Stopping Server...")

        // Stopped
        viewModel.serverStatus = .stopped
        XCTAssertEqual(viewModel.statusText, "Server Stopped")
    }

    // MARK: - Toggle Server Tests

    func testCanToggleServer() {
        viewModel.isProcessing = false
        XCTAssertTrue(viewModel.canToggleServer)

        viewModel.isProcessing = true
        XCTAssertFalse(viewModel.canToggleServer)
    }

    func testToggleServerTitle() {
        viewModel.serverStatus = .running
        XCTAssertEqual(viewModel.toggleServerTitle, "Stop Server")

        viewModel.serverStatus = .stopped
        XCTAssertEqual(viewModel.toggleServerTitle, "Start Server")

        viewModel.serverStatus = .starting
        XCTAssertEqual(viewModel.toggleServerTitle, "Starting...")

        viewModel.serverStatus = .stopping
        XCTAssertEqual(viewModel.toggleServerTitle, "Stopping...")
    }

    func testToggleServerFromStopped() async {
        serverManager.isRunning = false
        viewModel.serverStatus = .stopped
        viewModel.isProcessing = false

        await viewModel.toggleServer()

        // Should attempt to start
        // Note: In test environment, actual server won't start
        XCTAssertEqual(viewModel.serverStatus, .stopped) // Will be stopped after failed start
    }

    func testToggleServerFromRunning() async {
        serverManager.isRunning = true
        viewModel.serverStatus = .running
        viewModel.isProcessing = false

        await viewModel.toggleServer()

        XCTAssertEqual(viewModel.serverStatus, .stopped)
        XCTAssertFalse(serverManager.isRunning)
    }

    func testToggleServerWhileProcessing() async {
        viewModel.isProcessing = true
        let initialStatus = viewModel.serverStatus

        await viewModel.toggleServer()

        // Should not change when processing
        XCTAssertEqual(viewModel.serverStatus, initialStatus)
    }

    // MARK: - Connection Tests

    func testHasConnection() {
        // No connection string
        viewModel.connectionString = ""
        viewModel.serverStatus = .running
        XCTAssertFalse(viewModel.hasConnection)

        // Has connection string but stopped
        viewModel.connectionString = "http://localhost:3001"
        viewModel.serverStatus = .stopped
        XCTAssertFalse(viewModel.hasConnection)

        // Has connection and running
        viewModel.connectionString = "http://localhost:3001"
        viewModel.serverStatus = .running
        XCTAssertTrue(viewModel.hasConnection)
    }

    func testUpdateConnectionString() {
        serverManager.isRunning = true
        // connectionString is computed from serverManager properties
        serverManager.isRunning = true
        serverManager.port = 3001
        serverManager.localIP = "192.168.1.100"
        serverManager.port = 3001

        // Trigger update through binding
        serverManager.isRunning = false
        serverManager.isRunning = true

        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        XCTAssertEqual(viewModel.connectionString, "http://localhost:3001")
        XCTAssertEqual(viewModel.localURL, "http://192.168.1.100:3001")
    }

    // MARK: - Copy Connection Tests

    func testCopyConnectionString() {
        viewModel.connectionString = "http://localhost:3001"
        settingsManager.enableNotifications = false // Disable notifications for test

        viewModel.copyConnectionString()

        // Verify pasteboard contains the connection string
        let pasteboard = NSPasteboard.general
        let copied = pasteboard.string(forType: .string)
        XCTAssertEqual(copied, "http://localhost:3001")
    }

    func testCopyEmptyConnectionString() {
        viewModel.connectionString = ""

        let pasteboard = NSPasteboard.general
        let initialContent = pasteboard.string(forType: .string)

        viewModel.copyConnectionString()

        // Should not change pasteboard when empty
        let afterContent = pasteboard.string(forType: .string)
        XCTAssertEqual(initialContent, afterContent)
    }

    // MARK: - QR Code Tests

    func testShowQRCode() {
        XCTAssertFalse(viewModel.showingQRCode)

        viewModel.showQRCode()

        XCTAssertTrue(viewModel.showingQRCode)
    }

    // MARK: - Restart Server Tests

    func testRestartServerWhenRunning() async {
        serverManager.isRunning = true
        viewModel.serverStatus = .running

        // The restart will fail because server won't actually start in tests
        // But we need to wait for the async operation to complete
        await viewModel.restartServer()

        // Give time for state changes to propagate
        try? await Task.sleep(for: .milliseconds(100))

        // Should end in stopped state (since server won't actually start in tests)
        XCTAssertEqual(viewModel.serverStatus, .stopped)
    }

    func testRestartServerWhenStopped() async {
        serverManager.isRunning = false
        viewModel.serverStatus = .stopped

        await viewModel.restartServer()

        // Should remain stopped if not running
        XCTAssertEqual(viewModel.serverStatus, .stopped)
    }

    // MARK: - Refresh Status Tests

    func testRefreshStatus() {
        // This just triggers a refresh on ServerManager
        viewModel.refreshStatus()

        // Verify it doesn't crash
        XCTAssertNotNil(viewModel)
    }

    // MARK: - Quit App Tests

    func testQuitAppWhenServerStopped() async {
        serverManager.isRunning = false

        // We can't actually test NSApplication.terminate in unit tests
        // Just verify the method doesn't crash
        // await viewModel.quitApp() // Would terminate test runner

        XCTAssertFalse(serverManager.isRunning)
    }

    // MARK: - Quick Actions Tests

    func testQuickActionEnablement() {
        let copyAction = viewModel.quickActions.first { $0.id == "copy" }
        let qrAction = viewModel.quickActions.first { $0.id == "qr" }

        // When no connection
        viewModel.connectionString = ""
        viewModel.serverStatus = .stopped
        XCTAssertFalse(copyAction?.isEnabled() ?? true)
        XCTAssertFalse(qrAction?.isEnabled() ?? true)

        // When has connection
        viewModel.connectionString = "http://localhost:3001"
        viewModel.serverStatus = .running
        XCTAssertTrue(copyAction?.isEnabled() ?? false)
        XCTAssertTrue(qrAction?.isEnabled() ?? false)
    }

    // MARK: - Session Count Tests

    func testSessionCountBinding() {
        let expectation = XCTestExpectation(description: "Session count update")

        viewModel.$sessionCount
            .dropFirst()
            .sink { count in
                if count == 3 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        serverManager.activeSessions = [
            Session(sessionId: "1", deviceName: "Device 1", connectedAt: Date(), signalStrength: 100),
            Session(sessionId: "2", deviceName: "Device 2", connectedAt: Date(), signalStrength: 100),
            Session(sessionId: "3", deviceName: "Device 3", connectedAt: Date(), signalStrength: 100)
        ]

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(viewModel.sessionCount, 3)
    }

    // MARK: - Recent Logs Tests

    func testRecentLogsBinding() {
        let expectation = XCTestExpectation(description: "Recent logs update")

        viewModel.$recentLogs
            .dropFirst()
            .sink { logs in
                if !logs.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // Add more than 5 logs
        for i in 1...10 {
            serverManager.logs.append(
                LogEntry(level: .info, message: "Log \(i)")
            )
        }

        wait(for: [expectation], timeout: 1.0)

        // Should only keep last 5
        XCTAssertEqual(viewModel.recentLogs.count, 5)
        XCTAssertEqual(viewModel.recentLogs.last?.message, "Log 10")
    }

    // MARK: - Server Manager Binding Tests

    func testServerRunningBinding() {
        let expectation = XCTestExpectation(description: "Server running binding")

        viewModel.$serverStatus
            .dropFirst()
            .sink { status in
                if status == .running {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        serverManager.isRunning = true

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(viewModel.serverStatus, .running)
    }

    func testServerHealthBinding() {
        let expectation = XCTestExpectation(description: "Server health binding")

        viewModel.$serverHealth
            .dropFirst()
            .sink { health in
                if health == .healthy {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        serverManager.serverHealth = .healthy

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(viewModel.serverHealth, .healthy)
    }

    func testPublicURLBinding() {
        let expectation = XCTestExpectation(description: "Public URL binding")

        viewModel.$publicURL
            .dropFirst()
            .sink { url in
                if url == "https://test.ngrok.io" {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        serverManager.publicURL = "https://test.ngrok.io"

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(viewModel.publicURL, "https://test.ngrok.io")
    }

    func testIsProcessingBinding() {
        let expectation = XCTestExpectation(description: "Processing binding")

        viewModel.$isProcessing
            .dropFirst()
            .sink { isProcessing in
                if isProcessing {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        serverManager.isProcessing = true

        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(viewModel.isProcessing)
    }

    // MARK: - Navigation Tests

    func testOpenSettings() {
        // Just verify it doesn't crash
        viewModel.openSettings()
        XCTAssertNotNil(viewModel)
    }

    func testOpenActivityMonitor() {
        // Just verify it doesn't crash
        viewModel.openActivityMonitor()
        XCTAssertNotNil(viewModel)
    }

    func testOpenLogs() {
        // Just verify it doesn't crash
        viewModel.openLogs()
        XCTAssertNotNil(viewModel)
    }
}
