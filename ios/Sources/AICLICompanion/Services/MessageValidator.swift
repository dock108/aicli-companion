import Foundation

/// Validates messages received from the server to filter out invalid or malformed content
@available(iOS 16.0, macOS 13.0, *)
struct MessageValidator {
    
    /// Validate a stream chunk before processing
    static func isValidStreamChunk(_ chunk: StreamChunk) -> Bool {
        // Filter empty content chunks
        if chunk.type == "content" || chunk.type == "text" {
            let trimmedContent = chunk.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedContent.isEmpty {
                print("🚫 Filtering empty content chunk")
                return false
            }
        }
        
        // Filter incomplete tool use chunks
        if chunk.type == "tool_use" {
            if chunk.metadata?.toolName?.isEmpty ?? true {
                print("🚫 Filtering incomplete tool use chunk")
                return false
            }
        }
        
        // Check for required fields based on chunk type
        switch chunk.type {
        case "content", "text", "code", "header", "section", "list":
            // These types use the main content field
            return !chunk.content.isEmpty
            
        case "tool_use":
            // Must have tool name in metadata
            return chunk.metadata?.toolName != nil
            
        case "tool_result":
            // Tool results should have content
            return !chunk.content.isEmpty
            
        case "complete", "divider":
            // These chunk types don't require content
            return true
            
        default:
            // Unknown chunk types are allowed through
            return true
        }
    }
    
    /// Validate a WebSocket message
    static func isValidWebSocketMessage(_ message: WebSocketMessage) -> Bool {
        // Must have a type
        guard !message.type.rawValue.isEmpty else {
            print("🚫 Message missing type")
            return false
        }
        
        // Validate based on message type
        switch message.data {
        case .streamChunk(let chunkResponse):
            return isValidStreamChunk(chunkResponse.chunk)
            
        case .assistantMessage(let content):
            // Assistant messages should have non-empty content
            if content.content.isEmpty {
                print("🚫 Filtering empty assistant message")
                return false
            }
            return true
            
        case .toolUse(let tool):
            // Tool use must have a name
            return !tool.toolName.isEmpty
            
        case .toolResult(let result):
            // Tool results must have result or error
            return result.result != nil || result.error != nil
            
        case .error(let error):
            // Errors must have a message
            return !error.message.isEmpty
            
        default:
            // Other message types are allowed
            return true
        }
    }
    
    /// Filter duplicate messages based on content and timestamp
    static func filterDuplicates(messages: [Message], within timeWindow: TimeInterval = 1.0) -> [Message] {
        var filtered: [Message] = []
        var seenContent: Set<String> = []
        
        for message in messages {
            // Create a content hash for duplicate detection
            let contentHash = "\(message.content):\(message.sender)"
            
            // Check if we've seen this exact content recently
            let isDuplicate = filtered.contains { existingMessage in
                let timeDiff = abs(message.timestamp.timeIntervalSince(existingMessage.timestamp))
                let sameContent = existingMessage.content == message.content
                let sameRole = existingMessage.sender == message.sender
                
                return sameContent && sameRole && timeDiff < timeWindow
            }
            
            if !isDuplicate && !seenContent.contains(contentHash) {
                filtered.append(message)
                seenContent.insert(contentHash)
            } else {
                print("🚫 Filtering duplicate message: \(message.content.prefix(50))...")
            }
        }
        
        return filtered
    }
    
    /// Validate message order and fix if necessary
    static func ensureMessageOrder(messages: [Message]) -> [Message] {
        // Sort by timestamp to ensure proper order
        return messages.sorted { $0.timestamp < $1.timestamp }
    }
    
    /// Validate and clean message content
    static func cleanMessageContent(_ content: String) -> String {
        // Remove excessive whitespace
        let cleaned = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
        
        // Remove null characters or other control characters
        let controlCharacterSet = CharacterSet.controlCharacters
            .subtracting(CharacterSet.newlines)
            .subtracting(CharacterSet(charactersIn: "\t"))
        
        let filtered = cleaned.unicodeScalars.filter { scalar in
            !controlCharacterSet.contains(scalar)
        }
        
        return String(String.UnicodeScalarView(filtered))
    }
    
    /// Check if a message should be displayed in the UI
    static func shouldDisplayMessage(_ message: Message) -> Bool {
        // Filter out empty messages
        let cleanContent = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanContent.isEmpty {
            return false
        }
        
        // Filter out system messages that shouldn't be shown
        if message.sender == .system {
            // Check for internal system messages
            let internalPrefixes = [
                "[System]",
                "[Debug]",
                "[Internal]"
            ]
            
            if internalPrefixes.contains(where: { message.content.hasPrefix($0) }) {
                return false
            }
        }
        
        return true
    }
}