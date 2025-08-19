import Foundation
import Combine
import UserNotifications
#if os(iOS)
import UIKit
#endif

// MARK: - AICLI Push Notification Management

@available(iOS 16.0, macOS 13.0, *)
public class AICLIPushNotificationManager: ObservableObject {
    private var deviceToken: String?
    private let urlSession: URLSession
    private let connectionManager: AICLIConnectionManager
    private var cancellables = Set<AnyCancellable>()
    
    public init(urlSession: URLSession, connectionManager: AICLIConnectionManager) {
        self.urlSession = urlSession
        self.connectionManager = connectionManager
        setupPushNotifications()
        setupDeviceTokenListener()
    }
    
    // MARK: - Push Notification Setup
    
    private func setupPushNotifications() {
        #if os(iOS)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
            
            if let error = error {
                print("Push notification authorization error: \(error)")
            }
        }
        #endif
    }
    
    private func setupDeviceTokenListener() {
        #if os(iOS)
        NotificationCenter.default.publisher(for: Notification.Name("DeviceTokenReceived"))
            .compactMap { notification in
                notification.object as? String
            }
            .sink { [weak self] token in
                self?.setDeviceToken(token)
            }
            .store(in: &cancellables)
        #endif
    }
    
    // MARK: - Device Token Management
    
    func setDeviceToken(_ token: String) {
        self.deviceToken = token
        
        // Auto-register if we have a connection
        if connectionManager.hasValidConnection {
            registerDeviceForPushNotifications(deviceToken: token) { result in
                switch result {
                case .success:
                    print("Device successfully registered for push notifications")
                case .failure(let error):
                    print("Failed to register device for push notifications: \(error)")
                }
            }
        }
    }
    
    // MARK: - Device Registration
    
    func registerDeviceForPushNotifications(deviceToken: String, completion: @escaping (Result<Void, AICLICompanionError>) -> Void) {
        guard let registrationURL = connectionManager.buildURL(path: "/api/register-device") else {
            completion(.failure(.invalidURL))
            return
        }
        
        var request = connectionManager.createAuthenticatedRequest(url: registrationURL, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let deviceType: String
        #if os(iOS)
        deviceType = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        #else
        deviceType = "mac"
        #endif
        
        let requestBody = RegisterDeviceRequest(
            deviceToken: deviceToken,
            deviceType: deviceType,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        )
        
        do {
            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(requestBody)
        } catch {
            completion(.failure(.invalidInput("Failed to encode registration request")))
            return
        }
        
        let task = urlSession.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(.networkError(error.localizedDescription)))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(.invalidResponse))
                return
            }
            
            switch httpResponse.statusCode {
            case 200...299:
                if let data = data {
                    do {
                        let decoder = JSONDecoder()
                        let response = try decoder.decode(DeviceRegisteredResponse.self, from: data)
                        if response.success {
                            completion(.success(()))
                        } else {
                            completion(.failure(.serverError(response.message ?? "Registration failed")))
                        }
                    } catch {
                        // Registration succeeded but response parsing failed - not critical
                        completion(.success(()))
                    }
                } else {
                    completion(.success(()))
                }
            case 401:
                completion(.failure(.authenticationFailed))
            case 400...499:
                completion(.failure(.invalidInput("Invalid registration request")))
            case 500...599:
                completion(.failure(.serverError("Server error during registration")))
            default:
                completion(.failure(.serverError("Unexpected status code: \(httpResponse.statusCode)")))
            }
        }
        
        task.resume()
    }
    
    // MARK: - Push Notification State
    
    var currentDeviceToken: String? {
        return deviceToken
    }
    
    var isRegisteredForPushNotifications: Bool {
        return deviceToken != nil
    }
}
