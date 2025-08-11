//
//  ServerManagerProcessTests.swift
//  AICLICompanionHostTests
//
//  Tests for ServerManager's process management functionality
//

import XCTest
@testable import AICLICompanionHost

@MainActor
final class ServerManagerProcessTests: XCTestCase {
    
    var serverManager: ServerManager!
    
    override func setUp() async throws {
        try await super.setUp()
        serverManager = ServerManager.shared
        serverManager.logs.removeAll()
        serverManager.isRunning = false
        serverManager.serverProcess = nil
    }
    
    override func tearDown() async throws {
        // Ensure server is stopped
        if serverManager.isRunning {
            await serverManager.stopServer()
        }
        serverManager.logs.removeAll()
        serverManager.isRunning = false
        serverManager.serverProcess = nil
        try await super.tearDown()
    }
    
    // MARK: - Process Start Tests
    
    func testStartServerProcessSetsIsProcessing() async throws {
        // Start server in background
        Task {
            try? await serverManager.startServer()
        }
        
        // Give time for processing flag to be set
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Should set isProcessing during start
        XCTAssertTrue(serverManager.isProcessing || serverManager.isRunning)
    }
    
    func testStartServerWhenAlreadyRunning() async throws {
        // Mock a running state
        serverManager.isRunning = true
        serverManager.serverProcess = Process() // Mock process
        
        do {
            try await serverManager.startServer()
            XCTFail("Should throw error when server already running")
        } catch {
            // Expected error
            XCTAssertTrue(error.localizedDescription.contains("already running") || 
                         error.localizedDescription.contains("Server is already"))
        }
    }
    
    // MARK: - Environment Setup Tests
    
    func testSetupServerEnvironmentBasic() async throws {
        // Basic environment without auth or tunnel
        SettingsManager.shared.requireAuthentication = false
        SettingsManager.shared.enableTunnel = false
        
        let environment = try await serverManager.setupServerEnvironment()
        
        XCTAssertEqual(environment["PORT"], String(SettingsManager.shared.serverPort))
        XCTAssertEqual(environment["NODE_ENV"], "production")
        XCTAssertNil(environment["AUTH_REQUIRED"])
        XCTAssertNil(environment["ENABLE_TUNNEL"])
    }
    
    func testSetupServerEnvironmentWithAuth() async throws {
        // Environment with authentication enabled
        SettingsManager.shared.requireAuthentication = true
        serverManager.authToken = "test-token-123"
        
        let environment = try await serverManager.setupServerEnvironment()
        
        XCTAssertEqual(environment["AUTH_REQUIRED"], "true")
        XCTAssertEqual(environment["AUTH_TOKEN"], "test-token-123")
    }
    
    func testSetupServerEnvironmentWithTunnel() async throws {
        // Environment with tunnel enabled
        SettingsManager.shared.enableTunnel = true
        SettingsManager.shared.tunnelProvider = "ngrok"
        SettingsManager.shared.ngrokAuthToken = "ngrok-token-456"
        
        let environment = try await serverManager.setupServerEnvironment()
        
        XCTAssertEqual(environment["ENABLE_TUNNEL"], "true")
        XCTAssertEqual(environment["TUNNEL_PROVIDER"], "ngrok")
        XCTAssertEqual(environment["NGROK_AUTH_TOKEN"], "ngrok-token-456")
    }
    
    // MARK: - Server Directory Tests
    
    func testFindServerDirectory() throws {
        // Test finding server directory
        let serverDir = try serverManager.findServerDirectory()
        
        XCTAssertFalse(serverDir.isEmpty)
        XCTAssertTrue(serverDir.hasPrefix("/"))
    }
    
    func testFindServerDirectoryWithCustomPath() throws {
        // Test with custom server directory
        let customPath = "/custom/server/path"
        SettingsManager.shared.serverDirectory = customPath
        
        let serverDir = try serverManager.findServerDirectory()
        
        XCTAssertEqual(serverDir, customPath)
    }
    
    // MARK: - Command Parsing Tests
    
    func testParseServerCommandNpmStart() async throws {
        SettingsManager.shared.serverCommand = "npm start"
        
        let (executable, arguments) = try await serverManager.parseServerCommand()
        
        XCTAssertTrue(executable.contains("npm"))
        XCTAssertEqual(arguments, ["start"])
    }
    
    func testParseServerCommandNodeServer() async throws {
        SettingsManager.shared.serverCommand = "node server.js --port 3000"
        
        let (executable, arguments) = try await serverManager.parseServerCommand()
        
        XCTAssertTrue(executable.contains("node"))
        XCTAssertEqual(arguments, ["server.js", "--port", "3000"])
    }
    
    func testParseServerCommandYarnStart() async throws {
        SettingsManager.shared.serverCommand = "yarn start"
        
        let (executable, arguments) = try await serverManager.parseServerCommand()
        
        XCTAssertTrue(executable.contains("yarn"))
        XCTAssertEqual(arguments, ["start"])
    }
    
    // MARK: - Port Management Tests
    
    func testPortConfiguration() {
        // Test port is configurable
        SettingsManager.shared.serverPort = 3001
        XCTAssertEqual(SettingsManager.shared.serverPort, 3001)
        
        SettingsManager.shared.serverPort = 8080
        XCTAssertEqual(SettingsManager.shared.serverPort, 8080)
    }
    
    // MARK: - Process Stop Tests
    
    func testStopServerWhenNotRunning() async {
        serverManager.isRunning = false
        serverManager.serverProcess = nil
        
        await serverManager.stopServer()
        
        // Should handle gracefully
        XCTAssertFalse(serverManager.isRunning)
        XCTAssertNil(serverManager.serverProcess)
    }
    
    func testStopServerCleansUpState() async {
        // Setup mock running state
        serverManager.isRunning = true
        serverManager.serverProcess = Process()
        serverManager.publicURL = "https://test.ngrok.io"
        
        await serverManager.stopServer()
        
        // Should clean up all state
        XCTAssertFalse(serverManager.isRunning)
        XCTAssertNil(serverManager.serverProcess)
        XCTAssertNil(serverManager.publicURL)
    }
    
    // MARK: - Restart Tests
    
    func testRestartServerWhenRunning() async throws {
        // Mock running state
        serverManager.isRunning = true
        let mockProcess = Process()
        serverManager.serverProcess = mockProcess
        
        // Start restart (will fail but tests the flow)
        Task {
            try? await serverManager.restartServerWithCurrentConfig()
        }
        
        // Give time for stop to be called
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Should attempt to stop first
        XCTAssertTrue(serverManager.logs.contains { log in
            log.message.contains("Restarting server") || 
            log.message.contains("Stopping server")
        })
    }
    
    // MARK: - Health Check Tests
    
    func testRefreshServerStatus() async {
        serverManager.isRunning = true
        
        await serverManager.refreshStatus()
        
        // Should update health status
        XCTAssertNotNil(serverManager.serverHealth)
    }
    
    // MARK: - Process Monitoring Tests
    
    func testProcessTerminationHandling() {
        let process = Process()
        serverManager.serverProcess = process
        serverManager.isRunning = true
        
        // Setup termination handler
        serverManager.setupProcessOutputHandling(for: process)
        
        // Process should have termination handler
        XCTAssertNotNil(process.terminationHandler)
    }
}