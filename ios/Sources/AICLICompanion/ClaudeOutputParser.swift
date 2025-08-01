import Foundation

/// Parser for Claude's structured output
/// Detects and extracts user-facing content from Claude's JSON responses
@available(iOS 16.0, macOS 13.0, *)
class ClaudeOutputParser {
    
    /// Attempts to parse Claude's JSON output and extract the user-facing content
    /// - Parameter text: Raw text that might contain JSON
    /// - Returns: Parsed result with extracted content or nil
    static func parseClaudeOutput(_ text: String) -> (content: String, metadata: [String: Any])? {
        guard !text.isEmpty else { return nil }
        
        // Try to find JSON blocks in the text
        let jsonPattern = #"\{[\s\S]*\}"#
        guard let regex = try? NSRegularExpression(pattern: jsonPattern, options: []),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)),
              let jsonRange = Range(match.range, in: text) else {
            return nil
        }
        
        let jsonString = String(text[jsonRange])
        
        // Try to parse the JSON
        guard let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] else {
            return nil
        }
        
        // Check if this looks like Claude's structured output
        guard isClaudeStructuredOutput(json) else { return nil }
        
        // Extract the user-facing content
        if let content = extractUserContent(from: json) {
            let metadata: [String: Any] = [
                "type": json["type"] as? String ?? "unknown",
                "hasThinking": json["thinking"] != nil,
                "hasToolUse": (json["tool_calls"] != nil || json["tools_used"] != nil)
            ]
            return (content: content, metadata: metadata)
        }
        
        return nil
    }
    
    /// Check if the parsed object looks like Claude's structured output
    private static func isClaudeStructuredOutput(_ json: [String: Any]) -> Bool {
        // Common patterns in Claude's JSON output
        return json["content"] != nil ||
               json["result"] != nil ||
               json["answer"] != nil ||
               json["thinking"] != nil ||
               json["reasoning"] != nil ||
               json["tool_calls"] != nil ||
               json["tools_used"] != nil ||
               json["type"] != nil
    }
    
    /// Extract user-facing content from Claude's structured output
    private static func extractUserContent(from json: [String: Any]) -> String? {
        // Priority order for content extraction
        if let content = json["content"] as? String {
            return content
        }
        
        if let result = json["result"] as? String {
            return result
        }
        
        if let answer = json["answer"] as? String {
            return answer
        }
        
        if let message = json["message"] as? String {
            return message
        }
        
        if let text = json["text"] as? String {
            return text
        }
        
        if let response = json["response"] as? String {
            return response
        }
        
        // For tool use, create a summary
        if let toolCalls = json["tool_calls"] as? [[String: Any]] ?? json["tools_used"] as? [[String: Any]] {
            let toolNames = toolCalls.compactMap { $0["name"] as? String ?? $0["tool"] as? String }
            if !toolNames.isEmpty {
                return "Using tools: \(toolNames.joined(separator: ", "))"
            }
        }
        
        return nil
    }
}