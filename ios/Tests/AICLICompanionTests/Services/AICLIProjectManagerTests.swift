import XCTest
@testable import AICLICompanion
import Foundation

@available(iOS 16.0, macOS 13.0, *)
final class AICLIProjectManagerTests: XCTestCase {
    
    var projectManager: AICLIProjectManager!
    var mockURLSession: MockURLSession!
    var mockConnectionManager: MockAICLIConnectionManager!
    
    override func setUp() {
        super.setUp()
        mockURLSession = MockURLSession()
        mockConnectionManager = MockAICLIConnectionManager(urlSession: mockURLSession)
        projectManager = AICLIProjectManager(
            urlSession: mockURLSession,
            connectionManager: mockConnectionManager
        )
    }
    
    // MARK: - Get Projects Tests
    
    func testGetProjectsSuccess() throws {
        // Setup mock response
        let mockProjects = [
            Project(name: "Project1", path: "/Users/test/Project1", type: "node"),
            Project(name: "Project2", path: "/Users/test/Project2", type: "swift")
        ]
        let projectsResponse = ProjectsResponse(basePath: "/Users/test", projects: mockProjects)
        let responseData = try JSONEncoder().encode(projectsResponse)
        
        mockURLSession.data = responseData
        mockURLSession.response = HTTPURLResponse(
            url: URL(string: "https://test.com/api/projects")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        mockConnectionManager.mockURL = URL(string: "https://test.com/api/projects")
        
        let expectation = XCTestExpectation(description: "Get projects completion")
        
        projectManager.getProjects { result in
            switch result {
            case .success(let projects):
                XCTAssertEqual(projects.count, 2)
                XCTAssertEqual(projects[0].name, "Project1")
                XCTAssertEqual(projects[0].path, "/Users/test/Project1")
                XCTAssertEqual(projects[0].type, "node")
                XCTAssertEqual(projects[1].name, "Project2")
                XCTAssertEqual(projects[1].path, "/Users/test/Project2")
                XCTAssertEqual(projects[1].type, "swift")
            case .failure(let error):
                XCTFail("Expected success, got error: \(error)")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testGetProjectsFallbackToSimpleArray() throws {
        // Setup mock response as simple array (fallback parsing)
        let projectArray = [
            ["name": "Project1", "path": "/Users/test/Project1", "type": "node"],
            ["name": "Project2", "path": "/Users/test/Project2"] // Missing type
        ]
        let responseData = try JSONSerialization.data(withJSONObject: projectArray)
        
        mockURLSession.data = responseData
        mockURLSession.response = HTTPURLResponse(
            url: URL(string: "https://test.com/api/projects")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        mockConnectionManager.mockURL = URL(string: "https://test.com/api/projects")
        
        let expectation = XCTestExpectation(description: "Get projects fallback completion")
        
        projectManager.getProjects { result in
            switch result {
            case .success(let projects):
                XCTAssertEqual(projects.count, 2)
                XCTAssertEqual(projects[0].name, "Project1")
                XCTAssertEqual(projects[0].type, "node")
                XCTAssertEqual(projects[1].name, "Project2")
                XCTAssertEqual(projects[1].type, "other") // Default type
            case .failure(let error):
                XCTFail("Expected success, got error: \(error)")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testGetProjectsInvalidURL() {
        mockConnectionManager.mockURL = nil // Invalid URL
        
        let expectation = XCTestExpectation(description: "Get projects invalid URL")
        
        projectManager.getProjects { result in
            switch result {
            case .success:
                XCTFail("Expected failure for invalid URL")
            case .failure(let error):
                if case .invalidURL = error {
                    // Expected error
                } else {
                    XCTFail("Expected invalidURL error, got: \(error)")
                }
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testGetProjectsNetworkError() {
        mockConnectionManager.mockURL = URL(string: "https://test.com/api/projects")
        mockURLSession.error = NSError(domain: "TestDomain", code: -1, userInfo: [NSLocalizedDescriptionKey: "Network error"])
        
        let expectation = XCTestExpectation(description: "Get projects network error")
        
        projectManager.getProjects { result in
            switch result {
            case .success:
                XCTFail("Expected failure for network error")
            case .failure(let error):
                if case .networkError(let message) = error {
                    XCTAssertEqual(message, "Network error")
                } else {
                    XCTFail("Expected networkError, got: \(error)")
                }
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testGetProjectsAuthenticationFailed() {
        mockConnectionManager.mockURL = URL(string: "https://test.com/api/projects")
        mockURLSession.response = HTTPURLResponse(
            url: URL(string: "https://test.com/api/projects")!,
            statusCode: 401,
            httpVersion: nil,
            headerFields: nil
        )
        mockURLSession.data = Data()
        
        let expectation = XCTestExpectation(description: "Get projects auth failed")
        
        projectManager.getProjects { result in
            switch result {
            case .success:
                XCTFail("Expected failure for auth error")
            case .failure(let error):
                if case .authenticationFailed = error {
                    // Expected error
                } else {
                    XCTFail("Expected authenticationFailed, got: \(error)")
                }
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testGetProjectsServerError() {
        mockConnectionManager.mockURL = URL(string: "https://test.com/api/projects")
        mockURLSession.response = HTTPURLResponse(
            url: URL(string: "https://test.com/api/projects")!,
            statusCode: 500,
            httpVersion: nil,
            headerFields: nil
        )
        mockURLSession.data = Data()
        
        let expectation = XCTestExpectation(description: "Get projects server error")
        
        projectManager.getProjects { result in
            switch result {
            case .success:
                XCTFail("Expected failure for server error")
            case .failure(let error):
                if case .serverError = error {
                    // Expected error
                } else {
                    XCTFail("Expected serverError, got: \(error)")
                }
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Create Folder Tests
    
    func testCreateFolderSuccess() throws {
        let response = FolderCreationResponse(
            message: "Folder created successfully",
            folder: FolderInfo(name: "test-folder", path: "/Users/test/Project1/test-folder")
        )
        let responseData = try JSONEncoder().encode(response)
        
        mockURLSession.data = responseData
        mockURLSession.response = HTTPURLResponse(
            url: URL(string: "https://test.com/api/projects/Project1/folders")!,
            statusCode: 201,
            httpVersion: nil,
            headerFields: nil
        )
        mockConnectionManager.mockURL = URL(string: "https://test.com/api/projects/Project1/folders")
        
        let expectation = XCTestExpectation(description: "Create folder completion")
        
        projectManager.createFolder(in: "Project1", folderName: "test-folder") { result in
            switch result {
            case .success(let response):
                XCTAssertEqual(response.message, "Folder created successfully")
                XCTAssertEqual(response.folder.name, "test-folder")
                XCTAssertEqual(response.folder.path, "/Users/test/Project1/test-folder")
            case .failure(let error):
                XCTFail("Expected success, got error: \(error)")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testCreateFolderInvalidInput() {
        let errorResponse = FolderErrorResponse(
            error: "INVALID_NAME",
            message: "Invalid folder name"
        )
        let responseData = try! JSONEncoder().encode(errorResponse)
        
        mockConnectionManager.mockURL = URL(string: "https://test.com/api/projects/Project1/folders")
        mockURLSession.data = responseData
        mockURLSession.response = HTTPURLResponse(
            url: URL(string: "https://test.com/api/projects/Project1/folders")!,
            statusCode: 400,
            httpVersion: nil,
            headerFields: nil
        )
        
        let expectation = XCTestExpectation(description: "Create folder invalid input")
        
        projectManager.createFolder(in: "Project1", folderName: "invalid/name") { result in
            switch result {
            case .success:
                XCTFail("Expected failure for invalid input")
            case .failure(let error):
                if case .invalidInput(let message) = error {
                    XCTAssertEqual(message, "Invalid folder name")
                } else {
                    XCTFail("Expected invalidInput error, got: \(error)")
                }
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testCreateFolderAlreadyExists() {
        let errorResponse = FolderErrorResponse(
            error: "ALREADY_EXISTS",
            message: "Folder already exists"
        )
        let responseData = try! JSONEncoder().encode(errorResponse)
        
        mockConnectionManager.mockURL = URL(string: "https://test.com/api/projects/Project1/folders")
        mockURLSession.data = responseData
        mockURLSession.response = HTTPURLResponse(
            url: URL(string: "https://test.com/api/projects/Project1/folders")!,
            statusCode: 409,
            httpVersion: nil,
            headerFields: nil
        )
        
        let expectation = XCTestExpectation(description: "Create folder already exists")
        
        projectManager.createFolder(in: "Project1", folderName: "existing-folder") { result in
            switch result {
            case .success:
                XCTFail("Expected failure for existing folder")
            case .failure(let error):
                if case .alreadyExists(let message) = error {
                    XCTAssertEqual(message, "Folder already exists")
                } else {
                    XCTFail("Expected alreadyExists error, got: \(error)")
                }
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testCreateFolderProjectNotFound() {
        mockConnectionManager.mockURL = URL(string: "https://test.com/api/projects/NonExistent/folders")
        mockURLSession.data = Data()
        mockURLSession.response = HTTPURLResponse(
            url: URL(string: "https://test.com/api/projects/NonExistent/folders")!,
            statusCode: 404,
            httpVersion: nil,
            headerFields: nil
        )
        
        let expectation = XCTestExpectation(description: "Create folder project not found")
        
        projectManager.createFolder(in: "NonExistent", folderName: "test-folder") { result in
            switch result {
            case .success:
                XCTFail("Expected failure for missing project")
            case .failure(let error):
                if case .notFound(let message) = error {
                    XCTAssertEqual(message, "Project not found")
                } else {
                    XCTFail("Expected notFound error, got: \(error)")
                }
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Validate Project Path Tests
    
    func testValidateProjectPathValid() {
        let validationResponse = ["valid": true]
        let responseData = try! JSONSerialization.data(withJSONObject: validationResponse)
        
        mockConnectionManager.mockURL = URL(string: "https://test.com/api/projects/validate")
        mockURLSession.data = responseData
        mockURLSession.response = HTTPURLResponse(
            url: URL(string: "https://test.com/api/projects/validate")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        
        let expectation = XCTestExpectation(description: "Validate project path valid")
        
        projectManager.validateProjectPath("/Users/test/ValidProject") { result in
            switch result {
            case .success(let isValid):
                XCTAssertTrue(isValid)
            case .failure(let error):
                XCTFail("Expected success, got error: \(error)")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testValidateProjectPathInvalid() {
        mockConnectionManager.mockURL = URL(string: "https://test.com/api/projects/validate")
        mockURLSession.data = Data()
        mockURLSession.response = HTTPURLResponse(
            url: URL(string: "https://test.com/api/projects/validate")!,
            statusCode: 400,
            httpVersion: nil,
            headerFields: nil
        )
        
        let expectation = XCTestExpectation(description: "Validate project path invalid")
        
        projectManager.validateProjectPath("/invalid/path") { result in
            switch result {
            case .success(let isValid):
                XCTAssertFalse(isValid)
            case .failure(let error):
                XCTFail("Expected success with false result, got error: \(error)")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testValidateProjectPathNotFound() {
        mockConnectionManager.mockURL = URL(string: "https://test.com/api/projects/validate")
        mockURLSession.data = Data()
        mockURLSession.response = HTTPURLResponse(
            url: URL(string: "https://test.com/api/projects/validate")!,
            statusCode: 404,
            httpVersion: nil,
            headerFields: nil
        )
        
        let expectation = XCTestExpectation(description: "Validate project path not found")
        
        projectManager.validateProjectPath("/nonexistent/path") { result in
            switch result {
            case .success(let isValid):
                XCTAssertFalse(isValid)
            case .failure(let error):
                XCTFail("Expected success with false result, got error: \(error)")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testValidateProjectPathNoResponseData() {
        mockConnectionManager.mockURL = URL(string: "https://test.com/api/projects/validate")
        mockURLSession.data = nil // No response data
        mockURLSession.response = HTTPURLResponse(
            url: URL(string: "https://test.com/api/projects/validate")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        
        let expectation = XCTestExpectation(description: "Validate project path no data")
        
        projectManager.validateProjectPath("/Users/test/Project") { result in
            switch result {
            case .success(let isValid):
                XCTAssertTrue(isValid) // Should assume valid if no response data
            case .failure(let error):
                XCTFail("Expected success, got error: \(error)")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Data Model Tests
    
    func testProjectDataModel() throws {
        let projectData = ProjectData(
            name: "TestProject",
            path: "/Users/test/TestProject",
            type: "swift",
            lastModified: Date()
        )
        
        // Test encoding
        let encoder = JSONEncoder()
        let data = try encoder.encode(projectData)
        XCTAssertGreaterThan(data.count, 0)
        
        // Test decoding
        let decoder = JSONDecoder()
        let decodedProject = try decoder.decode(ProjectData.self, from: data)
        
        XCTAssertEqual(decodedProject.name, projectData.name)
        XCTAssertEqual(decodedProject.path, projectData.path)
        XCTAssertEqual(decodedProject.type, projectData.type)
    }
    
    func testFolderCreationResponseModel() throws {
        let folderInfo = FolderInfo(name: "test-folder", path: "/Users/test/Project/test-folder")
        let response = FolderCreationResponse(
            message: "Folder created",
            folder: folderInfo
        )
        
        // Test encoding
        let encoder = JSONEncoder()
        let data = try encoder.encode(response)
        XCTAssertGreaterThan(data.count, 0)
        
        // Test decoding
        let decoder = JSONDecoder()
        let decodedResponse = try decoder.decode(FolderCreationResponse.self, from: data)
        
        XCTAssertEqual(decodedResponse.message, response.message)
        XCTAssertEqual(decodedResponse.folder.name, response.folder.name)
        XCTAssertEqual(decodedResponse.folder.path, response.folder.path)
    }
    
    func testFolderErrorResponseModel() throws {
        let errorResponse = FolderErrorResponse(
            error: "INVALID_NAME",
            message: "Folder name is invalid"
        )
        
        // Test encoding
        let encoder = JSONEncoder()
        let data = try encoder.encode(errorResponse)
        XCTAssertGreaterThan(data.count, 0)
        
        // Test decoding
        let decoder = JSONDecoder()
        let decodedError = try decoder.decode(FolderErrorResponse.self, from: data)
        
        XCTAssertEqual(decodedError.error, errorResponse.error)
        XCTAssertEqual(decodedError.message, errorResponse.message)
    }
    
    // MARK: - Edge Cases Tests
    
    func testGetProjectsEmptyResponse() throws {
        let projectsResponse = ProjectsResponse(basePath: "/Users/test", projects: [])
        let responseData = try JSONEncoder().encode(projectsResponse)
        
        mockURLSession.data = responseData
        mockURLSession.response = HTTPURLResponse(
            url: URL(string: "https://test.com/api/projects")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        mockConnectionManager.mockURL = URL(string: "https://test.com/api/projects")
        
        let expectation = XCTestExpectation(description: "Get projects empty")
        
        projectManager.getProjects { result in
            switch result {
            case .success(let projects):
                XCTAssertEqual(projects.count, 0)
            case .failure(let error):
                XCTFail("Expected success with empty array, got error: \(error)")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testCreateFolderWithSpecialCharacters() throws {
        let response = FolderCreationResponse(
            message: "Folder created successfully",
            folder: FolderInfo(name: "test-folder-123_special", path: "/Users/test/Project1/test-folder-123_special")
        )
        let responseData = try JSONEncoder().encode(response)
        
        mockURLSession.data = responseData
        mockURLSession.response = HTTPURLResponse(
            url: URL(string: "https://test.com/api/projects/Project1/folders")!,
            statusCode: 201,
            httpVersion: nil,
            headerFields: nil
        )
        mockConnectionManager.mockURL = URL(string: "https://test.com/api/projects/Project1/folders")
        
        let expectation = XCTestExpectation(description: "Create folder special characters")
        
        projectManager.createFolder(in: "Project1", folderName: "test-folder-123_special") { result in
            switch result {
            case .success(let response):
                XCTAssertEqual(response.folder.name, "test-folder-123_special")
            case .failure(let error):
                XCTFail("Expected success, got error: \(error)")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testValidateProjectPathWithSpaces() {
        let validationResponse = ["valid": true]
        let responseData = try! JSONSerialization.data(withJSONObject: validationResponse)
        
        mockConnectionManager.mockURL = URL(string: "https://test.com/api/projects/validate")
        mockURLSession.data = responseData
        mockURLSession.response = HTTPURLResponse(
            url: URL(string: "https://test.com/api/projects/validate")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        
        let expectation = XCTestExpectation(description: "Validate project path with spaces")
        
        projectManager.validateProjectPath("/Users/test/Project With Spaces") { result in
            switch result {
            case .success(let isValid):
                XCTAssertTrue(isValid)
            case .failure(let error):
                XCTFail("Expected success, got error: \(error)")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
}

// MARK: - Mock Classes

class MockURLSession: URLSession, @unchecked Sendable {
    var data: Data?
    var response: URLResponse?
    var error: Error?
    
    override func dataTask(with request: URLRequest, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask {
        return MockURLSessionDataTask {
            completionHandler(self.data, self.response, self.error)
        }
    }
}

class MockURLSessionDataTask: URLSessionDataTask, @unchecked Sendable {
    private let completion: () -> Void
    
    init(completion: @escaping () -> Void) {
        self.completion = completion
        super.init()
    }
    
    override func resume() {
        completion()
    }
}

class MockAICLIConnectionManager: AICLIConnectionManager {
    var mockURL: URL?
    var mockRequest: URLRequest?
    
    override init(urlSession: URLSession) {
        super.init(urlSession: urlSession)
    }
    
    override func buildURL(path: String) -> URL? {
        return mockURL
    }
    
    override func createAuthenticatedRequest(url: URL, method: String = "GET") -> URLRequest {
        if let mockRequest = mockRequest {
            return mockRequest
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        return request
    }
}