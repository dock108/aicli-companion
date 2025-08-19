import Foundation

// MARK: - Conversation Storage Operations

class ConversationStorage {
    private let fileManager = FileManager.default
    private let baseURL: URL
    
    init() throws {
        let documentsURL = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        self.baseURL = documentsURL.appendingPathComponent("AICLIConversations", isDirectory: true)
        
        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: baseURL.path) {
            try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true, attributes: nil)
        }
    }
    
    // MARK: - Core Storage Operations
    
    func save(_ conversation: Conversation) throws {
        let conversationURL = baseURL.appendingPathComponent("\(conversation.id.uuidString).json")
        let data = try JSONEncoder().encode(conversation)
        try data.write(to: conversationURL)
    }
    
    func load(id: UUID) throws -> Conversation {
        let conversationURL = baseURL.appendingPathComponent("\(id.uuidString).json")
        let data = try Data(contentsOf: conversationURL)
        return try JSONDecoder().decode(Conversation.self, from: data)
    }
    
    func delete(id: UUID) throws {
        let conversationURL = baseURL.appendingPathComponent("\(id.uuidString).json")
        try fileManager.removeItem(at: conversationURL)
    }
    
    func loadAll() throws -> [Conversation] {
        let contents = try fileManager.contentsOfDirectory(atPath: baseURL.path)
        let jsonFiles = contents.filter { $0.hasSuffix(".json") }
        
        var conversations: [Conversation] = []
        for filename in jsonFiles {
            do {
                let conversationURL = baseURL.appendingPathComponent(filename)
                let data = try Data(contentsOf: conversationURL)
                let conversation = try JSONDecoder().decode(Conversation.self, from: data)
                conversations.append(conversation)
            } catch {
                print("Failed to load conversation from \(filename): \(error)")
            }
        }
        
        return conversations.sorted { $0.updatedAt > $1.updatedAt }
    }
    
    func exists(id: UUID) -> Bool {
        let conversationURL = baseURL.appendingPathComponent("\(id.uuidString).json")
        return fileManager.fileExists(atPath: conversationURL.path)
    }
    
    // MARK: - Storage Utilities
    
    func getTotalStorageSize() throws -> Int {
        let contents = try fileManager.contentsOfDirectory(atPath: baseURL.path)
        var totalSize = 0
        
        for filename in contents {
            let fileURL = baseURL.appendingPathComponent(filename)
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            if let fileSize = attributes[.size] as? Int {
                totalSize += fileSize
            }
        }
        
        return totalSize
    }
    
    func cleanupOldConversations(keepingRecent count: Int) throws {
        let conversations = try loadAll()
        let conversationsToDelete = Array(conversations.dropFirst(count))
        
        for conversation in conversationsToDelete {
            try delete(id: conversation.id)
        }
    }
    
    func getStorageURL() -> URL {
        return baseURL
    }
}
