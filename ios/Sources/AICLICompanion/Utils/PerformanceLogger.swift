import Foundation

/// Performance logging utility to track initialization times
@available(iOS 16.0, macOS 13.0, *)
public final class PerformanceLogger {
    public static let shared = PerformanceLogger()
    
    private var startTimes: [String: CFAbsoluteTime] = [:]
    private let queue = DispatchQueue(label: "performance.logger", attributes: .concurrent)
    
    private init() {}
    
    /// Start timing an operation
    public func startTiming(_ operation: String) {
        queue.async(flags: .barrier) {
            self.startTimes[operation] = CFAbsoluteTimeGetCurrent()
            print("⏱️ [PERF] Starting: \(operation)")
        }
    }
    
    /// End timing and log the duration
    @discardableResult
    public func endTiming(_ operation: String) -> TimeInterval {
        let endTime = CFAbsoluteTimeGetCurrent()
        
        return queue.sync {
            guard let startTime = startTimes[operation] else {
                print("⚠️ [PERF] No start time for: \(operation)")
                return 0
            }
            
            let duration = endTime - startTime
            startTimes.removeValue(forKey: operation)
            
            let emoji = duration > 1.0 ? "🐌" : duration > 0.5 ? "⚠️" : "✅"
            print("\(emoji) [PERF] \(operation): \(String(format: "%.3f", duration))s")
            
            if duration > 1.0 {
                print("   ⚠️ SLOW OPERATION DETECTED!")
            }
            
            return duration
        }
    }
    
    /// Measure a synchronous block
    public func measure<T>(_ operation: String, block: () throws -> T) rethrows -> T {
        startTiming(operation)
        defer { endTiming(operation) }
        return try block()
    }
    
    /// Measure an async block
    public func measureAsync<T>(_ operation: String, block: () async throws -> T) async rethrows -> T {
        startTiming(operation)
        defer { endTiming(operation) }
        return try await block()
    }
    
    /// Log app lifecycle events
    public func logAppEvent(_ event: String) {
        print("📱 [APP EVENT] \(event) at \(Date())")
    }
}
