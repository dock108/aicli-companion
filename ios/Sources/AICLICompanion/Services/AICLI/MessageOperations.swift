import Foundation
import Combine

// MARK: - AICLI Message Operations

@available(iOS 16.0, macOS 13.0, *)
public class AICLIMessageOperations {
    // MARK: - Private Types
    private struct LargeMessageResponse: Codable {
        let id: String
        let content: String
        let timestamp: TimeInterval?  // Server sends milliseconds as number
        let metadata: [String: String]?
    }
    
    private let urlSession: URLSession
    private let connectionManager: AICLIConnectionManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    public init(urlSession: URLSession, connectionManager: AICLIConnectionManager) {
        self.urlSession = urlSession
        self.connectionManager = connectionManager
        setupDateFormatters()
    }
    
    // MARK: - Send Message
    
    func sendMessage(
        _ text: String,
        projectPath: String? = nil,
        attachments: [AttachmentData]? = nil,
        mode: ChatMode = .normal,
        completion: @escaping (Result<ClaudeChatResponse, AICLICompanionError>) -> Void
    ) {
        guard connectionManager.hasValidConnection,
              let baseURL = connectionManager.currentBaseURL else {
            completion(.failure(.noProjectSelected))
            return
        }
        
        guard let request = createChatRequest(baseURL: baseURL, message: text, projectPath: projectPath, attachments: attachments, mode: mode) else {
            completion(.failure(.invalidInput("Failed to create request")))
            return
        }
        
        let task = urlSession.dataTask(with: request) { [weak self] data, response, error in
            self?.handleChatResponse(data: data, response: response, error: error, projectPath: projectPath, completion: completion)
        }
        
        task.resume()
    }
    
    // MARK: - Fetch Message
    
    func fetchMessage(messageId: String) async throws -> Message {
        guard let fetchURL = connectionManager.buildURL(path: "/api/messages/\(messageId)") else {
            throw AICLICompanionError.invalidURL
        }
        
        let request = connectionManager.createAuthenticatedRequest(url: fetchURL)
        
        do {
            let (data, response) = try await urlSession.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AICLICompanionError.invalidResponse
            }
            
            switch httpResponse.statusCode {
            case 200...299:
                // Server returns a simpler structure, construct full Message
                let messageData = try decoder.decode(LargeMessageResponse.self, from: data)
                // Convert timestamp from milliseconds to Date
                let messageDate: Date
                if let timestamp = messageData.timestamp {
                    // Server sends milliseconds since epoch
                    messageDate = Date(timeIntervalSince1970: timestamp / 1000.0)
                } else {
                    messageDate = Date()
                }
                
                let message = Message(
                    id: UUID(uuidString: messageData.id) ?? UUID(),
                    content: messageData.content,
                    sender: .assistant,  // Large messages are always from Claude
                    timestamp: messageDate,
                    type: .markdown
                )
                return message
            case 401:
                throw AICLICompanionError.authenticationFailed
            case 404:
                throw AICLICompanionError.fileNotFound("Message not found")
            case 500...599:
                throw AICLICompanionError.serverError("Server error")
            default:
                throw AICLICompanionError.serverError("Unexpected status code: \(httpResponse.statusCode)")
            }
        } catch {
            if error is AICLICompanionError {
                throw error
            }
            throw AICLICompanionError.networkError(error.localizedDescription)
        }
    }
    
    // MARK: - Fetch Large Message
    
    func fetchLargeMessage(messageId: String) async throws -> (content: String, metadata: [String: Any]?) {
        // Fetch large message from server's message storage endpoint
        guard let messageURL = connectionManager.buildURL(path: "/api/messages/\(messageId)") else {
            throw AICLICompanionError.invalidURL
        }
        
        var request = connectionManager.createAuthenticatedRequest(url: messageURL, method: "GET")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AICLICompanionError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 {
                throw AICLICompanionError.notFound("Message not found")
            }
            throw AICLICompanionError.serverError("HTTP \(httpResponse.statusCode)")
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let result = json?["result"] as? [String: Any],
              let content = result["content"] as? String else {
            throw AICLICompanionError.invalidResponse
        }
        
        let metadata = result["metadata"] as? [String: Any]
        return (content: content, metadata: metadata)
    }
    
    // MARK: - Fetch Messages
    
    func fetchMessages(sessionId: String, completion: @escaping (Result<[Message], AICLICompanionError>) -> Void) {
        guard let messagesURL = connectionManager.buildURL(path: "/api/messages") else {
            completion(.failure(.invalidURL))
            return
        }
        
        var urlComponents = URLComponents(url: messagesURL, resolvingAgainstBaseURL: false)
        urlComponents?.queryItems = [
            URLQueryItem(name: "session_id", value: sessionId),
            URLQueryItem(name: "limit", value: "100")
        ]
        
        guard let finalURL = urlComponents?.url else {
            completion(.failure(.invalidURL))
            return
        }
        
        let request = connectionManager.createAuthenticatedRequest(url: finalURL)
        
        let task = urlSession.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(.networkError(error.localizedDescription)))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(.invalidResponse))
                return
            }
            
            guard let data = data else {
                completion(.failure(.invalidResponse))
                return
            }
            
            switch httpResponse.statusCode {
            case 200...299:
                do {
                    let messagesResponse = try self.decoder.decode(GetMessageHistoryResponse.self, from: data)
                    let messages = messagesResponse.messages.map { historyMessage in
                        Message(
                            id: UUID(uuidString: historyMessage.id) ?? UUID(),
                            content: historyMessage.content,
                            sender: historyMessage.sender,
                            timestamp: historyMessage.timestamp,
                            type: .text,
                            metadata: nil,
                            streamingState: nil,
                            requestId: nil,
                            richContent: nil
                        )
                    }
                    completion(.success(messages))
                } catch {
                    completion(.failure(.invalidResponse))
                }
            case 401:
                completion(.failure(.authenticationFailed))
            case 404:
                completion(.failure(.fileNotFound("Session not found")))
            case 500...599:
                completion(.failure(.serverError("Server error")))
            default:
                completion(.failure(.serverError("Unexpected status code: \(httpResponse.statusCode)")))
            }
        }
        
        task.resume()
    }
    
    // MARK: - Session Management
    
    private func getSessionId(for projectPath: String) -> String? {
        // Use SessionKeyManager to retrieve session IDs per project
        return SessionKeyManager.sessionId(for: projectPath)
    }
    
    public func storeSessionId(_ sessionId: String, for projectPath: String) {
        SessionKeyManager.storeSessionId(sessionId, for: projectPath)
        print("💾 Stored session ID \(sessionId) for project \(projectPath)")
    }
    
    func clearSessionId(for projectPath: String) {
        SessionKeyManager.clearSession(for: projectPath)
        print("🗑️ Cleared session ID for project \(projectPath)")
    }
    
    // MARK: - Private Helper Methods
    
    private func createChatRequest(baseURL: URL, message: String, projectPath: String?, attachments: [AttachmentData]? = nil, mode: ChatMode = .normal) -> URLRequest? {
        let chatURL = baseURL.appendingPathComponent("/api/chat")
        var request = connectionManager.createAuthenticatedRequest(url: chatURL, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // iOS needs a timeout to handle unresponsive server, but we rely on push notifications
        // for the actual response, so this is just for the initial request acknowledgment
        request.timeoutInterval = 120 // 2 minutes for server to acknowledge request
        
        var requestBody: [String: Any] = [
            "message": message,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "mode": mode.rawValue  // Include the mode in the request
        ]
        
        if let projectPath = projectPath {
            // Check if this is workspace mode
            if projectPath == "__workspace__" {
                requestBody["workspace"] = true
                requestBody["projectPath"] = projectPath
                print("📁 Workspace mode enabled for cross-project operations")
            } else {
                requestBody["projectPath"] = projectPath  // Server expects camelCase
            }
            
            // Include session ID if we have one for this project (or workspace)
            if let sessionId = getSessionId(for: projectPath) {
                requestBody["sessionId"] = sessionId
                print("📝 Including session ID in request: \(sessionId)")
            } else {
                print("⚠️ No session ID found for project: \(projectPath)")
            }
        }
        
        // Include device token for APNS delivery
        if let deviceToken = UserDefaults.standard.string(forKey: "devicePushToken") {
            requestBody["deviceToken"] = deviceToken  // Server expects camelCase
            print("📱 Including device token in request: \(deviceToken)")
        } else {
            print("⚠️ No device token found in UserDefaults")
        }
        
        if let attachments = attachments, !attachments.isEmpty {
            let attachmentData = attachments.map { attachment in
                [
                    "name": attachment.name,
                    "mimeType": attachment.mimeType,
                    "size": attachment.size,
                    "data": attachment.data.base64EncodedString()
                ]
            }
            requestBody["attachments"] = attachmentData
        }
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            return request
        } catch {
            return nil
        }
    }
    
    private func handleChatResponse(
        data: Data?,
        response: URLResponse?,
        error: Error?,
        projectPath: String?,
        completion: @escaping (Result<ClaudeChatResponse, AICLICompanionError>) -> Void
    ) {
        if let error = error {
            handleNetworkError(error, completion: completion)
            return
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            completion(.failure(.invalidResponse))
            return
        }
        
        guard let data = data else {
            completion(.failure(.invalidResponse))
            return
        }
        
        switch httpResponse.statusCode {
        case 200...299:
            parseSuccessResponse(data: data, projectPath: projectPath, completion: completion)
        case 401:
            handleAuthenticationError(data: data, completion: completion)
        case 400...499:
            handleServerError(data: data, statusCode: httpResponse.statusCode, completion: completion)
        case 500...599:
            handleServerError(data: data, statusCode: httpResponse.statusCode, completion: completion)
        default:
            completion(.failure(.serverError("Unexpected status code: \(httpResponse.statusCode)")))
        }
    }
    
    private func handleNetworkError(_ error: Error, completion: @escaping (Result<ClaudeChatResponse, AICLICompanionError>) -> Void) {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                completion(.failure(.connectionTimeout))
            case .notConnectedToInternet:
                completion(.failure(.networkError("No internet connection")))
            default:
                completion(.failure(.networkError(urlError.localizedDescription)))
            }
        } else {
            completion(.failure(.networkError(error.localizedDescription)))
        }
    }
    
    private func handleAuthenticationError(data: Data, completion: @escaping (Result<ClaudeChatResponse, AICLICompanionError>) -> Void) {
        completion(.failure(.authenticationFailed))
    }
    
    private func handleServerError(data: Data, statusCode: Int, completion: @escaping (Result<ClaudeChatResponse, AICLICompanionError>) -> Void) {
        // Try to parse error message from response
        if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errorMessage = errorData["error"] as? String {
            completion(.failure(.serverError("\(statusCode): \(errorMessage)")))
        } else {
            completion(.failure(.serverError("Server error: \(statusCode)")))
        }
    }
    
    private func parseSuccessResponse(data: Data, projectPath: String?, completion: @escaping (Result<ClaudeChatResponse, AICLICompanionError>) -> Void) {
        do {
            let response = try decoder.decode(ClaudeChatResponse.self, from: data)
            
            // Store session ID if we have one and a project path
            if let sessionId = response.sessionId, let projectPath = projectPath {
                storeSessionId(sessionId, for: projectPath)
            }
            
            completion(.success(response))
        } catch {
            // Try to parse as a simple success response
            if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // First, always try to extract and store the session ID regardless of delivery method
                // Check for claudeSessionId first (new format), then sessionId, then session_id (legacy)
                let sessionId = jsonObject["claudeSessionId"] as? String
                    ?? jsonObject["sessionId"] as? String
                    ?? jsonObject["session_id"] as? String
                
                // Store session ID if we have one and a project path
                if let sessionId = sessionId, let projectPath = projectPath {
                    storeSessionId(sessionId, for: projectPath)
                    print("✅ Stored Claude session ID: \(sessionId) for project: \(projectPath)")
                } else {
                    print("⚠️ No session ID found in response. Keys: \(jsonObject.keys.joined(separator: ", "))")
                }
                
                // Handle APNS delivery acknowledgment response
                if let success = jsonObject["success"] as? Bool,
                   success,
                   let deliveryMethod = jsonObject["deliveryMethod"] as? String,
                   deliveryMethod == "apns" {
                    // This is an acknowledgment that the message will be delivered via APNS
                    let response = ClaudeChatResponse(
                        content: "", // Content will come via APNS
                        sessionId: sessionId,
                        error: nil,
                        metadata: jsonObject as? [String: AnyCodable]
                    )
                    completion(.success(response))
                } else if let content = jsonObject["content"] as? String {
                    // Legacy response format with content
                    let response = ClaudeChatResponse(
                        content: content,
                        sessionId: sessionId,
                        error: nil,
                        metadata: nil
                    )
                    completion(.success(response))
                } else {
                    completion(.failure(.invalidResponse))
                }
            } else {
                completion(.failure(.invalidResponse))
            }
        }
    }
    
    private func setupDateFormatters() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        encoder.dateEncodingStrategy = .formatted(dateFormatter)
        decoder.dateDecodingStrategy = .formatted(dateFormatter)
        
        // Also support ISO8601 as fallback
        let iso8601Formatter = ISO8601DateFormatter()
        iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            
            if let date = dateFormatter.date(from: dateString) {
                return date
            } else if let date = iso8601Formatter.date(from: dateString) {
                return date
            } else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format")
            }
        }
    }
    
    // MARK: - Kill Session
    
    public func killSession(_ sessionId: String, projectPath: String, sendNotification: Bool = true, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let baseURL = connectionManager.currentBaseURL else {
            completion(.failure(AICLICompanionError.networkError("No connection configured")))
            return
        }
        
        let killURL = baseURL.appendingPathComponent("/api/chat/kill")
        var request = connectionManager.createAuthenticatedRequest(url: killURL, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var requestBody: [String: Any] = [
            "sessionId": sessionId,
            "reason": "User requested cancellation"
        ]
        
        // Include device token only if notification is requested
        if sendNotification, let deviceToken = UserDefaults.standard.string(forKey: "devicePushToken") {
            requestBody["deviceToken"] = deviceToken
        }
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            completion(.failure(error))
            return
        }
        
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(AICLICompanionError.invalidResponse))
                return
            }
            
            if httpResponse.statusCode == 200 {
                // Clear the session ID for this project
                self?.clearSessionId(for: projectPath)
                completion(.success(()))
            } else {
                let error = AICLICompanionError.serverError("Failed to kill session: HTTP \(httpResponse.statusCode)")
                completion(.failure(error))
            }
        }.resume()
    }
    
    // MARK: - Planning Validation
    
    public func validatePlanningDocument(
        content: String,
        projectType: String? = nil,
        projectPath: String? = nil,
        completion: @escaping (Result<PlanningValidationResponse, AICLICompanionError>) -> Void
    ) {
        guard let baseURL = connectionManager.currentBaseURL else {
            completion(.failure(AICLICompanionError.networkError("No connection configured")))
            return
        }
        
        let validateURL = baseURL.appendingPathComponent("/api/planning-validation/validate")
        var request = connectionManager.createAuthenticatedRequest(url: validateURL, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody = PlanningValidationRequest(
            content: content,
            projectType: projectType,
            projectPath: projectPath
        )
        
        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            completion(.failure(AICLICompanionError.encodingError(error)))
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                completion(.failure(AICLICompanionError.networkError(error.localizedDescription)))
                return
            }
            
            guard let data = data else {
                completion(.failure(AICLICompanionError.invalidResponse))
                return
            }
            
            do {
                let validationResponse = try JSONDecoder().decode(PlanningValidationResponse.self, from: data)
                completion(.success(validationResponse))
            } catch {
                completion(.failure(AICLICompanionError.decodingError(error)))
            }
        }.resume()
    }
    
    public func analyzeDirectory(
        path: String,
        completion: @escaping (Result<DirectoryAnalysisResponse, AICLICompanionError>) -> Void
    ) {
        guard let baseURL = connectionManager.currentBaseURL else {
            completion(.failure(AICLICompanionError.networkError("No connection configured")))
            return
        }
        
        let analyzeURL = baseURL.appendingPathComponent("/api/planning-validation/analyze")
        var request = connectionManager.createAuthenticatedRequest(url: analyzeURL, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody = DirectoryAnalysisRequest(projectPath: path)
        
        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            completion(.failure(AICLICompanionError.encodingError(error)))
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                completion(.failure(AICLICompanionError.networkError(error.localizedDescription)))
                return
            }
            
            guard let data = data else {
                completion(.failure(AICLICompanionError.invalidResponse))
                return
            }
            
            do {
                let analysisResponse = try JSONDecoder().decode(DirectoryAnalysisResponse.self, from: data)
                completion(.success(analysisResponse))
            } catch {
                completion(.failure(AICLICompanionError.decodingError(error)))
            }
        }.resume()
    }
    
    public func saveAndValidatePlan(
        projectPath: String,
        content: String,
        completion: @escaping (Result<PlanSaveResponse, AICLICompanionError>) -> Void
    ) {
        guard let baseURL = connectionManager.currentBaseURL else {
            completion(.failure(AICLICompanionError.networkError("No connection configured")))
            return
        }
        
        let saveURL = baseURL.appendingPathComponent("/api/planning-validation/save")
        var request = connectionManager.createAuthenticatedRequest(url: saveURL, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody = PlanSaveRequest(projectPath: projectPath, content: content)
        
        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            completion(.failure(AICLICompanionError.encodingError(error)))
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                completion(.failure(AICLICompanionError.networkError(error.localizedDescription)))
                return
            }
            
            guard let data = data else {
                completion(.failure(AICLICompanionError.invalidResponse))
                return
            }
            
            do {
                let saveResponse = try JSONDecoder().decode(PlanSaveResponse.self, from: data)
                completion(.success(saveResponse))
            } catch {
                completion(.failure(AICLICompanionError.decodingError(error)))
            }
        }.resume()
    }
}

// MARK: - Response Models

public struct ClaudeChatResponse: Codable {
    public let content: String
    public let sessionId: String?
    public let error: String?
    public let metadata: [String: AnyCodable]?
}
