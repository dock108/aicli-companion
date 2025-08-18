import Foundation

// MARK: - AICLI Project Management

@available(iOS 16.0, macOS 13.0, *)
public class AICLIProjectManager {
    private let urlSession: URLSession
    private let connectionManager: AICLIConnectionManager
    private let decoder = JSONDecoder()
    
    public init(urlSession: URLSession, connectionManager: AICLIConnectionManager) {
        self.urlSession = urlSession
        self.connectionManager = connectionManager
    }
    
    // MARK: - Project Operations
    
    func getProjects(completion: @escaping (Result<[Project], AICLICompanionError>) -> Void) {
        guard let projectsURL = connectionManager.buildURL(path: "/api/projects") else {
            completion(.failure(.invalidURL))
            return
        }
        
        let request = connectionManager.createAuthenticatedRequest(url: projectsURL)
        
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
                    let projectsResponse = try self.decoder.decode(ProjectsResponse.self, from: data)
                    let projects = projectsResponse.projects
                    completion(.success(projects))
                } catch {
                    // Fallback: try to parse as simple array
                    if let projectArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                        let projects = projectArray.compactMap { projectData -> Project? in
                            guard let name = projectData["name"] as? String,
                                  let path = projectData["path"] as? String else {
                                return nil
                            }
                            
                            let type = projectData["type"] as? String ?? "other"
                            
                            return Project(
                                name: name,
                                path: path,
                                type: type
                            )
                        }
                        completion(.success(projects))
                    } else {
                        completion(.failure(.invalidResponse))
                    }
                }
            case 401:
                completion(.failure(.authenticationFailed))
            case 403:
                completion(.failure(.permissionDenied))
            case 500...599:
                completion(.failure(.serverError("Server error")))
            default:
                completion(.failure(.serverError("Unexpected status code: \(httpResponse.statusCode)")))
            }
        }
        
        task.resume()
    }
    
    // MARK: - Project Validation
    
    func validateProjectPath(_ path: String, completion: @escaping (Result<Bool, AICLICompanionError>) -> Void) {
        guard let validateURL = connectionManager.buildURL(path: "/api/projects/validate") else {
            completion(.failure(.invalidURL))
            return
        }
        
        var request = connectionManager.createAuthenticatedRequest(url: validateURL, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody = ["path": path]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            completion(.failure(.invalidInput("Failed to encode validation request")))
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
                if let data = data,
                   let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let isValid = jsonObject["valid"] as? Bool {
                    completion(.success(isValid))
                } else {
                    completion(.success(true)) // Assume valid if no response data
                }
            case 400:
                completion(.success(false)) // Invalid path
            case 401:
                completion(.failure(.authenticationFailed))
            case 403:
                completion(.failure(.permissionDenied))
            case 404:
                completion(.success(false)) // Path not found
            case 500...599:
                completion(.failure(.serverError("Server error")))
            default:
                completion(.failure(.serverError("Unexpected status code: \(httpResponse.statusCode)")))
            }
        }
        
        task.resume()
    }
}

// MARK: - Project Response Models
// Uses the Project type from ProjectSelectionView.swift

struct ProjectData: Codable {
    let name: String
    let path: String
    let type: String?
    let lastModified: Date?
}