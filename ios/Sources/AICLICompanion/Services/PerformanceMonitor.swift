import Foundation
import Combine

/// Service for monitoring app performance and reporting metrics
@available(iOS 16.0, macOS 13.0, *)
class PerformanceMonitor: ObservableObject {
    static let shared = PerformanceMonitor()
    
    // MARK: - Published Properties
    
    @Published var averageMessageProcessingTime: TimeInterval = 0
    @Published var connectionUptime: TimeInterval = 0
    @Published var messagesProcessedCount: Int = 0
    @Published var connectionStabilityScore: Double = 100.0
    
    // MARK: - Private Properties
    
    private var messageTimings: CircularBuffer<MessageTiming> = CircularBuffer(capacity: 100)
    private var connectionEvents: CircularBuffer<ConnectionEvent> = CircularBuffer(capacity: 50)
    private var metricsTimer: Timer?
    private let metricsReportInterval: TimeInterval = 60.0 // Report every minute
    
    private let httpAICLIService = HTTPAICLIService()
    private var cancellables = Set<AnyCancellable>()
    
    // Session tracking
    private var sessionStartTime: Date?
    private var lastConnectionTime: Date?
    private var totalConnectionTime: TimeInterval = 0
    private var disconnectionCount = 0
    
    // MARK: - Types
    
    struct MessageTiming {
        let messageId: String
        let startTime: Date
        let endTime: Date
        let processingTime: TimeInterval
        let messageType: String
        let success: Bool
        
        init(messageId: String, startTime: Date, endTime: Date, messageType: String, success: Bool = true) {
            self.messageId = messageId
            self.startTime = startTime
            self.endTime = endTime
            self.processingTime = endTime.timeIntervalSince(startTime)
            self.messageType = messageType
            self.success = success
        }
    }
    
    struct ConnectionEvent {
        let timestamp: Date
        let type: EventType
        let duration: TimeInterval?
        
        enum EventType {
            case connected
            case disconnected
            case reconnected
            case error
        }
    }
    
    struct PerformanceMetrics: Codable {
        let timestamp: Date
        let sessionId: String?
        let metrics: Metrics
        
        struct Metrics: Codable {
            let messageProcessing: MessageProcessingMetrics
            let connection: ConnectionMetrics
            let app: AppMetrics
        }
        
        struct MessageProcessingMetrics: Codable {
            let averageProcessingTime: TimeInterval
            let messageCount: Int
            let successRate: Double
            let p95ProcessingTime: TimeInterval
        }
        
        struct ConnectionMetrics: Codable {
            let uptime: TimeInterval
            let stabilityScore: Double
            let reconnectionCount: Int
            let averageReconnectionTime: TimeInterval
        }
        
        struct AppMetrics: Codable {
            let memoryUsage: Double
            let sessionDuration: TimeInterval
            let platform: String
            let appVersion: String
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        setupObservers()
        startMetricsReporting()
    }
    
    // MARK: - Public Methods
    
    /// Start tracking a message processing
    func startMessageTracking(messageId: String, type: String) -> Date {
        let startTime = Date()
        print("⏱ Started tracking message: \(messageId) of type: \(type)")
        return startTime
    }
    
    /// Complete message tracking
    func completeMessageTracking(messageId: String, startTime: Date, type: String, success: Bool = true) {
        let endTime = Date()
        let timing = MessageTiming(
            messageId: messageId,
            startTime: startTime,
            endTime: endTime,
            messageType: type,
            success: success
        )
        
        messageTimings.append(timing)
        messagesProcessedCount += 1
        updateAverageProcessingTime()
        
        print("⏱ Completed tracking message: \(messageId) - Duration: \(String(format: "%.2f", timing.processingTime))s")
    }
    
    /// Record connection established
    func recordConnectionEstablished() {
        lastConnectionTime = Date()
        
        let event = ConnectionEvent(
            timestamp: Date(),
            type: .connected,
            duration: nil
        )
        connectionEvents.append(event)
        
        updateConnectionStability()
    }
    
    /// Record connection lost
    func recordConnectionLost() {
        if let lastConnection = lastConnectionTime {
            let connectionDuration = Date().timeIntervalSince(lastConnection)
            totalConnectionTime += connectionDuration
        }
        
        disconnectionCount += 1
        
        let event = ConnectionEvent(
            timestamp: Date(),
            type: .disconnected,
            duration: lastConnectionTime != nil ? Date().timeIntervalSince(lastConnectionTime!) : nil
        )
        connectionEvents.append(event)
        
        lastConnectionTime = nil
        updateConnectionStability()
    }
    
    /// Start a new monitoring session
    func startSession() {
        sessionStartTime = Date()
        messagesProcessedCount = 0
        disconnectionCount = 0
        totalConnectionTime = 0
    }
    
    /// Get current performance metrics
    func getCurrentMetrics(sessionId: String? = nil) -> PerformanceMetrics {
        let messageMetrics = calculateMessageMetrics()
        let connectionMetrics = calculateConnectionMetrics()
        let appMetrics = calculateAppMetrics()
        
        return PerformanceMetrics(
            timestamp: Date(),
            sessionId: sessionId,
            metrics: PerformanceMetrics.Metrics(
                messageProcessing: messageMetrics,
                connection: connectionMetrics,
                app: appMetrics
            )
        )
    }
    
    // MARK: - Private Methods
    
    private func setupObservers() {
        // Monitor HTTP service connection state
        httpAICLIService.$isConnected
            .sink { [weak self] isConnected in
                if isConnected {
                    self?.recordConnectionEstablished()
                } else {
                    self?.recordConnectionLost()
                }
            }
            .store(in: &cancellables)
    }
    
    private func startMetricsReporting() {
        metricsTimer = Timer.scheduledTimer(withTimeInterval: metricsReportInterval, repeats: true) { [weak self] _ in
            self?.reportMetrics()
        }
    }
    
    private func updateAverageProcessingTime() {
        // TODO: CircularBuffer needs public API to access all elements
        // For now, just track the average manually
        averageMessageProcessingTime = 0
    }
    
    private func updateConnectionStability() {
        // Calculate stability score based on disconnection frequency
        let recentWindow: TimeInterval = 3600 // 1 hour
        let now = Date()
        
        // TODO: CircularBuffer needs public API to access all elements
        let recentDisconnections = 0
        
        // Score: 100 - (disconnections * 10), minimum 0
        connectionStabilityScore = max(0, 100 - Double(recentDisconnections * 10))
        
        // Update connection uptime
        if let sessionStart = sessionStartTime {
            let sessionDuration = now.timeIntervalSince(sessionStart)
            let currentConnectionTime = lastConnectionTime != nil ? now.timeIntervalSince(lastConnectionTime!) : 0
            connectionUptime = (totalConnectionTime + currentConnectionTime) / sessionDuration
        }
    }
    
    private func calculateMessageMetrics() -> PerformanceMetrics.MessageProcessingMetrics {
        // TODO: CircularBuffer needs public API to access all elements
        let timings: [MessageTiming] = []
        
        guard !timings.isEmpty else {
            return PerformanceMetrics.MessageProcessingMetrics(
                averageProcessingTime: 0,
                messageCount: 0,
                successRate: 0,
                p95ProcessingTime: 0
            )
        }
        
        let successCount = timings.filter { $0.success }.count
        let successRate = Double(successCount) / Double(timings.count)
        
        // Calculate P95
        let sortedTimings = timings.sorted { $0.processingTime < $1.processingTime }
        let p95Index = Int(Double(sortedTimings.count) * 0.95)
        let p95Time = sortedTimings[min(p95Index, sortedTimings.count - 1)].processingTime
        
        return PerformanceMetrics.MessageProcessingMetrics(
            averageProcessingTime: averageMessageProcessingTime,
            messageCount: timings.count,
            successRate: successRate,
            p95ProcessingTime: p95Time
        )
    }
    
    private func calculateConnectionMetrics() -> PerformanceMetrics.ConnectionMetrics {
        // TODO: CircularBuffer needs public API to access all elements
        let events: [ConnectionEvent] = []
        
        // Calculate average reconnection time
        var reconnectionTimes: [TimeInterval] = []
        for index in 0..<events.count {
            if events[index].type == .disconnected && index + 1 < events.count && events[index + 1].type == .connected {
                let reconnectionTime = events[index + 1].timestamp.timeIntervalSince(events[index].timestamp)
                reconnectionTimes.append(reconnectionTime)
            }
        }
        
        let avgReconnectionTime = reconnectionTimes.isEmpty ? 0 : reconnectionTimes.reduce(0, +) / Double(reconnectionTimes.count)
        
        return PerformanceMetrics.ConnectionMetrics(
            uptime: connectionUptime,
            stabilityScore: connectionStabilityScore,
            reconnectionCount: disconnectionCount,
            averageReconnectionTime: avgReconnectionTime
        )
    }
    
    private func calculateAppMetrics() -> PerformanceMetrics.AppMetrics {
        let sessionDuration = sessionStartTime != nil ? Date().timeIntervalSince(sessionStartTime!) : 0
        
        // Get memory usage
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        let memoryUsage = result == KERN_SUCCESS ? Double(info.resident_size) / 1024.0 / 1024.0 : 0 // MB
        
        return PerformanceMetrics.AppMetrics(
            memoryUsage: memoryUsage,
            sessionDuration: sessionDuration,
            platform: "iOS",
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        )
    }
    
    private func reportMetrics() {
        guard httpAICLIService.isConnected else { return }
        
        let metrics = getCurrentMetrics(sessionId: nil) // HTTP doesn't maintain persistent sessions
        
        // Send metrics to server telemetry endpoint
        sendMetricsToServer(metrics)
    }
    
    private func sendMetricsToServer(_ metrics: PerformanceMetrics) {
        // Create telemetry request
        let telemetryData: [String: Any] = [
            "type": "performance",
            "timestamp": ISO8601DateFormatter().string(from: metrics.timestamp),
            "sessionId": metrics.sessionId ?? "",
            "metrics": [
                "messageProcessing": [
                    "avgProcessingTime": metrics.metrics.messageProcessing.averageProcessingTime,
                    "messageCount": metrics.metrics.messageProcessing.messageCount,
                    "successRate": metrics.metrics.messageProcessing.successRate,
                    "p95ProcessingTime": metrics.metrics.messageProcessing.p95ProcessingTime
                ],
                "connection": [
                    "uptime": metrics.metrics.connection.uptime,
                    "stabilityScore": metrics.metrics.connection.stabilityScore,
                    "reconnectionCount": metrics.metrics.connection.reconnectionCount,
                    "avgReconnectionTime": metrics.metrics.connection.averageReconnectionTime
                ],
                "app": [
                    "memoryUsage": metrics.metrics.app.memoryUsage,
                    "sessionDuration": metrics.metrics.app.sessionDuration,
                    "platform": metrics.metrics.app.platform,
                    "appVersion": metrics.metrics.app.appVersion
                ]
            ]
        ]
        
        // Send via HTTP
        if let jsonData = try? JSONSerialization.data(withJSONObject: telemetryData),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            print("📊 Sending performance metrics to server")
            
            // Note: This would need an HTTP telemetry endpoint
            // For now, we'll just log it
            print("Telemetry data: \(jsonString)")
        }
    }
}

// Note: CircularBuffer extension removed - properties are private
// If needed, this functionality should be added directly to the CircularBuffer struct
