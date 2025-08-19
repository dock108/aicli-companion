import Foundation
import Combine

// MARK: - AICLI Connection Management

@available(iOS 16.0, macOS 13.0, *)
public class AICLIConnectionManager: ObservableObject {
    @Published public var isConnected = false
    @Published public var connectionStatus: ConnectionStatus = .disconnected
    
    private var baseURL: URL?
    private var authToken: String?
    private let urlSession: URLSession
    
    public init(urlSession: URLSession) {
        self.urlSession = urlSession
    }
    
    // MARK: - Connection Operations
    
    public func connect(to address: String, port: Int, authToken: String?, completion: @escaping (Result<Void, AICLICompanionError>) -> Void) {
        // Store the base URL and auth token for future use
        guard let url = URL(string: "http://\(address):\(port)") else {
            completion(.failure(AICLICompanionError.invalidURL))
            return
        }
        
        self.baseURL = url
        self.authToken = authToken
        
        DispatchQueue.main.async {
            self.connectionStatus = ConnectionStatus.connecting
        }
        
        // Test the connection
        testConnection { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.isConnected = true
                    self?.connectionStatus = ConnectionStatus.connected
                    completion(.success(()))
                case .failure(let error):
                    self?.isConnected = false
                    self?.connectionStatus = ConnectionStatus.error(error.localizedDescription)
                    completion(.failure(error))
                }
            }
        }
    }
    
    public func disconnect() {
        baseURL = nil
        authToken = nil
        
        DispatchQueue.main.async {
            self.isConnected = false
            self.connectionStatus = ConnectionStatus.disconnected
        }
        
        // Cancel any pending tasks
        urlSession.getAllTasks { tasks in
            tasks.forEach { $0.cancel() }
        }
    }
    
    // MARK: - Connection Testing
    
    private func testConnection(completion: @escaping (Result<Void, AICLICompanionError>) -> Void) {
        guard let baseURL = baseURL else {
            completion(.failure(AICLICompanionError.invalidURL))
            return
        }
        
        let healthCheckURL = baseURL.appendingPathComponent("/health")
        var request = URLRequest(url: healthCheckURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10 // Quick health check
        
        // Add auth token if available
        if let authToken = authToken {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        
        let task = urlSession.dataTask(with: request) { _, response, error in
            if let error = error {
                completion(.failure(AICLICompanionError.networkError(error.localizedDescription)))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(AICLICompanionError.invalidResponse))
                return
            }
            
            switch httpResponse.statusCode {
            case 200...299:
                completion(.success(()))
            case 401:
                completion(.failure(AICLICompanionError.authenticationFailed))
            case 500...599:
                completion(.failure(AICLICompanionError.serverError("Server error: \(httpResponse.statusCode)")))
            default:
                completion(.failure(AICLICompanionError.serverError("Unexpected status code: \(httpResponse.statusCode)")))
            }
        }
        
        task.resume()
    }
    
    // MARK: - URL Building
    
    func buildURL(path: String) -> URL? {
        return baseURL?.appendingPathComponent(path)
    }
    
    func createAuthenticatedRequest(url: URL, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        
        if let authToken = authToken {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        
        return request
    }
    
    // MARK: - Connection State
    
    public var hasValidConnection: Bool {
        return isConnected && baseURL != nil
    }
    
    var currentBaseURL: URL? {
        return baseURL
    }
}
