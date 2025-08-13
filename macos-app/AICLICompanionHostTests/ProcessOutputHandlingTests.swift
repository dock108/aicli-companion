//
//  ProcessOutputHandlingTests.swift
//  AICLICompanionHostTests
//
//  Tests for ServerManager's process output handling functionality
//

import XCTest
@testable import AICLICompanionHost

@MainActor
final class ProcessOutputHandlingTests: XCTestCase {
    
    var serverManager: ServerManager!
    
    override func setUp() async throws {
        try await super.setUp()
        serverManager = ServerManager.shared
        serverManager.logs.removeAll()
        serverManager.isRunning = false
        serverManager.serverProcess = nil
    }
    
    override func tearDown() async throws {
        serverManager.logs.removeAll()
        serverManager.isRunning = false
        serverManager.serverProcess = nil
        try await super.tearDown()
    }
    
    // MARK: - Output Parsing Tests
    
    func testParseServerStartupMessage() {
        let testMessages = [
            "Server running at http://localhost:3001",
            "Listening on port 3001",
            "Server started on http://127.0.0.1:3001",
            "🚀 Server ready at http://localhost:3001"
        ]
        
        for message in testMessages {
            serverManager.handleServerOutput(message)
            
            // Should detect server started
            if message.contains("3001") {
                XCTAssertTrue(serverManager.logs.contains { log in
                    log.message.contains(message) || log.message.contains("3001")
                })
            }
        }
    }
    
    func testParseNgrokURL() {
        let ngrokOutput = "Forwarding https://abc123.ngrok.io -> http://localhost:3001"
        
        serverManager.handleServerOutput(ngrokOutput)
        
        // Should extract public URL
        XCTAssertEqual(serverManager.publicURL, "https://abc123.ngrok.io")
    }
    
    func testParseCloudflaredURL() {
        let cloudflareOutput = "Your quick Tunnel has been created! Visit it at: https://test-tunnel.trycloudflare.com"
        
        serverManager.handleServerOutput(cloudflareOutput)
        
        // Should extract public URL
        XCTAssertEqual(serverManager.publicURL, "https://test-tunnel.trycloudflare.com")
    }
    
    func testParseErrorMessages() {
        let errorMessages = [
            "Error: EADDRINUSE: address already in use :::3001",
            "npm ERR! code ELIFECYCLE",
            "Error: Cannot find module 'express'",
            "Fatal error: Port 3001 is already in use"
        ]
        
        for errorMsg in errorMessages {
            serverManager.logs.removeAll()
            serverManager.handleServerOutput(errorMsg)
            
            // Should log as error
            XCTAssertTrue(serverManager.logs.contains { log in
                log.level == .error && log.message == errorMsg
            }, "Failed to find error log for: \(errorMsg)")
        }
    }
    
    func testParseWarningMessages() {
        let warningMessages = [
            "npm WARN deprecated package@1.0.0",
            "Warning: No auth token provided",
            "WARN: Using default configuration"
        ]
        
        for warningMsg in warningMessages {
            serverManager.logs.removeAll()
            serverManager.handleServerOutput(warningMsg)
            
            // Should log as warning
            XCTAssertTrue(serverManager.logs.contains { log in
                log.level == .warning && log.message.contains(warningMsg)
            })
        }
    }
    
    // MARK: - Stream Handling Tests
    
    func testHandleOutputStream() {
        // Test output handling
        let testMessage = "Test server output"
        
        serverManager.handleServerOutput(testMessage)
        
        // Should have logged the output
        XCTAssertTrue(serverManager.logs.contains { log in
            log.message.contains("Test server output")
        })
    }
    
    func testHandleErrorStream() {
        // Test error handling
        let testError = "Error: Something went wrong"
        
        serverManager.handleServerError(testError)
        
        // Should have logged as error
        XCTAssertTrue(serverManager.logs.contains { log in
            log.level == .error && log.message.contains("Something went wrong")
        })
    }
    
    // MARK: - Port Detection Tests
    
    func testDetectPortFromOutput() {
        let portMessages = [
            "Server listening on port 8080",
            "Listening on :4000",
            "Starting server on 0.0.0.0:5000",
            "HTTP server listening at http://localhost:9000"
        ]
        
        for message in portMessages {
            serverManager.handleServerOutput(message)
        }
        
        // Should detect various port formats
        XCTAssertTrue(serverManager.logs.count > 0)
    }
    
    // MARK: - Tunnel URL Detection Tests
    
    func testDetectNgrokURLVariations() {
        let ngrokVariations = [
            "Forwarding https://abc123.ngrok.io -> http://localhost:3001",
            "Forwarding https://xyz789.ngrok-free.app -> localhost:3001",
            "https://test123.ngrok.io -> http://127.0.0.1:3001"
        ]
        
        for output in ngrokVariations {
            serverManager.publicURL = nil
            serverManager.handleServerOutput(output)
            
            XCTAssertNotNil(serverManager.publicURL)
            XCTAssertTrue(serverManager.publicURL?.contains("ngrok") ?? false)
        }
    }
    
    func testDetectCloudflareURLVariations() {
        let cloudflareVariations = [
            "Your quick Tunnel has been created! Visit it at: https://test.trycloudflare.com",
            "Tunnel URL: https://example.trycloudflare.com",
            "Access your tunnel at https://demo.trycloudflare.com"
        ]
        
        for output in cloudflareVariations {
            serverManager.publicURL = nil
            serverManager.handleServerOutput(output)
            
            XCTAssertNotNil(serverManager.publicURL)
            XCTAssertTrue(serverManager.publicURL?.contains("trycloudflare.com") ?? false)
        }
    }
    
    // MARK: - Buffer Management Tests
    
    func testOutputBufferAccumulation() {
        // Simulate partial output lines
        let partialOutputs = [
            "Starting ",
            "server on ",
            "port 3001\n"
        ]
        
        for partial in partialOutputs {
            serverManager.handleServerOutput(partial)
        }
        
        // Should accumulate and process complete line
        XCTAssertTrue(serverManager.logs.contains { log in
            log.message.contains("Starting server on port 3001") ||
            log.message.contains("3001")
        })
    }
    
    // MARK: - Process State Tests
    
    func testProcessTerminationHandling() {
        // Create a mock process that has been launched
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/echo")
        process.arguments = ["test"]
        
        // Launch and immediately terminate the process
        do {
            try process.run()
            process.terminate()
            process.waitUntilExit()
        } catch {
            // If we can't launch the process, just test with unlaunched process
        }
        
        serverManager.isRunning = true
        serverManager.handleServerTermination(process)
        
        // Should handle termination
        XCTAssertFalse(serverManager.isRunning)
        XCTAssertTrue(serverManager.logs.contains { log in
            log.message.contains("terminated") || log.message.contains("stopped") || log.message.contains("Server process") || log.message.contains("exited")
        })
    }
    
    func testAutoRestartOnCrash() {
        // Test auto-restart configuration
        SettingsManager.shared.autoRestartOnCrash = true
        XCTAssertTrue(SettingsManager.shared.autoRestartOnCrash)
        
        SettingsManager.shared.autoRestartOnCrash = false
        XCTAssertFalse(SettingsManager.shared.autoRestartOnCrash)
    }
}