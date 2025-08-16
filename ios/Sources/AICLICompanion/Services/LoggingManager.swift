import Foundation
import os.log

/// Centralized logging system for better debugging and performance
@available(iOS 16.0, macOS 13.0, *)
public class LoggingManager {
    public static let shared = LoggingManager()
    
    // MARK: - Log Categories
    
    public enum Category: String, CaseIterable {
        case ui = "UI"
        case network = "Network"
        case persistence = "Persistence"
        case session = "Session"
        case loading = "Loading"
        case project = "Project"
        case message = "Message"
        case apns = "APNS"
        case performance = "Performance"
        case error = "Error"
        case debug = "Debug"
        case claude = "Claude"
        case sync = "Sync"
        case queue = "Queue"
        case auth = "Auth"
        case state = "State"
    }
    
    public enum Level: Int, CaseIterable {
        case debug = 0
        case info = 1
        case warning = 2
        case error = 3
        case critical = 4
        
        var emoji: String {
            switch self {
            case .debug: return "🐛"
            case .info: return "ℹ️"
            case .warning: return "⚠️"
            case .error: return "❌"
            case .critical: return "🚨"
            }
        }
        
        var osLogType: OSLogType {
            switch self {
            case .debug: return .debug
            case .info: return .info
            case .warning: return .default
            case .error: return .error
            case .critical: return .fault
            }
        }
    }
    
    // MARK: - Configuration
    
    public var minimumLevel: Level = .debug
    public var enabledCategories: Set<Category> = Set(Category.allCases)
    public var enableConsoleLogging: Bool = true
    public var enableOSLogging: Bool = true
    public var enableFileLogging: Bool = false
    
    // MARK: - Private Properties
    
    private let osLog = OSLog(subsystem: "com.aiclicompanion", category: "app")
    private let queue = DispatchQueue(label: "com.aiclicompanion.logging", qos: .utility)
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
    
    private init() {}
    
    // MARK: - Public API
    
    /// Main logging method
    public func log(
        _ message: String,
        category: Category = .debug,
        level: Level = .info,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        guard level.rawValue >= minimumLevel.rawValue else { return }
        guard enabledCategories.contains(category) else { return }
        
        let fileName = (file as NSString).lastPathComponent.replacingOccurrences(of: ".swift", with: "")
        let timestamp = dateFormatter.string(from: Date())
        
        let logMessage = "\(level.emoji) [\(category.rawValue)] \(timestamp) \(fileName):\(line) \(function) - \(message)"
        
        queue.async { [weak self] in
            self?.outputLog(logMessage, level: level)
        }
    }
    
    // MARK: - Convenience Methods
    
    public func debug(_ message: String, category: Category = .debug, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, category: category, level: .debug, file: file, function: function, line: line)
    }
    
    public func info(_ message: String, category: Category = .debug, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, category: category, level: .info, file: file, function: function, line: line)
    }
    
    public func warning(_ message: String, category: Category = .debug, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, category: category, level: .warning, file: file, function: function, line: line)
    }
    
    public func error(_ message: String, category: Category = .error, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, category: category, level: .error, file: file, function: function, line: line)
    }
    
    public func critical(_ message: String, category: Category = .error, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, category: category, level: .critical, file: file, function: function, line: line)
    }
    
    // MARK: - Domain-Specific Convenience Methods
    
    public func logMessage(_ message: String, operation: String, details: String? = nil) {
        var logText = "\(operation): \(message)"
        if let details = details {
            logText += " - \(details)"
        }
        log(logText, category: .message, level: .info)
    }
    
    public func logSession(_ message: String, sessionId: String?, projectPath: String? = nil) {
        var logText = message
        if let sessionId = sessionId {
            logText += " [Session: \(sessionId.prefix(8))]"
        }
        if let projectPath = projectPath {
            logText += " [Project: \(projectPath.split(separator: "/").last ?? "unknown")]"
        }
        log(logText, category: .session, level: .info)
    }
    
    public func logLoading(_ message: String, isLoading: Bool, projectPath: String? = nil) {
        var logText = "\(isLoading ? "🔄 Started" : "✅ Stopped") \(message)"
        if let projectPath = projectPath {
            logText += " [Project: \(projectPath.split(separator: "/").last ?? "unknown")]"
        }
        log(logText, category: .loading, level: .info)
    }
    
    public func logProject(_ message: String, projectName: String? = nil, projectPath: String? = nil) {
        var logText = message
        if let projectName = projectName {
            logText += " [Project: \(projectName)]"
        }
        if let projectPath = projectPath, projectName == nil {
            logText += " [Path: \(projectPath.split(separator: "/").last ?? "unknown")]"
        }
        log(logText, category: .project, level: .info)
    }
    
    public func logAPNS(_ message: String, messageId: String? = nil, sessionId: String? = nil) {
        var logText = message
        if let messageId = messageId {
            logText += " [MsgID: \(messageId.prefix(8))]"
        }
        if let sessionId = sessionId {
            logText += " [Session: \(sessionId.prefix(8))]"
        }
        log(logText, category: .apns, level: .info)
    }
    
    public func logPerformance(_ message: String, duration: TimeInterval? = nil, details: String? = nil) {
        var logText = message
        if let duration = duration {
            logText += " (\(String(format: "%.3f", duration))s)"
        }
        if let details = details {
            logText += " - \(details)"
        }
        log(logText, category: .performance, level: .info)
    }
    
    // MARK: - Configuration Methods
    
    public func setLevel(_ level: Level) {
        minimumLevel = level
        log("Logging level set to \(level)", category: .debug, level: .info)
    }
    
    public func enableCategory(_ category: Category) {
        enabledCategories.insert(category)
    }
    
    public func disableCategory(_ category: Category) {
        enabledCategories.remove(category)
    }
    
    public func enableCategories(_ categories: [Category]) {
        enabledCategories.formUnion(categories)
    }
    
    public func disableCategories(_ categories: [Category]) {
        enabledCategories.subtract(categories)
    }
    
    // MARK: - Private Methods
    
    private func outputLog(_ message: String, level: Level) {
        if enableConsoleLogging {
            print(message)
        }
        
        if enableOSLogging {
            os_log("%{public}@", log: osLog, type: level.osLogType, message)
        }
        
        // File logging could be implemented here if needed
    }
}

// MARK: - Global Convenience Functions

@available(iOS 16.0, macOS 13.0, *)
public func log(_ message: String, category: LoggingManager.Category = .debug, level: LoggingManager.Level = .info, file: String = #file, function: String = #function, line: Int = #line) {
    LoggingManager.shared.log(message, category: category, level: level, file: file, function: function, line: line)
}

@available(iOS 16.0, macOS 13.0, *)
public func logDebug(_ message: String, category: LoggingManager.Category = .debug, file: String = #file, function: String = #function, line: Int = #line) {
    LoggingManager.shared.debug(message, category: category, file: file, function: function, line: line)
}

@available(iOS 16.0, macOS 13.0, *)
public func logInfo(_ message: String, category: LoggingManager.Category = .debug, file: String = #file, function: String = #function, line: Int = #line) {
    LoggingManager.shared.info(message, category: category, file: file, function: function, line: line)
}

@available(iOS 16.0, macOS 13.0, *)
public func logError(_ message: String, category: LoggingManager.Category = .error, file: String = #file, function: String = #function, line: Int = #line) {
    LoggingManager.shared.error(message, category: category, file: file, function: function, line: line)
}
