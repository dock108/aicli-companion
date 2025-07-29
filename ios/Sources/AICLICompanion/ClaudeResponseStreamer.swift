import Foundation
import Combine

/// Service that manages streaming Claude responses by collecting chunks and building complete messages
@available(iOS 13.0, macOS 10.15, *)
class ClaudeResponseStreamer: ObservableObject {
    @Published var currentMessage: Message?
    @Published var streamingChunks: [StreamChunk] = []
    @Published var isStreaming = false
    
    var currentSessionId: String?
    private var messageBuilder = MessageBuilder()
    private var chunksReceived = 0
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupNotifications()
    }
    
    private func setupNotifications() {
        // Listen for stream chunk notifications from WebSocketService
        NotificationCenter.default.publisher(for: .streamChunkReceived)
            .compactMap { $0.userInfo?["chunk"] as? StreamChunk }
            .sink { [weak self] chunk in
                self?.handleStreamChunk(chunk)
            }
            .store(in: &cancellables)
    }
    
    /// Start a new streaming session
    func startStreaming(sessionId: String) {
        print("🎬 Starting streaming session: \(sessionId)")
        currentSessionId = sessionId
        isStreaming = true
        streamingChunks.removeAll()
        chunksReceived = 0
        messageBuilder.reset()
        
        // Create initial message placeholder
        currentMessage = Message(
            content: "",
            sender: .assistant,
            type: .text,
            streamingState: .streaming
        )
    }
    
    /// Handle an incoming stream chunk
    func handleStreamChunk(_ chunk: StreamChunk) {
        guard isStreaming else { return }
        
        chunksReceived += 1
        streamingChunks.append(chunk)
        
        print("📦 Processing chunk #\(chunksReceived): \(chunk.type)")
        
        // Add chunk to message builder
        messageBuilder.addChunk(chunk)
        
        // Update current message with built content
        if let builtContent = messageBuilder.buildContent() {
            currentMessage?.content = builtContent
        }
        
        // If this is the final chunk, finalize the message
        if chunk.isFinal {
            finalizeStreaming()
        }
    }
    
    /// Finalize the streaming session
    private func finalizeStreaming() {
        print("✅ Finalizing streaming session with \(chunksReceived) chunks")
        
        isStreaming = false
        
        // Mark message as complete
        currentMessage?.streamingState = .complete
        
        // Emit completion notification
        NotificationCenter.default.post(
            name: .streamingComplete,
            object: nil,
            userInfo: [
                "sessionId": currentSessionId ?? "",
                "totalChunks": chunksReceived,
                "message": currentMessage as Any
            ]
        )
        
        // Reset for next session
        currentSessionId = nil
    }
    
    /// Cancel the current streaming session
    func cancelStreaming() {
        if isStreaming {
            print("❌ Cancelling streaming session")
            isStreaming = false
            currentMessage?.streamingState = .cancelled
            currentSessionId = nil
        }
    }
}

// MARK: - Message Builder

private class MessageBuilder {
    private var sections: [MessageSection] = []
    private var currentSection: MessageSection?
    
    struct MessageSection {
        let type: String
        var content: String
        var metadata: [String: Any]
    }
    
    func reset() {
        sections.removeAll()
        currentSection = nil
    }
    
    func addChunk(_ chunk: StreamChunk) {
        switch chunk.type {
        case "section", "header":
            // Start a new section
            finishCurrentSection()
            currentSection = MessageSection(
                type: chunk.type,
                content: chunk.content,
                metadata: ["level": chunk.metadata?.level ?? 1]
            )
            
        case "code":
            // Add code block
            finishCurrentSection()
            let codeSection = MessageSection(
                type: "code",
                content: chunk.content,
                metadata: ["language": chunk.metadata?.language ?? "text"]
            )
            sections.append(codeSection)
            
        case "list":
            // Add list
            finishCurrentSection()
            let listSection = MessageSection(
                type: "list",
                content: chunk.content,
                metadata: [:]
            )
            sections.append(listSection)
            
        case "divider":
            // Add divider
            finishCurrentSection()
            sections.append(MessageSection(type: "divider", content: "", metadata: [:]))
            
        case "text":
            // Add to current section or create new text section
            if currentSection == nil {
                currentSection = MessageSection(type: "text", content: "", metadata: [:])
            }
            if !currentSection!.content.isEmpty {
                currentSection!.content += "\n\n"
            }
            currentSection!.content += chunk.content
            
        default:
            // Unknown type, treat as text
            if currentSection == nil {
                currentSection = MessageSection(type: "text", content: "", metadata: [:])
            }
            currentSection!.content += chunk.content
        }
    }
    
    private func finishCurrentSection() {
        if let section = currentSection {
            sections.append(section)
            currentSection = nil
        }
    }
    
    func buildContent() -> String? {
        // Finish any pending section
        finishCurrentSection()
        
        guard !sections.isEmpty else { return nil }
        
        var output = ""
        
        for (index, section) in sections.enumerated() {
            if index > 0 && section.type != "divider" {
                output += "\n\n"
            }
            
            switch section.type {
            case "section":
                let level = section.metadata["level"] as? Int ?? 1
                if level == 1 {
                    output += "**\(section.content)**"
                } else {
                    output += "*\(section.content)*"
                }
                
            case "header":
                let level = section.metadata["level"] as? Int ?? 1
                let prefix = String(repeating: "#", count: level)
                output += "\(prefix) \(section.content)"
                
            case "code":
                let language = section.metadata["language"] as? String ?? ""
                output += "```\(language)\n\(section.content)\n```"
                
            case "list":
                output += section.content
                
            case "divider":
                output += "---"
                
            case "text":
                output += section.content
                
            default:
                output += section.content
            }
        }
        
        return output
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let streamChunkReceived = Notification.Name("streamChunkReceived")
    static let streamingComplete = Notification.Name("streamingComplete")
}

// MARK: - Streaming State

extension Message {
    enum StreamingState: Codable {
        case none
        case streaming
        case complete
        case cancelled
    }
}