//
//  ServerDiscoveryTests.swift
//  AICLICompanionHostTests
//
//  Tests for ServerDiscovery extension of ServerManager
//

import XCTest
@testable import AICLICompanionHost

@MainActor
final class ServerDiscoveryTests: XCTestCase {
    
    var serverManager: ServerManager!
    var originalServerCommand: String = ""
    
    override func setUp() async throws {
        try await super.setUp()
        serverManager = ServerManager.shared
        
        // Store original settings
        originalServerCommand = SettingsManager.shared.serverCommand
        
        // Clear logs
        serverManager.logs.removeAll()
    }
    
    override func tearDown() async throws {
        // Restore original settings
        SettingsManager.shared.serverCommand = originalServerCommand
        
        try await super.tearDown()
    }
    
    // MARK: - Server Directory Discovery Tests
    
    func testFindServerDirectoryInBundle() throws {
        // Test finding server in bundle resources
        let resourcePath = Bundle.main.resourcePath!
        let expectedPath = "\(resourcePath)/server"
        
        // If server is bundled, it should find it
        if FileManager.default.fileExists(atPath: expectedPath) {
            let result = try serverManager.findServerDirectory()
            XCTAssertEqual(result, expectedPath)
        }
    }
    
    func testFindServerDirectoryFallback() throws {
        // Test fallback behavior when server is not in bundle
        do {
            let result = try serverManager.findServerDirectory()
            
            // Should find server somewhere
            XCTAssertFalse(result.isEmpty)
            
            // Check logs for appropriate messages
            if !result.contains("/Resources/server") {
                // Using development, custom, or fallback path
                XCTAssertTrue(serverManager.logs.contains { log in
                    (log.level == .warning && (
                        log.message.contains("Using development server") ||
                        log.message.contains("Using project server")
                    )) ||
                    (log.level == .info && (
                        log.message.contains("Using custom server directory") ||
                        log.message.contains("Using bundled server")
                    ))
                })
            }
        } catch {
            // If it throws, check that appropriate error was logged
            XCTAssertTrue(serverManager.logs.contains { log in
                log.level == .error && log.message.contains("Server not found")
            })
            
            XCTAssertTrue(serverManager.logs.contains { log in
                log.message.contains("ADD_SERVER_TO_XCODE.md")
            })
        }
    }
    
    // MARK: - Server Command Parsing Tests
    
    func testParseServerCommandNpmStart() async throws {
        SettingsManager.shared.serverCommand = "npm start"
        
        let (executable, arguments) = try await serverManager.parseServerCommand()
        
        // Executable should be full path to npm
        XCTAssertTrue(executable.contains("npm"))
        XCTAssertTrue(executable.hasPrefix("/")) // Should be absolute path
        
        // Arguments should be ["start"]
        XCTAssertEqual(arguments, ["start"])
    }
    
    func testParseServerCommandNpmRun() async throws {
        SettingsManager.shared.serverCommand = "npm run dev"
        
        let (executable, arguments) = try await serverManager.parseServerCommand()
        
        // Executable should be full path to npm
        XCTAssertTrue(executable.contains("npm"))
        
        // Arguments should be ["run", "dev"]
        XCTAssertEqual(arguments, ["run", "dev"])
    }
    
    func testParseServerCommandNodeDirect() async throws {
        SettingsManager.shared.serverCommand = "node server.js"
        
        let (executable, arguments) = try await serverManager.parseServerCommand()
        
        // Executable should be full path to node
        XCTAssertTrue(executable.contains("node"))
        XCTAssertTrue(executable.hasPrefix("/")) // Should be absolute path
        
        // Arguments should be ["server.js"]
        XCTAssertEqual(arguments, ["server.js"])
    }
    
    func testParseServerCommandYarn() async throws {
        SettingsManager.shared.serverCommand = "yarn start"
        
        let (executable, arguments) = try await serverManager.parseServerCommand()
        
        // Executable should be "yarn" (not resolved to full path)
        XCTAssertEqual(executable, "yarn")
        
        // Arguments should be ["start"]
        XCTAssertEqual(arguments, ["start"])
    }
    
    func testParseServerCommandWithMultipleArguments() async throws {
        SettingsManager.shared.serverCommand = "node --inspect --max-old-space-size=4096 server.js"
        
        let (executable, arguments) = try await serverManager.parseServerCommand()
        
        // Executable should be full path to node
        XCTAssertTrue(executable.contains("node"))
        
        // Arguments should preserve all flags
        XCTAssertEqual(arguments, ["--inspect", "--max-old-space-size=4096", "server.js"])
    }
    
    func testParseServerCommandEmptyCommand() async {
        SettingsManager.shared.serverCommand = ""
        
        do {
            _ = try await serverManager.parseServerCommand()
            XCTFail("Should throw error for empty command")
        } catch {
            // Expected to throw
            XCTAssertTrue(error is ServerError)
            
            // Should log error
            XCTAssertTrue(serverManager.logs.contains { log in
                log.level == .error && log.message.contains("Invalid server command")
            })
        }
    }
    
    func testParseServerCommandWhitespaceOnly() async {
        SettingsManager.shared.serverCommand = "   "
        
        do {
            _ = try await serverManager.parseServerCommand()
            XCTFail("Should throw error for whitespace-only command")
        } catch {
            // Expected to throw
            XCTAssertTrue(error is ServerError)
        }
    }
    
    func testParseServerCommandNpmWithoutArguments() async throws {
        SettingsManager.shared.serverCommand = "npm"
        
        let (executable, arguments) = try await serverManager.parseServerCommand()
        
        // Should default to "npm start"
        XCTAssertTrue(executable.contains("npm"))
        XCTAssertEqual(arguments, ["start"])
    }
    
    func testParseServerCommandNodeWithoutArguments() async throws {
        SettingsManager.shared.serverCommand = "node"
        
        let (executable, arguments) = try await serverManager.parseServerCommand()
        
        // Node without arguments should have empty arguments array
        XCTAssertTrue(executable.contains("node"))
        XCTAssertEqual(arguments, [])
    }
    
    // MARK: - Custom Command Tests
    
    func testParseServerCommandCustomPath() async throws {
        SettingsManager.shared.serverCommand = "/usr/local/bin/custom-server --port 3000"
        
        let (executable, arguments) = try await serverManager.parseServerCommand()
        
        // Custom command should be preserved as-is
        XCTAssertEqual(executable, "/usr/local/bin/custom-server")
        XCTAssertEqual(arguments, ["--port", "3000"])
    }
    
    func testParseServerCommandPnpm() async throws {
        SettingsManager.shared.serverCommand = "pnpm dev"
        
        let (executable, arguments) = try await serverManager.parseServerCommand()
        
        // pnpm should be preserved (not resolved)
        XCTAssertEqual(executable, "pnpm")
        XCTAssertEqual(arguments, ["dev"])
    }
    
    // MARK: - Integration Tests
    
    func testServerDiscoveryFullFlow() async throws {
        // Test the full discovery flow
        SettingsManager.shared.serverCommand = "npm start"
        
        // Find server directory
        var serverDir: String?
        do {
            serverDir = try serverManager.findServerDirectory()
        } catch {
            // It's okay if server directory is not found in tests
        }
        
        // Parse command
        let (executable, arguments) = try await serverManager.parseServerCommand()
        
        // Verify we have all components needed to start server
        XCTAssertFalse(executable.isEmpty)
        XCTAssertFalse(arguments.isEmpty)
        
        if let dir = serverDir {
            XCTAssertFalse(dir.isEmpty)
        }
    }
    
    // MARK: - Logging Tests
    
    func testLoggingDuringDiscovery() async throws {
        serverManager.logs.removeAll()
        
        // Try to find server directory
        do {
            _ = try serverManager.findServerDirectory()
        } catch {
            // Expected in test environment
        }
        
        // Should have logged something about the search
        XCTAssertTrue(serverManager.logs.count > 0)
    }
    
    func testLoggingDuringCommandParsing() async throws {
        serverManager.logs.removeAll()
        SettingsManager.shared.serverCommand = "npm run test"
        
        _ = try await serverManager.parseServerCommand()
        
        // Should have logs about finding executables
        // (from the findNpmExecutable call)
        XCTAssertTrue(serverManager.logs.count > 0)
    }
}