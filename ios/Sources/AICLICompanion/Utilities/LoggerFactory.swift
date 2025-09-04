//
//  LoggerFactory.swift
//  AICLICompanion
//
//  Centralized logger creation to ensure consistency
//

import Foundation
import os

/// Centralized factory for creating consistent loggers throughout the app
/// Eliminates inconsistent logger initialization patterns
public enum LoggerFactory {
    
    // MARK: - Constants
    
    /// Default subsystem identifier for the app
    private static let defaultSubsystem = Bundle.main.bundleIdentifier ?? "AICLICompanion"
    
    // MARK: - Logger Creation
    
    /// Creates a logger for a specific category
    /// - Parameter category: The logging category (e.g., "CloudKitSync", "DeviceCoordinator")
    /// - Returns: A configured os.Logger instance
    public static func logger(for category: String) -> os.Logger {
        return os.Logger(subsystem: defaultSubsystem, category: category)
    }
    
    /// Creates a logger for a specific type
    /// - Parameter type: The type to create a logger for
    /// - Returns: A configured os.Logger instance with the type name as category
    public static func logger<T>(for type: T.Type) -> os.Logger {
        let category = String(describing: type)
        return os.Logger(subsystem: defaultSubsystem, category: category)
    }
    
    // MARK: - Predefined Loggers
    
    /// Logger for CloudKit synchronization operations
    public static let cloudKitSync = logger(for: "CloudKitSync")
    
    /// Logger for device coordination operations
    public static let deviceCoordinator = logger(for: "DeviceCoordinator")
    
    /// Logger for conflict resolution operations
    public static let conflictResolver = logger(for: "ConflictResolver")
    
    /// Logger for WebSocket operations
    public static let webSocket = logger(for: "WebSocket")
    
    /// Logger for push notification operations
    public static let pushNotifications = logger(for: "PushNotifications")
    
    /// Logger for session management
    public static let sessionManager = logger(for: "SessionManager")
    
    /// Logger for message operations
    public static let messageOperations = logger(for: "MessageOperations")
    
    /// Logger for networking operations
    public static let networking = logger(for: "Networking")
    
    /// Logger for performance monitoring
    public static let performance = logger(for: "Performance")
    
    /// Logger for security operations
    public static let security = logger(for: "Security")
    
    // MARK: - Logging Helpers
    
    /// Log an info message with consistent formatting
    /// - Parameters:
    ///   - logger: The logger to use
    ///   - message: The message to log
    ///   - function: The calling function (automatically filled)
    ///   - line: The calling line (automatically filled)
    public static func logInfo(_ logger: os.Logger, _ message: String, function: String = #function, line: Int = #line) {
        logger.info("[\(function):\(line)] \(message)")
    }
    
    /// Log an error message with consistent formatting
    /// - Parameters:
    ///   - logger: The logger to use
    ///   - error: The error to log
    ///   - context: Additional context about the error
    ///   - function: The calling function (automatically filled)
    ///   - line: The calling line (automatically filled)
    public static func logError(_ logger: os.Logger, _ error: Error, context: String? = nil, function: String = #function, line: Int = #line) {
        let contextStr = context.map { " - \($0)" } ?? ""
        logger.error("[\(function):\(line)] Error: \(error.localizedDescription)\(contextStr)")
    }
    
    /// Log a debug message with consistent formatting
    /// - Parameters:
    ///   - logger: The logger to use
    ///   - message: The message to log
    ///   - function: The calling function (automatically filled)
    ///   - line: The calling line (automatically filled)
    public static func logDebug(_ logger: os.Logger, _ message: String, function: String = #function, line: Int = #line) {
        logger.debug("[\(function):\(line)] \(message)")
    }
    
    /// Log a warning message with consistent formatting
    /// - Parameters:
    ///   - logger: The logger to use
    ///   - message: The message to log
    ///   - function: The calling function (automatically filled)
    ///   - line: The calling line (automatically filled)
    public static func logWarning(_ logger: os.Logger, _ message: String, function: String = #function, line: Int = #line) {
        logger.warning("[\(function):\(line)] \(message)")
    }
    
    // MARK: - Performance Logging
    
    /// Log the duration of an operation
    /// - Parameters:
    ///   - logger: The logger to use
    ///   - operation: Description of the operation
    ///   - duration: Time taken in seconds
    ///   - function: The calling function (automatically filled)
    public static func logPerformance(_ logger: os.Logger, operation: String, duration: TimeInterval, function: String = #function) {
        logger.info("[\(function)] Performance: \(operation) took \(String(format: "%.3f", duration))s")
    }
    
    /// Execute a block and log its performance
    /// - Parameters:
    ///   - logger: The logger to use
    ///   - operation: Description of the operation
    ///   - block: The block to execute and measure
    /// - Returns: The result of the block
    public static func loggedExecution<T>(_ logger: os.Logger, operation: String, block: () throws -> T) rethrows -> T {
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try block()
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        logPerformance(logger, operation: operation, duration: duration)
        return result
    }
    
    /// Execute an async block and log its performance
    /// - Parameters:
    ///   - logger: The logger to use
    ///   - operation: Description of the operation
    ///   - block: The async block to execute and measure
    /// - Returns: The result of the block
    public static func loggedAsyncExecution<T>(_ logger: os.Logger, operation: String, block: () async throws -> T) async rethrows -> T {
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try await block()
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        logPerformance(logger, operation: operation, duration: duration)
        return result
    }
}