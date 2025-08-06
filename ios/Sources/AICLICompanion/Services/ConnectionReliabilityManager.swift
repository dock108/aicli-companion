import Foundation
import Combine
import Network

/// Manages connection reliability with exponential backoff and quality monitoring
@available(iOS 16.0, macOS 13.0, *)
class ConnectionReliabilityManager: ObservableObject {
    static let shared = ConnectionReliabilityManager()
    
    // MARK: - Published Properties
    
    @Published var connectionQuality: ConnectionQuality = .unknown
    @Published var isReconnecting = false
    @Published var reconnectAttempt = 0
    @Published var nextReconnectTime: Date?
    @Published var connectionHistory: [ConnectionEvent] = []
    
    // MARK: - Private Properties
    
    private let maxReconnectAttempts = 10
    private let baseReconnectDelay: TimeInterval = 1.0 // Start with 1 second
    private let maxReconnectDelay: TimeInterval = 300.0 // Cap at 5 minutes
    private let jitterFactor = 0.3 // Add up to 30% jitter
    
    private var reconnectTimer: Timer?
    private var qualityMonitor: Timer?
    private var pathMonitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "com.aiclicompanion.network.monitor")
    
    private var lastSuccessfulConnection: Date?
    private var connectionAttempts: [Date] = []
    private var disconnectionEvents: [Date] = []
    
    // Message cache for reconnection comparison
    private var messageCache: CircularBuffer<CachedMessage> = CircularBuffer(capacity: 50)
    
    // MARK: - Types
    
    enum ConnectionQuality: String, CaseIterable {
        case excellent = "Excellent"
        case good = "Good"
        case fair = "Fair"
        case poor = "Poor"
        case offline = "Offline"
        case unknown = "Unknown"
        
        var color: String {
            switch self {
            case .excellent: return "green"
            case .good: return "blue"
            case .fair: return "yellow"
            case .poor: return "orange"
            case .offline: return "red"
            case .unknown: return "gray"
            }
        }
        
        var icon: String {
            switch self {
            case .excellent: return "wifi"
            case .good: return "wifi"
            case .fair: return "wifi.exclamationmark"
            case .poor: return "wifi.exclamationmark"
            case .offline: return "wifi.slash"
            case .unknown: return "questionmark.circle"
            }
        }
    }
    
    struct ConnectionEvent {
        let timestamp: Date
        let type: EventType
        let quality: ConnectionQuality?
        let details: String?
        
        enum EventType {
            case connected
            case disconnected
            case reconnecting
            case qualityChanged
            case error
        }
    }
    
    struct CachedMessage: Equatable {
        let id: String
        let content: String
        let timestamp: Date
        let checksum: String
        
        init(from message: Message) {
            self.id = message.id.uuidString
            self.content = message.content
            self.timestamp = message.timestamp
            self.checksum = message.content.hashValue.description
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        setupNetworkMonitoring()
        startQualityMonitoring()
    }
    
    // MARK: - Public Methods
    
    /// Calculate next reconnect delay with exponential backoff and jitter
    func getNextReconnectDelay() -> TimeInterval {
        // Exponential backoff: delay = min(base * 2^attempt, max)
        let exponentialDelay = min(
            baseReconnectDelay * pow(2.0, Double(reconnectAttempt)),
            maxReconnectDelay
        )
        
        // Add jitter to prevent thundering herd
        let jitter = exponentialDelay * jitterFactor * Double.random(in: -1...1)
        let finalDelay = max(baseReconnectDelay, exponentialDelay + jitter)
        
        return finalDelay
    }
    
    /// Schedule reconnection with exponential backoff
    func scheduleReconnection(action: @escaping () -> Void) {
        guard reconnectAttempt < maxReconnectAttempts else {
            logConnectionEvent(.error, details: "Max reconnection attempts reached")
            return
        }
        
        isReconnecting = true
        reconnectAttempt += 1
        
        let delay = getNextReconnectDelay()
        nextReconnectTime = Date().addingTimeInterval(delay)
        
        logConnectionEvent(.reconnecting, details: "Attempt \(reconnectAttempt) in \(Int(delay))s")
        
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.performReconnection(action: action)
        }
    }
    
    /// Reset reconnection state after successful connection
    func resetReconnectionState() {
        print("🔄 ConnectionReliabilityManager: Resetting reconnection state")
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        reconnectAttempt = 0
        isReconnecting = false
        nextReconnectTime = nil
        lastSuccessfulConnection = Date()
        
        print("   Clearing disconnection history")
        // Clear old disconnection events to ensure fresh quality calculation
        disconnectionEvents.removeAll()
        
        updateConnectionQuality()
        logConnectionEvent(.connected)
    }
    
    /// Cancel ongoing reconnection attempts
    func cancelReconnection() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        isReconnecting = false
        nextReconnectTime = nil
    }
    
    /// Called when WebSocket connects successfully
    func handleConnectionEstablished() {
        print("🎉 ConnectionReliabilityManager: WebSocket connection established")
        resetReconnectionState()
        lastSuccessfulConnection = Date()
        updateConnectionQuality()
    }
    
    /// Called when WebSocket disconnects
    func handleConnectionLost() {
        recordDisconnection()
        updateConnectionQuality()
    }
    
    /// Cache a message for reconnection comparison
    func cacheMessage(_ message: Message) {
        messageCache.append(CachedMessage(from: message))
    }
    
    /// Check if a message was already received (for deduplication after reconnect)
    func wasMessageReceived(_ message: Message) -> Bool {
        let cached = CachedMessage(from: message)
        return messageCache.contains(cached)
    }
    
    /// Get recent cached messages for comparison
    func getRecentMessages(count: Int = 10) -> [CachedMessage] {
        return Array(messageCache.suffix(count))
    }
    
    /// Record a disconnection event
    func recordDisconnection() {
        disconnectionEvents.append(Date())
        updateConnectionQuality()
        logConnectionEvent(.disconnected)
    }
    
    /// Record a connection attempt
    func recordConnectionAttempt() {
        connectionAttempts.append(Date())
    }
    
    // MARK: - Private Methods
    
    private func setupNetworkMonitoring() {
        pathMonitor = NWPathMonitor()
        pathMonitor?.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.handleNetworkPathUpdate(path)
            }
        }
        pathMonitor?.start(queue: monitorQueue)
    }
    
    private func handleNetworkPathUpdate(_ path: NWPath) {
        if path.status == .satisfied {
            // Network is available
            if connectionQuality == .offline {
                connectionQuality = .unknown
                updateConnectionQuality()
            }
        } else {
            // Network is not available
            connectionQuality = .offline
            logConnectionEvent(.qualityChanged, quality: .offline)
        }
    }
    
    private func startQualityMonitoring() {
        qualityMonitor = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.updateConnectionQuality()
        }
    }
    
    private func updateConnectionQuality() {
        let now = Date()
        let recentWindow: TimeInterval = 300 // 5 minutes
        
        // First check if WebSocket is actually connected
        let isWebSocketConnected = WebSocketService.shared.isConnected
        
        print("🔍 ConnectionReliabilityManager: Updating connection quality")
        print("   WebSocket connected: \(isWebSocketConnected)")
        print("   Current quality: \(connectionQuality)")
        
        // If WebSocket is not connected, we're offline
        if !isWebSocketConnected {
            if connectionQuality != .offline {
                print("   Setting quality to OFFLINE (WebSocket not connected)")
                connectionQuality = .offline
                logConnectionEvent(.qualityChanged, quality: .offline)
            }
            return
        }
        
        // Count recent disconnections
        let recentDisconnections = disconnectionEvents.filter { 
            now.timeIntervalSince($0) < recentWindow 
        }.count
        
        // Calculate uptime percentage
        let uptimePercentage: Double
        if let lastConnection = lastSuccessfulConnection {
            let totalTime = now.timeIntervalSince(lastConnection)
            let disconnectionTime = Double(recentDisconnections) * 30.0 // Assume 30s per disconnection
            uptimePercentage = max(0, (totalTime - disconnectionTime) / totalTime)
        } else {
            uptimePercentage = 0
        }
        
        print("   Recent disconnections: \(recentDisconnections)")
        print("   Uptime percentage: \(uptimePercentage)")
        print("   Last successful connection: \(lastSuccessfulConnection?.description ?? "none")")
        
        // Determine quality based on metrics
        let oldQuality = connectionQuality
        
        if recentDisconnections == 0 && uptimePercentage >= 0.99 {
            connectionQuality = .excellent
        } else if recentDisconnections <= 1 && uptimePercentage >= 0.95 {
            connectionQuality = .good
        } else if recentDisconnections <= 3 && uptimePercentage >= 0.85 {
            connectionQuality = .fair
        } else if uptimePercentage >= 0.5 {
            connectionQuality = .poor
        } else {
            connectionQuality = .poor // Keep as poor instead of offline if WebSocket is connected
        }
        
        if oldQuality != connectionQuality {
            print("   Quality changed: \(oldQuality) → \(connectionQuality)")
            logConnectionEvent(.qualityChanged, quality: connectionQuality)
        } else {
            print("   Quality unchanged: \(connectionQuality)")
        }
    }
    
    private func performReconnection(action: @escaping () -> Void) {
        recordConnectionAttempt()
        action()
    }
    
    private func logConnectionEvent(_ type: ConnectionEvent.EventType, quality: ConnectionQuality? = nil, details: String? = nil) {
        let event = ConnectionEvent(
            timestamp: Date(),
            type: type,
            quality: quality ?? connectionQuality,
            details: details
        )
        
        DispatchQueue.main.async {
            self.connectionHistory.append(event)
            
            // Keep only last 100 events
            if self.connectionHistory.count > 100 {
                self.connectionHistory.removeFirst(self.connectionHistory.count - 100)
            }
        }
        
        print("🌐 Connection event: \(type) - \(quality?.rawValue ?? connectionQuality.rawValue) - \(details ?? "")")
    }
}

// MARK: - Circular Buffer for Message Cache

struct CircularBuffer<T> {
    private var buffer: [T?]
    private var writeIndex = 0
    private var count = 0
    private let capacity: Int
    
    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = Array(repeating: nil, count: capacity)
    }
    
    mutating func append(_ element: T) {
        buffer[writeIndex] = element
        writeIndex = (writeIndex + 1) % capacity
        count = min(count + 1, capacity)
    }
    
    func contains(_ element: T) -> Bool where T: Equatable {
        for i in 0..<count {
            let index = (writeIndex - count + i + capacity) % capacity
            if buffer[index] == element {
                return true
            }
        }
        return false
    }
    
    func suffix(_ k: Int) -> [T] {
        let k = min(k, count)
        var result: [T] = []
        
        for i in 0..<k {
            let index = (writeIndex - k + i + capacity) % capacity
            if let element = buffer[index] {
                result.append(element)
            }
        }
        
        return result
    }
}
