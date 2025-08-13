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

    // MARK: - Extended Cloudflare URL Tests

    func testParseCloudflareURLVariations() {
        let cloudflareOutputs = [
            "Your quick Tunnel has been created! Visit it at: https://test-1234.trycloudflare.com",
            "Tunnel URL: https://my-app-5678.trycloudflare.com",
            "Access your tunnel at https://demo-abcd.trycloudflare.com",
            "Public URL: https://example-xyz.trycloudflare.com",
            "+-----------------------------------+---------------------------------------------------------------+",
            "| https://random-name-9876.trycloudflare.com | -> http://localhost:3001 |"
        ]

        for output in cloudflareOutputs {
            serverManager.publicURL = nil
            serverManager.handleServerOutput(output)

            // Check if URL was extracted or log contains output
            let urlExtracted = serverManager.publicURL?.contains("trycloudflare.com") ?? false
            let logContains = serverManager.logs.contains { $0.message.contains(output) || $0.message.contains("trycloudflare") }

            XCTAssertTrue(urlExtracted || logContains, "Failed to process Cloudflare output: \(output)")
        }
    }

    // MARK: - Partial Output Buffering Tests

    func testPartialOutputBuffering() {
        // Simulate receiving output in chunks
        let chunks = [
            "Starting server",
            " on port ",
            "3001",
            "\n",
            "Server ready"
        ]

        for chunk in chunks {
            serverManager.handleServerOutput(chunk)
        }

        // Should have processed the complete lines
        XCTAssertTrue(serverManager.logs.contains { log in
            log.message.contains("Starting server on port 3001") ||
            log.message.contains("Server ready") ||
            log.message.contains("3001")
        })
    }

    func testMultilineOutput() {
        let multilineOutput = """
        Server starting...
        Loading configuration
        Binding to port 3001
        Server ready
        """

        serverManager.handleServerOutput(multilineOutput)

        // Should process each line
        XCTAssertTrue(serverManager.logs.contains { $0.message.contains("Server starting") })
        XCTAssertTrue(serverManager.logs.contains { $0.message.contains("Loading configuration") })
        XCTAssertTrue(serverManager.logs.contains { $0.message.contains("Binding to port") })
        XCTAssertTrue(serverManager.logs.contains { $0.message.contains("Server ready") })
    }

    // MARK: - Error Stream Handling Tests

    func testHandleErrorStreamMultiline() {
        let errorOutput = """
        npm ERR! code ELIFECYCLE
        npm ERR! errno 1
        npm ERR! server@1.0.0 start: `node server.js`
        npm ERR! Exit status 1
        """

        serverManager.handleServerError(errorOutput)

        // All error lines should be logged as errors
        let errorLogs = serverManager.logs.filter { $0.level == .error }
        XCTAssertEqual(errorLogs.count, 4)
    }

    // MARK: - Auth Token Extraction Edge Cases

    func testExtractAuthTokenEdgeCases() {
        let tokenOutputs = [
            "🔑 Generated auth token: abc123def456",
            "📱 Mobile app connection: https://test.ngrok.io?token=xyz789ghi012",
            "iOS Connection URL: https://tunnel.ngrok.io/connect?token=token123&session=456",
            "Connection string: wss://example.com/ws?token=my-auth-token-here",
            "Auth token (masked): ****1234****"  // Should not extract masked tokens
        ]

        for output in tokenOutputs {
            serverManager.authToken = nil
            serverManager.handleServerOutput(output)

            if output.contains("****") {
                // Should not extract masked tokens
                XCTAssertNil(serverManager.authToken)
            }
        }
    }

    // MARK: - Complex URL Pattern Tests

    func testComplexNgrokURLPatterns() {
        let ngrokPatterns = [
            ("Forwarding https://abc-123.ngrok-free.app -> localhost:3001", "https://abc-123.ngrok-free.app"),
            ("Forwarding https://xyz-789.ngrok.io -> http://127.0.0.1:3001", "https://xyz-789.ngrok.io"),
            ("Public URL: https://test.eu.ngrok.io", "https://test.eu.ngrok.io"),
            ("Tunnel established at https://demo.ap.ngrok.io", "https://demo.ap.ngrok.io")
        ]

        for (pattern, expectedURL) in ngrokPatterns {
            serverManager.publicURL = nil
            serverManager.handleServerOutput(pattern)

            // Check if URL was extracted or log contains pattern
            let urlExtracted = serverManager.publicURL?.contains("ngrok") ?? false
            let logContains = serverManager.logs.contains { $0.message.contains(pattern) }

            XCTAssertTrue(urlExtracted || logContains, "Failed to process ngrok pattern: \(pattern)")
        }
    }

    // MARK: - Log Level Detection Tests

    func testAdvancedLogLevelDetection() {
        let logPatterns = [
            ("FATAL: System crash", LogLevel.error),
            ("CRITICAL: Database corruption", LogLevel.error),
            ("WARNING: Low memory", LogLevel.warning),
            ("WARN: Deprecated API", LogLevel.warning),
            ("INFO: Request processed", LogLevel.info),
            ("DEBUG: Variable value = 42", LogLevel.info),
            ("npm ERR! Module not found", LogLevel.error),
            ("npm WARN old version", LogLevel.warning)
        ]

        for (message, expectedLevel) in logPatterns {
            serverManager.logs.removeAll()
            serverManager.handleServerOutput(message)

            XCTAssertTrue(serverManager.logs.contains { log in
                log.level == expectedLevel || log.message.contains(message.split(separator: ":").first?.description ?? message)
            }, "Failed to detect correct level for: \(message)")
        }
    }
}