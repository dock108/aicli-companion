import Foundation
import Combine
import Network

@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
public class AICLIService: ObservableObject {
    @Published var isConnected = false
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var currentSession: String?

    private var currentConnection: ServerConnection?
    private var urlSession: URLSession
    private var webSocketTask: URLSessionWebSocketTask?
    private var cancellables = Set<AnyCancellable>()

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.urlSession = URLSession(configuration: config)

        setupDateFormatters()
    }

    deinit {
        // Cancel any pending tasks
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil

        // Clear all references
        cancellables.removeAll()
        currentConnection = nil
        currentSession = nil
    }

    // MARK: - Connection Management

    func connect(to address: String, port: Int, authToken: String?, completion: @escaping (Result<Void, AICLICompanionError>) -> Void) {
        let connection = ServerConnection(
            address: address,
            port: port,
            authToken: authToken,
            isSecure: port == 443 || address.contains("https")
        )

        currentConnection = connection

        // Test basic connectivity first
        testConnection(connection) { [weak self] result in
            switch result {
            case .success:
                self?.establishWebSocketConnection(connection, completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func disconnect() {
        // Cancel WebSocket task
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil

        // Cancel all URLSession tasks
        urlSession.getAllTasks { tasks in
            tasks.forEach { $0.cancel() }
        }

        // Clear references
        currentConnection = nil
        currentSession = nil

        DispatchQueue.main.async { [weak self] in
            self?.isConnected = false
            self?.connectionStatus = .disconnected
        }
    }

    // MARK: - Server Discovery

    func discoverLocalServers(completion: @escaping (Result<[DiscoveredServer], AICLICompanionError>) -> Void) {
        // Use Bonjour to discover local Claude Code servers
        let browser = NetworkServiceBrowser()

        browser.browseForServices(ofType: "_claudecode._tcp", inDomain: "local.") { services in
            let discoveredServers = services.compactMap { service -> DiscoveredServer? in
                guard let address = service.hostName,
                      let port = service.port else { return nil }

                return DiscoveredServer(
                    name: service.name,
                    address: address,
                    port: port,
                    isSecure: false // Local discovery typically uses HTTP
                )
            }

            completion(.success(discoveredServers))
        }

        // Fallback: scan common ports on local network
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 2.0) {
            completion(.success([]))
        }
    }

    // MARK: - Claude Code API

    func sendPrompt(_ prompt: String, completion: @escaping (Result<AICLIResponse, AICLICompanionError>) -> Void) {
        guard let connection = currentConnection,
              let url = connection.url else {
            completion(.failure(AICLICompanionError.connectionFailed("No active connection")))
            return
        }

        let requestBody = AICLIRequest(prompt: prompt, format: "json")

        guard let bodyData = try? encoder.encode(requestBody) else {
            completion(.failure(AICLICompanionError.jsonParsingError(NSError(domain: "EncodingError", code: 0))))
            return
        }

        var request = URLRequest(url: url.appendingPathComponent("/api/ask"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = connection.authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = bodyData

        urlSession.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                completion(.failure(AICLICompanionError.networkError(error)))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(.invalidResponse))
                return
            }

            guard 200...299 ~= httpResponse.statusCode else {
                completion(.failure(.connectionFailed("HTTP \(httpResponse.statusCode)")))
                return
            }

            guard let data = data else {
                completion(.failure(.invalidResponse))
                return
            }

            do {
                let claudeResponse = try self?.decoder.decode(AICLIResponse.self, from: data)
                if let response = claudeResponse {
                    completion(.success(response))
                } else {
                    completion(.failure(.jsonParsingError(NSError(domain: "DecodingError", code: 0))))
                }
            } catch {
                completion(.failure(.jsonParsingError(error)))
            }
        }.resume()
    }

    func sendStreamingPrompt(_ prompt: String, onPartialResponse: @escaping (String) -> Void, completion: @escaping (Result<AICLIResponse, AICLICompanionError>) -> Void) {
        // TODO: Implement streaming via WebSocket
        sendPrompt(prompt, completion: completion)
    }
    
    // MARK: - Project Management
    
    func startProjectSession(project: Project, connection: ServerConnection, completion: @escaping (Result<ProjectSession, AICLICompanionError>) -> Void) {
        guard let url = connection.url else {
            completion(.failure(.connectionFailed("Invalid server URL")))
            return
        }
        
        let projectUrl = url.appendingPathComponent("/api/projects/\(project.name)/start")
        
        var request = URLRequest(url: projectUrl)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let token = connection.authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        // Empty body for POST request
        request.httpBody = Data()
        
        urlSession.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                completion(.failure(AICLICompanionError.networkError(error)))
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
            
            // Log response for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                print("Project start response: \(responseString)")
            }
            
            do {
                // Check for error response
                if httpResponse.statusCode >= 400 {
                    let errorResponse = try self?.decoder.decode(ErrorResponse.self, from: data)
                    let errorMessage = errorResponse?.message ?? "Server error"
                    completion(.failure(.connectionFailed(errorMessage)))
                    return
                }
                
                // Parse successful response
                let response = try self?.decoder.decode(ProjectStartResponse.self, from: data)
                if let sessionData = response?.session {
                    let session = ProjectSession(
                        sessionId: sessionData.sessionId,
                        projectName: sessionData.projectName,
                        projectPath: sessionData.projectPath,
                        status: sessionData.status,
                        startedAt: sessionData.startedAt
                    )
                    completion(.success(session))
                } else {
                    completion(.failure(.invalidResponse))
                }
            } catch {
                print("Failed to parse project start response: \(error)")
                completion(.failure(.jsonParsingError(error)))
            }
        }.resume()
    }

    // MARK: - Health Check

    func healthCheck(completion: @escaping (Result<ServerHealth, AICLICompanionError>) -> Void) {
        guard let connection = currentConnection,
              let url = connection.url else {
            completion(.failure(AICLICompanionError.connectionFailed("No active connection")))
            return
        }

        var request = URLRequest(url: url.appendingPathComponent("/api/health"))
        request.httpMethod = "GET"

        if let token = connection.authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        urlSession.dataTask(with: request) { _, response, error in
            if let error = error {
                completion(.failure(AICLICompanionError.networkError(error)))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse,
                  200...299 ~= httpResponse.statusCode else {
                completion(.failure(.connectionFailed("Health check failed")))
                return
            }

            // Parse health response if available
            let health = ServerHealth(status: "healthy", version: "1.0.0")
            completion(.success(health))
        }.resume()
    }

    // MARK: - Private Methods

    private func setupDateFormatters() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        decoder.dateDecodingStrategy = .formatted(formatter)
        encoder.dateEncodingStrategy = .formatted(formatter)
    }

    private func testConnection(_ connection: ServerConnection, completion: @escaping (Result<Void, AICLICompanionError>) -> Void) {
        guard let url = connection.url else {
            completion(.failure(.connectionFailed("Invalid server URL")))
            return
        }

        var request = URLRequest(url: url.appendingPathComponent("/api/health"))
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        if let token = connection.authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        urlSession.dataTask(with: request) { _, response, error in
            if let error = error {
                completion(.failure(AICLICompanionError.networkError(error)))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(.invalidResponse))
                return
            }

            if httpResponse.statusCode == 401 {
                completion(.failure(.authenticationFailed))
                return
            }

            guard 200...299 ~= httpResponse.statusCode else {
                completion(.failure(.connectionFailed("HTTP \(httpResponse.statusCode)")))
                return
            }

            completion(.success(()))
        }.resume()
    }

    private func establishWebSocketConnection(_ connection: ServerConnection, completion: @escaping (Result<Void, AICLICompanionError>) -> Void) {
        guard let wsURL = connection.wsURL else {
            completion(.failure(.connectionFailed("Invalid WebSocket URL")))
            return
        }

        var request = URLRequest(url: wsURL)
        if let token = connection.authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        webSocketTask = urlSession.webSocketTask(with: request)
        webSocketTask?.resume()

        DispatchQueue.main.async { [weak self] in
            self?.isConnected = true
            self?.connectionStatus = .connected
        }

        completion(.success(()))
        startReceivingMessages()
    }

    private func startReceivingMessages() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleWebSocketMessage(message)
                self?.startReceivingMessages() // Continue receiving
            case .failure(let error):
                print("WebSocket error: \(error)")
                DispatchQueue.main.async {
                    self?.connectionStatus = .disconnected
                    self?.isConnected = false
                }
            }
        }
    }

    private func handleWebSocketMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            print("Received WebSocket message: \(text)")
        // Handle real-time updates, streaming responses, etc.
        case .data(let data):
            print("Received WebSocket data: \(data.count) bytes")
        @unknown default:
            break
        }
    }
}

// MARK: - Supporting Types

enum ConnectionStatus {
    case disconnected
    case connecting
    case connected
    case error(AICLICompanionError)
}

struct AICLIRequest: Codable {
    let prompt: String
    let format: String
    let sessionId: String?

    init(prompt: String, format: String = "json", sessionId: String? = nil) {
        self.prompt = prompt
        self.format = format
        self.sessionId = sessionId
    }
}

struct ServerHealth: Codable {
    let status: String
    let version: String
    let claudeCodeVersion: String?

    init(status: String, version: String, claudeCodeVersion: String? = nil) {
        self.status = status
        self.version = version
        self.claudeCodeVersion = claudeCodeVersion
    }
}

// MARK: - Network Service Browser (Simplified)

class NetworkServiceBrowser {
    func browseForServices(ofType type: String, inDomain domain: String, completion: @escaping ([NetworkService]) -> Void) {
        // TODO: Implement actual Bonjour discovery using Network framework
        // For now, return empty array
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1.0) {
            completion([])
        }
    }
}

struct NetworkService {
    let name: String
    let hostName: String?
    let port: Int?
}
