//
//  MockProcess.swift
//  AICLICompanionHostTests
//
//  Mock process for unit testing without spawning actual processes
//

import Foundation
@testable import AICLICompanionHost

class MockProcess: Process {
    // MARK: - Mock Properties
    private var mockIsRunning = false
    private var mockProcessIdentifier: Int32 = 12345
    private var mockTerminationStatus: Int32 = 0
    private var mockTerminationReason: TerminationReason = .exit
    
    // MARK: - Test Tracking Properties
    var launchCalled = false
    var launchCallCount = 0
    var terminateCalled = false
    var terminateCallCount = 0
    var interruptCalled = false
    var interruptCallCount = 0
    var waitUntilExitCalled = false
    
    // Test control properties
    var shouldFailOnLaunch = false
    var launchError: Error?
    var simulateImmediateExit = false
    var simulateCrash = false
    
    // Capture configuration
    private(set) var capturedLaunchPath: String?
    private(set) var capturedArguments: [String]?
    private(set) var capturedEnvironment: [String: String]?
    private(set) var capturedCurrentDirectoryURL: URL?
    
    // Mock output
    var mockStandardOutput: String?
    var mockStandardError: String?
    
    // MARK: - Process Override Properties
    
    override var isRunning: Bool {
        return mockIsRunning
    }
    
    override var processIdentifier: Int32 {
        return mockProcessIdentifier
    }
    
    override var terminationStatus: Int32 {
        return mockTerminationStatus
    }
    
    override var terminationReason: TerminationReason {
        return mockTerminationReason
    }
    
    // MARK: - Process Override Methods
    
    override func launch() {
        launchCalled = true
        launchCallCount += 1
        
        // Capture configuration
        capturedLaunchPath = self.launchPath ?? self.executableURL?.path
        capturedArguments = self.arguments
        capturedEnvironment = self.environment
        capturedCurrentDirectoryURL = self.currentDirectoryURL
        
        // Don't actually throw since launch() is non-throwing
        // Tests can check shouldFailOnLaunch to verify failure scenarios
        if shouldFailOnLaunch {
            // Mark as not running to simulate failure
            mockIsRunning = false
            mockTerminationStatus = 1
            mockTerminationReason = .exit
            return
        }
        
        mockIsRunning = true
        
        // Simulate immediate exit if configured
        if simulateImmediateExit {
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.simulateExit(status: self?.simulateCrash == true ? 1 : 0)
            }
        }
        
        // Write mock output if configured
        if let output = mockStandardOutput,
           let pipe = self.standardOutput as? Pipe {
            let data = output.data(using: .utf8) ?? Data()
            pipe.fileHandleForWriting.write(data)
        }
        
        if let error = mockStandardError,
           let pipe = self.standardError as? Pipe {
            let data = error.data(using: .utf8) ?? Data()
            pipe.fileHandleForWriting.write(data)
        }
    }
    
    override func terminate() {
        terminateCalled = true
        terminateCallCount += 1
        
        if mockIsRunning {
            simulateExit(status: 143) // SIGTERM exit code
        }
    }
    
    override func interrupt() {
        interruptCalled = true
        interruptCallCount += 1
        
        if mockIsRunning {
            simulateExit(status: 130) // SIGINT exit code
        }
    }
    
    override func waitUntilExit() {
        waitUntilExitCalled = true
        
        // In mock, we don't actually wait
        // Process should already be configured to exit
    }
    
    // MARK: - Mock Control Methods
    
    func simulateExit(status: Int32 = 0, reason: TerminationReason = .exit) {
        mockIsRunning = false
        mockTerminationStatus = status
        mockTerminationReason = reason
        
        // Call termination handler if set
        if let handler = self.terminationHandler {
            handler(self)
        }
    }
    
    func simulateOutput(_ output: String) {
        if let pipe = self.standardOutput as? Pipe {
            if let data = output.data(using: .utf8) {
                pipe.fileHandleForWriting.write(data)
            }
        }
    }
    
    func simulateError(_ error: String) {
        if let pipe = self.standardError as? Pipe {
            if let data = error.data(using: .utf8) {
                pipe.fileHandleForWriting.write(data)
            }
        }
    }
    
    // MARK: - Test Helpers
    
    func reset() {
        mockIsRunning = false
        mockProcessIdentifier = 12345
        mockTerminationStatus = 0
        mockTerminationReason = .exit
        
        launchCalled = false
        launchCallCount = 0
        terminateCalled = false
        terminateCallCount = 0
        interruptCalled = false
        interruptCallCount = 0
        waitUntilExitCalled = false
        
        shouldFailOnLaunch = false
        launchError = nil
        simulateImmediateExit = false
        simulateCrash = false
        
        capturedLaunchPath = nil
        capturedArguments = nil
        capturedEnvironment = nil
        capturedCurrentDirectoryURL = nil
        
        mockStandardOutput = nil
        mockStandardError = nil
        
        self.launchPath = nil
        self.arguments = nil
        self.environment = nil
        self.currentDirectoryURL = nil
        self.standardOutput = nil
        self.standardError = nil
        self.standardInput = nil
        self.terminationHandler = nil
    }
    
    func getConfiguration() -> (path: String?, args: [String]?, env: [String: String]?, dir: URL?) {
        return (
            capturedLaunchPath,
            capturedArguments,
            capturedEnvironment,
            capturedCurrentDirectoryURL
        )
    }
}

// MARK: - Mock Process Factory

class MockProcessFactory {
    static func createServerProcess(
        port: Int = 3001,
        shouldStart: Bool = true,
        shouldFail: Bool = false
    ) -> MockProcess {
        let process = MockProcess()
        
        process.launchPath = "/usr/local/bin/npm"
        process.arguments = ["start"]
        process.environment = [
            "PORT": "\(port)",
            "NODE_ENV": "production"
        ]
        
        if shouldFail {
            process.shouldFailOnLaunch = true
        } else if shouldStart {
            process.mockStandardOutput = "Server started on port \(port)\n"
        }
        
        return process
    }
}