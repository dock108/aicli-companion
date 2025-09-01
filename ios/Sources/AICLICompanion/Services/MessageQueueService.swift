import Foundation
import Combine

/// Service for interacting with server-side message queue
@available(iOS 16.0, macOS 13.0, *)
class MessageQueueService: ObservableObject {
    static let shared = MessageQueueService()
    
    // MARK: - Published Properties
    
    @Published var queueStatus: QueueStatus?
    @Published var queuedMessages: [QueuedMessage] = []
    @Published var deadLetterMessages: [QueuedMessage] = []
    @Published var isLoading: Bool = false
    @Published var error: String?
    @Published var metrics: QueueMetrics?
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    private let refreshTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    
    private var baseURL: String {
        // Get the base URL from the current connection
        if let connection = SettingsManager.shared.currentConnection {
            let scheme = connection.isSecure ? "https" : "http"
            return "\(scheme)://\(connection.address):\(connection.port)"
        }
        // Fallback to localhost
        return "http://localhost:3456"
    }
    
    // MARK: - Types
    
    struct QueueStatus: Codable {
        let sessionId: String
        let queue: QueueInfo
        let success: Bool
        let timestamp: String
        
        struct QueueInfo: Codable {
            let length: Int
            let processing: Bool
            let paused: Bool
            let currentMessage: CurrentMessage?
            let stats: QueueStats
            let deadLetterQueueSize: Int
        }
        
        struct CurrentMessage: Codable {
            let id: String
            let priority: Int
            let timestamp: TimeInterval
        }
        
        struct QueueStats: Codable {
            let messagesQueued: Int
            let messagesProcessed: Int
            let messagesFailed: Int
            let averageProcessingTime: Double
            let queueDepth: Int
            let lastProcessedAt: TimeInterval?
        }
    }
    
    struct QueuedMessage: Codable, Identifiable {
        let id: String
        let priority: Int
        let priorityName: String
        let timestamp: TimeInterval
        let status: String
        let attempts: Int
        let error: String?
        let metadata: MessageMetadata?
        
        struct MessageMetadata: Codable {
            let requestId: String?
            let timestamp: String?
        }
        
        var priorityColor: String {
            switch priorityName {
            case "HIGH": return "red"
            case "LOW": return "gray"
            default: return "blue"
            }
        }
        
        var prioritySymbol: String {
            switch priorityName {
            case "HIGH": return "exclamationmark.triangle.fill"
            case "LOW": return "arrow.down.circle"
            default: return "circle.fill"
            }
        }
    }
    
    struct QueueMetrics: Codable {
        let totalQueues: Int
        let totalMessages: Int
        let totalProcessing: Int
        let totalPaused: Int
        let totalDeadLetter: Int
        let queues: [String: QueueSummary]
        
        struct QueueSummary: Codable {
            let queueLength: Int
            let processing: Bool
            let paused: Bool
            let stats: QueueStatus.QueueStats
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        setupAutoRefresh()
    }
    
    // MARK: - Public Methods
    
    /// Fetch queue status for a session
    func fetchQueueStatus(for sessionId: String) async {
        isLoading = true
        error = nil
        
        guard let url = URL(string: "\(baseURL)/api/queue/\(sessionId)/status") else {
            error = "Invalid URL"
            isLoading = false
            return
        }
        
        do {
            var request = URLRequest(url: url)
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            
            if httpResponse.statusCode == 404 {
                // Queue doesn't exist yet
                queueStatus = nil
                queuedMessages = []
                deadLetterMessages = []
            } else if httpResponse.statusCode == 200 {
                let status = try JSONDecoder().decode(QueueStatus.self, from: data)
                await MainActor.run {
                    self.queueStatus = status
                }
                
                // Fetch messages if queue exists
                await fetchQueueMessages(for: sessionId)
            } else {
                throw URLError(.badServerResponse)
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                print("❌ Failed to fetch queue status: \(error)")
            }
        }
        
        await MainActor.run {
            isLoading = false
        }
    }
    
    /// Fetch queued messages for a session
    func fetchQueueMessages(for sessionId: String) async {
        guard let url = URL(string: "\(baseURL)/api/queue/\(sessionId)/messages") else {
            return
        }
        
        do {
            var request = URLRequest(url: url)
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return
            }
            
            struct MessagesResponse: Codable {
                let messages: Messages
                
                struct Messages: Codable {
                    let pending: [QueuedMessage]
                    let deadLetter: [QueuedMessage]
                }
            }
            
            let messagesResponse = try JSONDecoder().decode(MessagesResponse.self, from: data)
            await MainActor.run {
                self.queuedMessages = messagesResponse.messages.pending
                self.deadLetterMessages = messagesResponse.messages.deadLetter
            }
        } catch {
            print("❌ Failed to fetch queue messages: \(error)")
        }
    }
    
    /// Pause queue processing
    func pauseQueue(for sessionId: String) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/queue/\(sessionId)/pause") else {
            return false
        }
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return false
            }
            
            await fetchQueueStatus(for: sessionId)
            return true
        } catch {
            print("❌ Failed to pause queue: \(error)")
            return false
        }
    }
    
    /// Resume queue processing
    func resumeQueue(for sessionId: String) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/queue/\(sessionId)/resume") else {
            return false
        }
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return false
            }
            
            await fetchQueueStatus(for: sessionId)
            return true
        } catch {
            print("❌ Failed to resume queue: \(error)")
            return false
        }
    }
    
    /// Clear all queued messages
    func clearQueue(for sessionId: String) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/queue/\(sessionId)/clear") else {
            return false
        }
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return false
            }
            
            await fetchQueueStatus(for: sessionId)
            return true
        } catch {
            print("❌ Failed to clear queue: \(error)")
            return false
        }
    }
    
    /// Update message priority
    func updateMessagePriority(sessionId: String, messageId: String, priority: Int) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/queue/\(sessionId)/message/\(messageId)/priority") else {
            return false
        }
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let body = ["priority": priority]
            request.httpBody = try JSONEncoder().encode(body)
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return false
            }
            
            await fetchQueueMessages(for: sessionId)
            return true
        } catch {
            print("❌ Failed to update message priority: \(error)")
            return false
        }
    }
    
    /// Fetch global queue metrics
    func fetchMetrics() async {
        guard let url = URL(string: "\(baseURL)/api/queue/metrics") else {
            return
        }
        
        do {
            var request = URLRequest(url: url)
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return
            }
            
            struct MetricsResponse: Codable {
                let metrics: QueueMetrics
            }
            
            let metricsResponse = try JSONDecoder().decode(MetricsResponse.self, from: data)
            await MainActor.run {
                self.metrics = metricsResponse.metrics
            }
        } catch {
            print("❌ Failed to fetch queue metrics: \(error)")
        }
    }
    
    /// Start auto-refresh for a session
    func startMonitoring(sessionId: String) {
        refreshTimer
            .sink { _ in
                Task {
                    await self.fetchQueueStatus(for: sessionId)
                }
            }
            .store(in: &cancellables)
    }
    
    /// Stop auto-refresh
    func stopMonitoring() {
        cancellables.removeAll()
    }
    
    // MARK: - Private Methods
    
    private func setupAutoRefresh() {
        // Auto-refresh metrics every 10 seconds
        Timer.publish(every: 10, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                Task {
                    await self.fetchMetrics()
                }
            }
            .store(in: &cancellables)
    }
}

// MARK: - Priority Helpers

extension MessageQueueService {
    enum MessagePriority: Int {
        case high = 0
        case normal = 1
        case low = 2
        
        var name: String {
            switch self {
            case .high: return "HIGH"
            case .normal: return "NORMAL"
            case .low: return "LOW"
            }
        }
        
        var color: String {
            switch self {
            case .high: return "red"
            case .normal: return "blue"
            case .low: return "gray"
            }
        }
        
        var symbol: String {
            switch self {
            case .high: return "exclamationmark.triangle.fill"
            case .normal: return "circle.fill"
            case .low: return "arrow.down.circle"
            }
        }
    }
}
