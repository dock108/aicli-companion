import Foundation
import Network

// MARK: - File Content Wrapper

class FileContentWrapper: NSObject {
    let data: FileContentData
    
    init(_ data: FileContentData) {
        self.data = data
    }
}

// MARK: - File Content Service

@MainActor
class FileContentService: ObservableObject {
    static let shared = FileContentService()
    
    private let cache = NSCache<NSString, FileContentWrapper>()
    private let cacheExpirationInterval: TimeInterval = 300 // 5 minutes
    private var cacheTimestamps: [String: Date] = [:]
    private var connectionManager: AICLIConnectionManager?
    private var projectManager: AICLIProjectManager?
    
    private init() {
        setupCache()
        // Don't create a connection manager here - wait for it to be provided via updateConnection
        print("📄 [FILE SERVICE] FileContentService initialized, waiting for connection...")
    }
    
    // MARK: - Public Methods
    
    func fetchFileContent(path: String) async throws -> (content: FileContentData, warning: DuplicateFileWarning?) {
        print("📄 [FILE SERVICE] Fetching file content for path: \(path)")
        
        // Check cache first
        if let cached = getCachedContent(for: path) {
            print("📄 [FILE SERVICE] Found cached content for: \(path)")
            return (content: cached, warning: nil) // Cached content doesn't include warnings
        }
        
        print("📄 [FILE SERVICE] No cache, fetching from server for: \(path)")
        
        // Fetch from server
        let result = try await fetchFromServerWithWarnings(path: path)
        
        // Cache the result
        cacheContent(result.content, for: path)
        
        print("📄 [FILE SERVICE] Successfully fetched and cached content for: \(path)")
        if let warning = result.warning {
            print("📄 [FILE SERVICE] ⚠️ Duplicate filename warning for: \(path)")
        }
        
        return result
    }
    
    func clearCache() {
        cache.removeAllObjects()
        cacheTimestamps.removeAll()
    }
    
    func prefetchFileContent(path: String) {
        Task {
            do {
                _ = try await fetchFileContent(path: path)
            } catch {
                // Silently fail for prefetch operations
                print("Failed to prefetch file content for \(path): \(error)")
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func setupCache() {
        cache.countLimit = 50 // Max 50 files cached
        cache.totalCostLimit = 10 * 1024 * 1024 // 10MB total
    }
    
    private func getCachedContent(for path: String) -> FileContentData? {
        let cacheKey = NSString(string: path)
        
        // Check if we have cached content
        guard let cached = cache.object(forKey: cacheKey) else {
            return nil
        }
        
        // Check if cache is still valid
        if let timestamp = cacheTimestamps[path],
           Date().timeIntervalSince(timestamp) < cacheExpirationInterval {
            return cached.data
        } else {
            // Cache expired, remove it
            cache.removeObject(forKey: cacheKey)
            cacheTimestamps.removeValue(forKey: path)
            return nil
        }
    }
    
    private func cacheContent(_ content: FileContentData, for path: String) {
        let cacheKey = NSString(string: path)
        let cost = content.content.utf8.count
        let wrapper = FileContentWrapper(content)
        
        cache.setObject(wrapper, forKey: cacheKey, cost: cost)
        cacheTimestamps[path] = Date()
    }
    
    private func fetchFromServerWithWarnings(path: String) async throws -> (content: FileContentData, warning: DuplicateFileWarning?) {
        print("📄 [FILE SERVICE] Starting server request for: \(path)")
        
        // Get the connection manager from AICLIService.shared
        let connectionManager = AICLIService.shared.activeConnectionManager
        print("📄 [FILE SERVICE] Got connection manager from AICLIService")
        
        // Ensure we have a valid connection
        guard connectionManager.hasValidConnection else {
            print("📄 [FILE SERVICE] ❌ Connection manager has no valid connection")
            throw FileContentError.noServerConnection
        }
        
        print("📄 [FILE SERVICE] Valid connection found, building URL...")
        
        // Build the API endpoint using connection manager
        guard let url = connectionManager.buildURL(path: "api/files/content") else {
            print("📄 [FILE SERVICE] ❌ Failed to build URL for api/files/content")
            throw FileContentError.invalidResponse
        }
        
        print("📄 [FILE SERVICE] Built URL: \(url)")
        
        // Create authenticated request
        var request = connectionManager.createAuthenticatedRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Request body
        let workingDirectory = getCurrentWorkingDirectory()
        print("📄 [FILE SERVICE] Working directory: \(workingDirectory ?? "nil")")
        
        let requestBody = FileContentRequest(path: path, workingDirectory: workingDirectory)
        let jsonData = try JSONEncoder().encode(requestBody)
        request.httpBody = jsonData
        
        print("📄 [FILE SERVICE] Making HTTP request...")
        
        // Perform the request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Check response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FileContentError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200:
            // Success
            let apiResponse = try JSONDecoder().decode(FileContentResponse.self, from: data)
            return (content: apiResponse.content, warning: apiResponse.warning)
        case 401:
            throw FileContentError.unauthorized
        case 403:
            throw FileContentError.accessDenied
        case 404:
            throw FileContentError.fileNotFound(path)
        case 413:
            throw FileContentError.fileTooLarge
        default:
            // Try to parse error message
            if let errorResponse = try? JSONDecoder().decode(FileContentErrorResponse.self, from: data) {
                throw FileContentError.serverError(errorResponse.message)
            } else {
                throw FileContentError.serverError("HTTP \(httpResponse.statusCode)")
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func getCurrentWorkingDirectory() -> String? {
        // Get the working directory from the resolved path that was passed in
        // or from ProjectStateManager
        
        // First check if we have stored project context
        if let storedPath = UserDefaults.standard.string(forKey: "currentProjectPath") {
            print("📄 [FILE SERVICE] Got working directory from UserDefaults: \(storedPath)")
            return storedPath
        }
        
        // Try to get from ProjectStateManager
        if let currentProject = ProjectStateManager.shared.currentProject {
            print("📄 [FILE SERVICE] Got working directory from ProjectStateManager: \(currentProject.path)")
            return currentProject.path
        }
        
        print("📄 [FILE SERVICE] ⚠️ No working directory available")
        return nil
    }
    
    // MARK: - Connection Management
    
    public func updateConnection(_ connectionManager: AICLIConnectionManager) {
        self.connectionManager = connectionManager
        // ProjectManager uses the same URLSession.shared, so we can create it with the connection manager
        self.projectManager = AICLIProjectManager(urlSession: URLSession.shared, connectionManager: connectionManager)
    }
}

// MARK: - Data Models

struct FileContentRequest: Codable {
    let path: String
    let workingDirectory: String?
}

struct FileContentResponse: Codable {
    let content: FileContentData
    let success: Bool
    let warning: DuplicateFileWarning?
}

struct DuplicateFileWarning: Codable {
    let type: String
    let message: String
    let duplicates: [DuplicateFileInfo]
    let suggestion: String
}

struct DuplicateFileInfo: Codable {
    let relativePath: String
    let size: Int
    let lastModified: String
}

struct FileContentErrorResponse: Codable {
    let message: String
    let error: String?
}

// MARK: - Errors

enum FileContentError: LocalizedError {
    case noServerConnection
    case invalidResponse
    case unauthorized
    case accessDenied
    case fileNotFound(String)
    case fileTooLarge
    case serverError(String)
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .noServerConnection:
            return "No server connection available"
        case .invalidResponse:
            return "Invalid server response"
        case .unauthorized:
            return "Authentication required"
        case .accessDenied:
            return "Access denied to file"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .fileTooLarge:
            return "File is too large to display"
        case .serverError(let message):
            return "Server error: \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
