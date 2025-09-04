import Foundation
import Combine

// MARK: - AICLI Session Management

@available(iOS 16.0, macOS 13.0, *)
public class AICLISessionManager: ObservableObject {
    @Published var currentSession: String?
    
    private let urlSession: URLSession
    private let connectionManager: AICLIConnectionManager
    private let decoder = JSONDecoder()
    
    public init(urlSession: URLSession, connectionManager: AICLIConnectionManager) {
        self.urlSession = urlSession
        self.connectionManager = connectionManager
    }
    
    // MARK: - Session Status
    
    func checkSessionStatus(sessionId: String, completion: @escaping (Result<Bool, AICLICompanionError>) -> Void) {
        guard let statusURL = connectionManager.buildURL(path: "/api/session/\(sessionId)/status") else {
            completion(.failure(.invalidURL))
            return
        }
        
        let request = connectionManager.createAuthenticatedRequest(url: statusURL)
        
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
                    let statusResponse = try self.decoder.decode(SessionStatusResponse.self, from: data)
                    completion(.success(statusResponse.isActive))
                } catch {
                    // Fallback: try to parse as simple JSON
                    if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let isActive = jsonObject["active"] as? Bool {
                        completion(.success(isActive))
                    } else {
                        completion(.failure(.invalidResponse))
                    }
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
    
    // MARK: - Async Session Status
    
    func checkSessionStatus(sessionId: String) async throws -> SessionStatus {
        guard let statusURL = connectionManager.buildURL(path: "/api/session/\(sessionId)/status") else {
            throw AICLICompanionError.invalidURL
        }
        
        let request = connectionManager.createAuthenticatedRequest(url: statusURL)
        
        do {
            let (data, response) = try await urlSession.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AICLICompanionError.invalidResponse
            }
            
            switch httpResponse.statusCode {
            case 200...299:
                let statusResponse = try decoder.decode(SessionStatusResponse.self, from: data)
                return SessionStatus(
                    isActive: statusResponse.isActive,
                    sessionId: statusResponse.sessionId,
                    startTime: statusResponse.startTime,
                    lastActivity: statusResponse.lastActivity,
                    messageCount: statusResponse.messageCount,
                    workingDirectory: statusResponse.workingDirectory
                )
            case 401:
                throw AICLICompanionError.authenticationFailed
            case 404:
                throw AICLICompanionError.fileNotFound("Session not found")
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
    
    // MARK: - Session Management
    
    func setCurrentSession(_ sessionId: String?) {
        DispatchQueue.main.async {
            self.currentSession = sessionId
        }
    }
    
    func clearCurrentSession() {
        DispatchQueue.main.async {
            self.currentSession = nil
        }
    }
    
    var hasActiveSession: Bool {
        return currentSession != nil
    }
    
    // MARK: - Session ID Management
    
    func getSessionId(for projectPath: String) -> String? {
        // Use SessionKeyManager to retrieve session IDs per project
        return SessionKeyManager.sessionId(for: projectPath)
    }
}

// MARK: - Session Models

public struct SessionStatus {
    public let isActive: Bool
    public let sessionId: String?
    public let startTime: Date?
    public let lastActivity: Date?
    public let messageCount: Int?
    public let workingDirectory: String?
}
