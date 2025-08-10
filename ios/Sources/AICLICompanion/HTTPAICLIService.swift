import Foundation
import Combine
import UserNotifications
#if os(iOS)
import UIKit
#endif

@available(iOS 16.0, macOS 13.0, *)
public class HTTPAICLIService: ObservableObject {
    static let shared = HTTPAICLIService()
    
    @Published var isConnected = false
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var currentSession: String?

    private var baseURL: URL?
    private var urlSession: URLSession
    private var deviceToken: String?
    private var cancellables = Set<AnyCancellable>()

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120 // Longer timeout for Claude processing
        config.waitsForConnectivity = true // Wait for network connectivity
        config.allowsCellularAccess = true
        config.sessionSendsLaunchEvents = true
        self.urlSession = URLSession(configuration: config)

        setupDateFormatters()
        setupPushNotifications()
        setupDeviceTokenListener()
    }

    deinit {
        // Cancel any pending tasks
        urlSession.getAllTasks { tasks in
            tasks.forEach { $0.cancel() }
        }
        cancellables.removeAll()
    }

    // MARK: - Connection Management

    func connect(to address: String, port: Int, authToken: String?, completion: @escaping (Result<Void, AICLICompanionError>) -> Void) {
        let scheme = port == 443 || address.contains("https") ? "https" : "http"
        
        // For default ports (443 for https, 80 for http), don't include port in URL
        // This is especially important for ngrok URLs like domain.ngrok-free.app
        let urlString: String
        if (scheme == "https" && port == 443) || (scheme == "http" && port == 80) {
            urlString = "\(scheme)://\(address)"
        } else {
            urlString = "\(scheme)://\(address):\(port)"
        }
        
        guard let url = URL(string: urlString) else {
            completion(.failure(.invalidURL))
            return
        }

        baseURL = url
        
        // Test connection by hitting the health endpoint
        testConnection { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.isConnected = true
                    self?.connectionStatus = .connected
                    
                    // Notify ConnectionReliabilityManager
                    ConnectionReliabilityManager.shared.handleConnectionEstablished()
                    
                    // Register device for push notifications if we have a token
                    if let deviceToken = self?.deviceToken {
                        self?.registerDeviceForPushNotifications(deviceToken: deviceToken) { _ in }
                    }
                    
                    completion(.success(()))
                case .failure(let error):
                    self?.isConnected = false
                    self?.connectionStatus = .error(error)
                    completion(.failure(error))
                }
            }
        }
    }

    func disconnect() {
        // Cancel all URLSession tasks
        urlSession.getAllTasks { tasks in
            tasks.forEach { $0.cancel() }
        }

        baseURL = nil
        currentSession = nil

        DispatchQueue.main.async { [weak self] in
            self?.isConnected = false
            self?.connectionStatus = .disconnected
        }
    }

    // MARK: - Health Check

    private func testConnection(completion: @escaping (Result<Void, AICLICompanionError>) -> Void) {
        guard let baseURL = baseURL else {
            completion(.failure(.invalidURL))
            return
        }

        let healthURL = baseURL.appendingPathComponent("health")
        var request = URLRequest(url: healthURL)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        urlSession.dataTask(with: request) { _, response, error in
            if let error = error {
                completion(.failure(.networkError(error)))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(.invalidResponse))
                return
            }

            if httpResponse.statusCode == 200 {
                completion(.success(()))
            } else {
                completion(.failure(.httpError(httpResponse.statusCode)))
            }
        }.resume()
    }

    // MARK: - Push Notifications Setup

    private func setupPushNotifications() {
        // Request notification permission
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if granted {
                DispatchQueue.main.async {
                    #if os(iOS)
                    UIApplication.shared.registerForRemoteNotifications()
                    #endif
                }
            }
        }
    }

    private func setupDeviceTokenListener() {
        // Listen for device token updates from AppDelegate
        NotificationCenter.default.addObserver(
            forName: Notification.Name("DeviceTokenReceived"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let token = notification.object as? String {
                self?.setDeviceToken(token)
            }
        }
    }

    func setDeviceToken(_ token: String) {
        self.deviceToken = token
        
        // Register with server if we're connected
        if isConnected {
            registerDeviceForPushNotifications(deviceToken: token) { result in
                switch result {
                case .success:
                    print("✅ Device registered for push notifications")
                case .failure(let error):
                    print("❌ Failed to register device: \(error)")
                }
            }
        }
    }

    private func registerDeviceForPushNotifications(deviceToken: String, completion: @escaping (Result<Void, AICLICompanionError>) -> Void) {
        guard let baseURL = baseURL else {
            completion(.failure(.invalidURL))
            return
        }

        let registerURL = baseURL.appendingPathComponent("api/devices/register")
        var request = URLRequest(url: registerURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = [
            "deviceToken": deviceToken,
            "platform": "ios",
            "bundleId": "com.aiclicompanion.ios"
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            completion(.failure(.jsonParsingError(error)))
            return
        }

        urlSession.dataTask(with: request) { _, response, error in
            if let error = error {
                completion(.failure(.networkError(error)))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(.invalidResponse))
                return
            }

            if httpResponse.statusCode == 200 {
                completion(.success(()))
            } else {
                completion(.failure(.httpError(httpResponse.statusCode)))
            }
        }.resume()
    }

    // MARK: - Chat API

    func sendMessage(
        message: String,
        projectPath: String?,
        sessionId: String? = nil,
        completion: @escaping (Result<ClaudeChatResponse, AICLICompanionError>) -> Void
    ) {
        guard let baseURL = baseURL else {
            completion(.failure(.invalidURL))
            return
        }

        let chatURL = baseURL.appendingPathComponent("api/chat")
        var request = URLRequest(url: chatURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120 // Extended timeout for Claude processing

        var payload: [String: Any] = [
            "message": message
        ]

        if let projectPath = projectPath {
            payload["projectPath"] = projectPath
        }

        if let sessionId = sessionId {
            payload["sessionId"] = sessionId
        }

        if let deviceToken = deviceToken {
            payload["deviceToken"] = deviceToken
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            completion(.failure(.jsonParsingError(error)))
            return
        }

        print("📤 Sending HTTP message to: \(chatURL)")
        print("   Payload: \(payload)")

        // Create background task for iOS to continue request when app is backgrounded
        #if os(iOS)
        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "Claude Chat Request") {
            // Clean up if task expires
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
        #endif
        
        let task = urlSession.dataTask(with: request) { data, response, error in
            #if os(iOS)
            defer {
                if backgroundTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTaskID)
                }
            }
            #endif
            
            if let error = error {
                print("❌ Network error: \(error)")
                // Check if it's a timeout error
                let nsError = error as NSError
                if nsError.code == NSURLErrorTimedOut {
                    // More user-friendly timeout message
                    completion(.failure(.networkError(NSError(domain: "HTTPAICLIService", code: -1001, userInfo: [NSLocalizedDescriptionKey: "The request timed out. Please check your connection and try again."]))))
                } else {
                    completion(.failure(.networkError(error)))
                }
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(.invalidResponse))
                return
            }

            print("📥 HTTP Response status: \(httpResponse.statusCode)")

            guard let data = data else {
                completion(.failure(.noData))
                return
            }

            // Parse the response
            do {
                let chatResponse = try self.decoder.decode(ClaudeChatResponse.self, from: data)
                print("✅ Chat response received: \(chatResponse.content?.prefix(100) ?? "acknowledgment")...")
                
                // Update session ID if provided
                if let newSessionId = chatResponse.sessionId {
                    DispatchQueue.main.async {
                        self.currentSession = newSessionId
                    }
                }
                
                completion(.success(chatResponse))
            } catch {
                print("❌ JSON parsing error: \(error)")
                completion(.failure(.jsonParsingError(error)))
            }
        }
        task.resume()
    }

    // MARK: - Session Status
    
    func checkSessionStatus(sessionId: String, completion: @escaping (Result<Bool, AICLICompanionError>) -> Void) {
        guard let baseURL = baseURL else {
            completion(.failure(.invalidURL))
            return
        }
        
        let statusURL = baseURL.appendingPathComponent("api/sessions/\(sessionId)/status")
        var request = URLRequest(url: statusURL)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10 // Quick status check
        
        print("📡 Checking session status: \(statusURL)")
        
        urlSession.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(.networkError(error)))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(.invalidResponse))
                return
            }
            
            guard let data = data else {
                completion(.failure(.noData))
                return
            }
            
            do {
                let statusResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let hasNewMessages = statusResponse?["hasNewMessages"] as? Bool ?? false
                completion(.success(hasNewMessages))
            } catch {
                completion(.failure(.jsonParsingError(error)))
            }
        }.resume()
    }

    // MARK: - Project Management

    func getProjects(completion: @escaping (Result<[Project], AICLICompanionError>) -> Void) {
        guard let baseURL = baseURL else {
            completion(.failure(.invalidURL))
            return
        }

        let projectsURL = baseURL.appendingPathComponent("api/projects")
        var request = URLRequest(url: projectsURL)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        urlSession.dataTask(with: request) { data, _, error in
            if let error = error {
                completion(.failure(.networkError(error)))
                return
            }

            guard let data = data else {
                completion(.failure(.noData))
                return
            }

            do {
                let projects = try self.decoder.decode([Project].self, from: data)
                completion(.success(projects))
            } catch {
                completion(.failure(.jsonParsingError(error)))
            }
        }.resume()
    }

    // MARK: - Utility Methods

    private func setupDateFormatters() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }

        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)

            if let date = formatter.date(from: string) {
                return date
            }

            // Fallback to standard ISO8601 without fractional seconds
            let fallbackFormatter = ISO8601DateFormatter()
            if let date = fallbackFormatter.date(from: string) {
                return date
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format")
        }
    }
}

// MARK: - Response Models

struct ClaudeChatResponse: Codable {
    let content: String?        // Optional - not present in acknowledgments
    let sessionId: String?
    let projectPath: String?
    let timestamp: Date
    let success: Bool
    let message: String?        // Acknowledgment message
    let deliveryMethod: String? // "apns" for acknowledgments
    let requestId: String?      // Track request/response pairs
}
