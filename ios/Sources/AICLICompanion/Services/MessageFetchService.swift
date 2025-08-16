import Foundation
import SwiftUI

/// Service for fetching messages from the server (iMessage-style pattern)
@available(iOS 16.0, macOS 13.0, *)
class MessageFetchService: ObservableObject {
    static let shared = MessageFetchService()
    
    // MARK: - Properties
    
    private let cache = NSCache<NSString, CachedMessage>()
    private var fetchQueue = DispatchQueue(label: "com.aiclicompanion.messagefetch", attributes: .concurrent)
    private var activeFetches = Set<String>() // Track in-progress fetches to avoid duplicates
    
    // MARK: - Types
    
    private class CachedMessage: NSObject {
        let message: Message
        let timestamp: Date
        
        init(message: Message, timestamp: Date = Date()) {
            self.message = message
            self.timestamp = timestamp
        }
        
        var isExpired: Bool {
            Date().timeIntervalSince(timestamp) > 3600 // 1 hour cache
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        setupCache()
    }
    
    private func setupCache() {
        // Configure cache limits
        cache.countLimit = 100 // Max 100 messages in cache
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB max cache size
    }
    
    // MARK: - Public Methods
    
    /// Fetch a message by ID from the server
    func fetchMessage(sessionId: String, messageId: String) async throws -> Message {
        let cacheKey = "\(sessionId):\(messageId)" as NSString
        
        // Check cache first
        if let cached = cache.object(forKey: cacheKey), !cached.isExpired {
            print("📦 Message fetched from cache: \(messageId)")
            return cached.message
        }
        
        // Check if already fetching
        if activeFetches.contains(cacheKey as String) {
            print("⏳ Already fetching message: \(messageId)")
            // Wait a bit and try cache again
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            if let cached = cache.object(forKey: cacheKey) {
                return cached.message
            }
        }
        
        // Mark as fetching
        activeFetches.insert(cacheKey as String)
        defer { activeFetches.remove(cacheKey as String) }
        
        print("🌐 Fetching message from server: \(messageId)")
        
        // Use AICLIService to fetch the message
        let message = try await AICLIService.shared.fetchMessage(
            sessionId: sessionId,
            messageId: messageId
        )
        
        // Cache the message
        cacheMessage(message, key: cacheKey)
        
        print("✅ Message fetched successfully: \(messageId)")
        return message
    }
    
    /// Fetch multiple messages for a session
    func fetchMessages(sessionId: String, limit: Int = 50, offset: Int = 0) async throws -> [MessagePreview] {
        // This would typically be implemented with a proper API call
        // For now, return empty array as we don't have a list endpoint in AICLIService
        print("🌐 Fetching message list for session: \(sessionId)")
        return []
    }
    
    // MARK: - Private Methods
    
    private func cacheMessage(_ message: Message, key: NSString) {
        let cached = CachedMessage(message: message)
        let cost = message.content.count // Use content length as cost
        cache.setObject(cached, forKey: key, cost: cost)
        print("💾 Cached message: \(key)")
    }
    
    public func getCachedMessage(sessionId: String, messageId: String) -> Message? {
        let cacheKey = "\(sessionId):\(messageId)" as NSString
        return cache.object(forKey: cacheKey)?.message
    }
    
    /// Clear all cached messages
    public func clearCache() {
        cache.removeAllObjects()
        print("🧹 Message cache cleared")
    }
    
    /// Preemptively fetch a message (fire and forget)
    public func prefetchMessage(sessionId: String, messageId: String) {
        Task {
            do {
                _ = try await fetchMessage(sessionId: sessionId, messageId: messageId)
            } catch {
                print("⚠️ Prefetch failed for message \(messageId): \(error)")
            }
        }
    }
}

// MARK: - Response Types

struct MessageFetchResponse: Codable {
    let success: Bool
    let message: FetchedMessage
}

struct FetchedMessage: Codable {
    let id: String
    let content: String
    let timestamp: String
    let sessionId: String
    let type: String?
    let metadata: [String: String]?
}

struct MessageListResponse: Codable {
    let success: Bool
    let messages: [MessagePreview]
    let total: Int
    let hasMore: Bool
    let sessionId: String
}

struct MessagePreview: Codable, Identifiable {
    let id: String
    let preview: String
    let timestamp: String
    let type: String
    let length: Int
}
