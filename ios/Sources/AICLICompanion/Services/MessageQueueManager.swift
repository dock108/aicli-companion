import Foundation
import Combine

/// Manages message queue operations and tracking
@available(iOS 16.0, macOS 13.0, *)
class MessageQueueManager: ObservableObject {
    static let shared = MessageQueueManager()
    
    // MARK: - Published Properties
    
    @Published var queuedMessageCount: Int = 0
    @Published var isReceivingQueued: Bool = false
    @Published var oldestQueuedTimestamp: Date?
    @Published var queuedMessages: [QueuedMessageInfo] = []
    
    // MARK: - Private Properties
    
    private var messageQueue: [QueuedMessageInfo] = []
    private let queueLock = NSLock()
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Types
    
    struct QueuedMessageInfo {
        let messageId: String
        let sessionId: String
        let queuedAt: Date
        let priority: Int
        var deliveredAt: Date?
        
        var deliveryDelay: TimeInterval? {
            guard let delivered = deliveredAt else { return nil }
            return delivered.timeIntervalSince(queuedAt)
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        setupWebSocketHandlers()
    }
    
    // MARK: - Public Methods
    
    /// Track a message being queued
    func trackQueuedMessage(messageId: String, sessionId: String, priority: Int = 0) {
        queueLock.lock()
        defer { queueLock.unlock() }
        
        let queuedInfo = QueuedMessageInfo(
            messageId: messageId,
            sessionId: sessionId,
            queuedAt: Date(),
            priority: priority
        )
        
        messageQueue.append(queuedInfo)
        updateQueueStatus()
        
        print("📬 Message queued: \(messageId) for session \(sessionId)")
    }
    
    /// Mark a message as delivered from queue
    func markMessageDelivered(messageId: String) {
        queueLock.lock()
        defer { queueLock.unlock() }
        
        if let index = messageQueue.firstIndex(where: { $0.messageId == messageId }) {
            messageQueue[index].deliveredAt = Date()
            
            let delay = messageQueue[index].deliveryDelay ?? 0
            print("✅ Message delivered from queue: \(messageId) (delay: \(String(format: "%.1f", delay))s)")
            
            // Remove delivered messages after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.cleanupDeliveredMessages()
            }
        }
        
        updateQueueStatus()
    }
    
    /// Get queue info for a specific session
    func getQueueInfo(for sessionId: String) -> (count: Int, oldestTimestamp: Date?) {
        queueLock.lock()
        defer { queueLock.unlock() }
        
        let sessionMessages = messageQueue.filter { 
            $0.sessionId == sessionId && $0.deliveredAt == nil 
        }
        
        let oldest = sessionMessages.min { $0.queuedAt < $1.queuedAt }?.queuedAt
        
        return (sessionMessages.count, oldest)
    }
    
    /// Clear queue for a session
    func clearQueue(for sessionId: String) {
        queueLock.lock()
        defer { queueLock.unlock() }
        
        messageQueue.removeAll { $0.sessionId == sessionId }
        updateQueueStatus()
    }
    
    /// Check if currently processing queued messages
    func startReceivingQueued() {
        DispatchQueue.main.async {
            self.isReceivingQueued = true
        }
    }
    
    /// Mark queue processing as complete
    func finishReceivingQueued() {
        DispatchQueue.main.async {
            self.isReceivingQueued = false
        }
    }
    
    // MARK: - Private Methods
    
    private func updateQueueStatus() {
        let undelivered = messageQueue.filter { $0.deliveredAt == nil }
        
        DispatchQueue.main.async {
            self.queuedMessageCount = undelivered.count
            self.oldestQueuedTimestamp = undelivered.min { $0.queuedAt < $1.queuedAt }?.queuedAt
            self.queuedMessages = self.messageQueue
        }
    }
    
    private func cleanupDeliveredMessages() {
        queueLock.lock()
        defer { queueLock.unlock() }
        
        // Remove messages that have been delivered more than 2 seconds ago
        let cutoff = Date().addingTimeInterval(-2)
        messageQueue.removeAll { message in
            if let deliveredAt = message.deliveredAt {
                return deliveredAt < cutoff
            }
            return false
        }
        
        updateQueueStatus()
    }
    
    private func setupWebSocketHandlers() {
        // Listen for queue-related messages
        WebSocketService.shared.setMessageHandler(for: .progress) { [weak self] message in
            if case .progress(let progress) = message.data {
                if progress.stage == "queue_processing" {
                    self?.handleQueueProgress(progress)
                }
            }
        }
    }
    
    private func handleQueueProgress(_ progress: ProgressResponse) {
        if progress.message.contains("Processing queued messages") {
            startReceivingQueued()
        } else if progress.message.contains("Queue processing complete") {
            finishReceivingQueued()
        }
        
        // Extract queue count from progress message if available
        do {
            let regex = try NSRegularExpression(pattern: "(\\d+) queued messages?", options: [])
            if let match = regex.firstMatch(in: progress.message, options: [], range: NSRange(location: 0, length: progress.message.utf16.count)) {
                if let range = Range(match.range(at: 1), in: progress.message),
                   let count = Int(progress.message[range]) {
                    DispatchQueue.main.async {
                        self.queuedMessageCount = count
                    }
                }
            }
        } catch {
            // Ignore regex errors
        }
    }
}

// MARK: - Message Extension for Queue Support

extension Message {
    /// Create metadata with queue information
    static func createQueuedMetadata(
        sessionId: String,
        duration: TimeInterval = 0,
        queuedAt: Date = Date()
    ) -> AICLIMessageMetadata {
        return AICLIMessageMetadata(
            sessionId: sessionId,
            duration: duration,
            queuedAt: queuedAt,
            deliveredAt: nil
        )
    }
    
    /// Update metadata when delivered from queue
    mutating func markDeliveredFromQueue() {
        if let meta = metadata, meta.queuedAt != nil {
            metadata = AICLIMessageMetadata(
                sessionId: meta.sessionId,
                duration: meta.duration,
                cost: meta.cost,
                tools: meta.tools,
                queuedAt: meta.queuedAt,
                deliveredAt: Date(),
                queuePriority: meta.queuePriority
            )
        }
    }
}