//
//  ExecutableDiscoveryTests.swift
//  AICLICompanionHostTests
//
//  Tests for ExecutableDiscovery extension of ServerManager
//

import XCTest
@testable import AICLICompanionHost

@MainActor
final class ExecutableDiscoveryTests: XCTestCase {

    var serverManager: ServerManager!
    var originalNodePath: String = ""
    var originalNpmPath: String = ""

    override func setUp() async throws {
        try await super.setUp()
        serverManager = ServerManager.shared

        // Store original settings
        originalNodePath = SettingsManager.shared.nodeExecutable
        originalNpmPath = SettingsManager.shared.npmExecutable

        // Clear logs
        serverManager.logs.removeAll()
    }

    override func tearDown() async throws {
        // Restore original settings
        SettingsManager.shared.nodeExecutable = originalNodePath
        SettingsManager.shared.npmExecutable = originalNpmPath

        try await super.tearDown()
    }

    // MARK: - Node Executable Discovery Tests

    func testFindNodeWithConfiguredPath() async {
        let customPath = "/custom/path/to/node"
        SettingsManager.shared.nodeExecutable = customPath

        let result = await serverManager.findNodeExecutable()

        XCTAssertEqual(result, customPath)

        // Check that it logged using configured path
        XCTAssertTrue(serverManager.logs.contains { log in
            log.message.contains("Using node path from settings")
        })
    }

    func testFindNodeWithTildePath() async {
        let tildePath = "~/bin/node"
        SettingsManager.shared.nodeExecutable = tildePath

        let result = await serverManager.findNodeExecutable()

        let expectedPath = NSString(string: tildePath).expandingTildeInPath
        XCTAssertEqual(result, expectedPath)
        XCTAssertTrue(result.hasPrefix("/Users/")) // Tilde should be expanded
    }

    func testFindNodeWithEmptyConfiguredPath() async {
        SettingsManager.shared.nodeExecutable = ""

        let result = await serverManager.findNodeExecutable()

        // Should fall back to auto-detection
        XCTAssertFalse(result.isEmpty)

        // At minimum should return the fallback
        XCTAssertTrue(
            result == "/usr/local/bin/node" ||
            result.contains("homebrew") ||
            result.contains("nvm") ||
            result == "/usr/bin/node"
        )
    }

    func testFindNodeFallback() async {
        // Clear configured path to trigger auto-detection
        SettingsManager.shared.nodeExecutable = ""

        let result = await serverManager.findNodeExecutable()

        // Should never return empty
        XCTAssertFalse(result.isEmpty)

        // Should log if using fallback
        if result == "/usr/local/bin/node" {
            XCTAssertTrue(serverManager.logs.contains { log in
                log.level == .warning && log.message.contains("Could not auto-detect node")
            })
        }
    }

    // MARK: - NPM Executable Discovery Tests

    func testFindNpmWithConfiguredPath() async {
        let customPath = "/custom/path/to/npm"
        SettingsManager.shared.npmExecutable = customPath

        let result = await serverManager.findNpmExecutable()

        XCTAssertEqual(result, customPath)

        // Check that it logged using configured path
        XCTAssertTrue(serverManager.logs.contains { log in
            log.message.contains("Using npm path from settings")
        })
    }

    func testFindNpmWithTildePath() async {
        let tildePath = "~/.local/bin/npm"
        SettingsManager.shared.npmExecutable = tildePath

        let result = await serverManager.findNpmExecutable()

        let expectedPath = NSString(string: tildePath).expandingTildeInPath
        XCTAssertEqual(result, expectedPath)
        XCTAssertTrue(result.hasPrefix("/Users/")) // Tilde should be expanded
    }

    func testFindNpmWithEmptyConfiguredPath() async {
        SettingsManager.shared.npmExecutable = ""

        let result = await serverManager.findNpmExecutable()

        // Should fall back to auto-detection
        XCTAssertFalse(result.isEmpty)

        // At minimum should return the fallback
        XCTAssertTrue(
            result == "/usr/local/bin/npm" ||
            result.contains("homebrew") ||
            result.contains("nvm") ||
            result == "/usr/bin/npm"
        )
    }

    func testFindNpmFallback() async {
        // Clear configured path to trigger auto-detection
        SettingsManager.shared.npmExecutable = ""

        let result = await serverManager.findNpmExecutable()

        // Should never return empty
        XCTAssertFalse(result.isEmpty)

        // Should log if using fallback
        if result == "/usr/local/bin/npm" {
            XCTAssertTrue(serverManager.logs.contains { log in
                log.level == .warning && log.message.contains("Could not auto-detect npm")
            })
        }
    }

    // MARK: - Common Paths Detection Tests

    func testCommonPathsOrder() async {
        // Test that it checks paths in the correct order
        SettingsManager.shared.nodeExecutable = ""
        serverManager.logs.removeAll()

        _ = await serverManager.findNodeExecutable()

        // The actual found path depends on the system, but we can verify
        // that it attempted detection
        let debugLogs = serverManager.logs.filter { $0.level == .debug }

        // Should have at least one debug log about detection
        XCTAssertTrue(
            debugLogs.contains { $0.message.contains("Auto-detected") } ||
            debugLogs.contains { $0.message.contains("Found") } ||
            debugLogs.contains { $0.message.contains("Using") }
        )
    }

    // MARK: - Both Executables Tests

    func testFindBothExecutables() async {
        SettingsManager.shared.nodeExecutable = ""
        SettingsManager.shared.npmExecutable = ""

        let nodePath = await serverManager.findNodeExecutable()
        let npmPath = await serverManager.findNpmExecutable()

        // Both should return valid paths
        XCTAssertFalse(nodePath.isEmpty)
        XCTAssertFalse(npmPath.isEmpty)

        // Paths should be absolute
        XCTAssertTrue(nodePath.hasPrefix("/"))
        XCTAssertTrue(npmPath.hasPrefix("/"))

        // If they're in the same directory (common case), verify that
        let nodeDir = URL(fileURLWithPath: nodePath).deletingLastPathComponent().path
        let npmDir = URL(fileURLWithPath: npmPath).deletingLastPathComponent().path

        // Often they're in the same bin directory
        if nodeDir == npmDir {
            XCTAssertTrue(nodeDir.contains("bin"))
        }
    }

    func testMixedConfiguration() async {
        // Configure node but not npm
        SettingsManager.shared.nodeExecutable = "/custom/node"
        SettingsManager.shared.npmExecutable = ""

        let nodePath = await serverManager.findNodeExecutable()
        let npmPath = await serverManager.findNpmExecutable()

        XCTAssertEqual(nodePath, "/custom/node")
        XCTAssertFalse(npmPath.isEmpty)
        XCTAssertNotEqual(npmPath, "/custom/npm") // Should auto-detect, not assume
    }

    // MARK: - Logging Tests

    func testLoggingDuringDiscovery() async {
        serverManager.logs.removeAll()
        SettingsManager.shared.nodeExecutable = "/test/node"
        SettingsManager.shared.npmExecutable = ""

        _ = await serverManager.findNodeExecutable()
        _ = await serverManager.findNpmExecutable()

        // Should have logs about the discovery process
        XCTAssertTrue(serverManager.logs.count > 0)

        // Should have debug log about using configured path for node
        XCTAssertTrue(serverManager.logs.contains { log in
            log.level == .debug && log.message.contains("Using node path from settings")
        })
    }

    // MARK: - Path Validation Tests

    func testPathsAreAbsolute() async {
        // Test various configurations
        let testPaths = [
            ("", true),  // Empty returns fallback which is absolute
            ("~/bin/node", true),  // Tilde expansion makes it absolute
            ("/usr/local/bin/node", true),  // Already absolute
            ("relative/path/node", false)  // Relative paths stay relative
        ]

        for (testPath, shouldBeAbsolute) in testPaths {
            SettingsManager.shared.nodeExecutable = testPath

            let result = await serverManager.findNodeExecutable()

            if shouldBeAbsolute {
                XCTAssertTrue(result.hasPrefix("/"), "Path '\(result)' should be absolute for input '\(testPath)'")
            } else {
                // Relative paths are returned as-is after tilde expansion
                XCTAssertEqual(result, testPath, "Relative path should be returned as-is")
            }
        }
    }

    func testPathExpansion() async {
        let pathsToTest = [
            ("~/bin/node", true),    // Should expand
            ("$HOME/bin/node", false), // Won't expand $ variables
            ("/usr/bin/node", false)   // Already absolute
        ]

        for (path, shouldExpand) in pathsToTest {
            SettingsManager.shared.nodeExecutable = path

            let result = await serverManager.findNodeExecutable()

            if shouldExpand {
                XCTAssertNotEqual(result, path)
                XCTAssertFalse(result.contains("~"))
            }
        }
    }
}