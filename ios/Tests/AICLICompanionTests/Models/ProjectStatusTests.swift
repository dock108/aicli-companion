import XCTest
import Combine
@testable import AICLICompanion

@available(iOS 17.0, macOS 14.0, *)
final class ProjectStatusTests: XCTestCase {
    // MARK: - Project Tests
    
    func testProjectInitialization() {
        let project = Project(
            name: "TestProject",
            path: "/Users/test/project",
            type: "Swift"
        )
        
        XCTAssertEqual(project.name, "TestProject")
        XCTAssertEqual(project.path, "/Users/test/project")
        XCTAssertEqual(project.type, "Swift")
        XCTAssertEqual(project.id, "/Users/test/project") // id should equal path
    }
    
    func testProjectCodable() throws {
        let project = Project(
            name: "DescribedProject",
            path: "/test/path",
            type: "TypeScript"
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(project)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Project.self, from: data)
        
        XCTAssertEqual(decoded.name, project.name)
        XCTAssertEqual(decoded.path, project.path)
        XCTAssertEqual(decoded.type, project.type)
    }
    
    func testProjectEquality() {
        let project1 = Project(
            name: "Project",
            path: "/path/one",
            type: "Swift"
        )
        
        let project2 = Project(
            name: "Different Name",
            path: "/path/one",
            type: "Different Type"
        )
        
        let project3 = Project(
            name: "Project",
            path: "/path/two",
            type: "Swift"
        )
        
        // Projects with same path should be equal
        XCTAssertEqual(project1.id, project2.id)
        // Projects with different paths should not be equal
        XCTAssertNotEqual(project1.id, project3.id)
    }
    
    // MARK: - StatusInfo Tests
    
    @MainActor
    func testStatusInfoInitialState() {
        let statusInfo = Project.StatusInfo()
        
        XCTAssertFalse(statusInfo.isProcessing)
        XCTAssertNil(statusInfo.lastActivity)
        XCTAssertNil(statusInfo.processingStartTime)
        XCTAssertEqual(statusInfo.elapsedSeconds, 0)
    }
    
    @MainActor
    func testStatusInfoUpdateFromHeartbeat() {
        let statusInfo = Project.StatusInfo()
        
        let heartbeatData: [AnyHashable: Any] = [
            "isProcessing": true,
            "activity": "Analyzing code",
            "elapsedSeconds": 42
        ]
        
        statusInfo.updateFromHeartbeat(heartbeatData)
        
        XCTAssertTrue(statusInfo.isProcessing)
        XCTAssertEqual(statusInfo.lastActivity, "Analyzing code")
        XCTAssertEqual(statusInfo.elapsedSeconds, 42)
        XCTAssertNotNil(statusInfo.processingStartTime)
    }
    
    @MainActor
    func testStatusInfoProcessingLifecycle() {
        let statusInfo = Project.StatusInfo()
        
        // Start processing
        let startData: [AnyHashable: Any] = [
            "isProcessing": true,
            "activity": "Starting",
            "elapsedSeconds": 0
        ]
        statusInfo.updateFromHeartbeat(startData)
        
        XCTAssertTrue(statusInfo.isProcessing)
        XCTAssertNotNil(statusInfo.processingStartTime)
        let startTime = statusInfo.processingStartTime
        
        // Update during processing
        let updateData: [AnyHashable: Any] = [
            "isProcessing": true,
            "activity": "Working",
            "elapsedSeconds": 10
        ]
        statusInfo.updateFromHeartbeat(updateData)
        
        XCTAssertTrue(statusInfo.isProcessing)
        XCTAssertEqual(statusInfo.processingStartTime, startTime) // Should not change
        XCTAssertEqual(statusInfo.elapsedSeconds, 10)
        
        // Stop processing
        let stopData: [AnyHashable: Any] = [
            "isProcessing": false
        ]
        statusInfo.updateFromHeartbeat(stopData)
        
        XCTAssertFalse(statusInfo.isProcessing)
        XCTAssertNil(statusInfo.processingStartTime)
        XCTAssertNil(statusInfo.lastActivity)
        XCTAssertEqual(statusInfo.elapsedSeconds, 0)
    }
    
    @MainActor
    func testStatusInfoReset() {
        let statusInfo = Project.StatusInfo()
        
        // Set some values
        let heartbeatData: [AnyHashable: Any] = [
            "isProcessing": true,
            "activity": "Testing",
            "elapsedSeconds": 100
        ]
        statusInfo.updateFromHeartbeat(heartbeatData)
        
        // Reset
        statusInfo.reset()
        
        XCTAssertFalse(statusInfo.isProcessing)
        XCTAssertNil(statusInfo.lastActivity)
        XCTAssertNil(statusInfo.processingStartTime)
        XCTAssertEqual(statusInfo.elapsedSeconds, 0)
    }
    
    @MainActor
    func testFormattedElapsedTime() {
        let statusInfo = Project.StatusInfo()
        
        // Test seconds only
        statusInfo.elapsedSeconds = 45
        XCTAssertEqual(statusInfo.formattedElapsedTime, "45s")
        
        // Test exactly one minute
        statusInfo.elapsedSeconds = 60
        XCTAssertEqual(statusInfo.formattedElapsedTime, "1m 0s")
        
        // Test minutes and seconds
        statusInfo.elapsedSeconds = 125
        XCTAssertEqual(statusInfo.formattedElapsedTime, "2m 5s")
        
        // Test large values
        statusInfo.elapsedSeconds = 3661
        XCTAssertEqual(statusInfo.formattedElapsedTime, "61m 1s")
    }
    
    // MARK: - ProjectStatusManager Tests
    
    @MainActor
    func testProjectStatusManagerSingleton() {
        let manager1 = ProjectStatusManager.shared
        let manager2 = ProjectStatusManager.shared
        
        XCTAssertTrue(manager1 === manager2)
    }
    
    @MainActor
    func testProjectStatusManagerGetStatus() {
        let manager = ProjectStatusManager.shared
        let project = Project(
            name: "Test",
            path: "/test/unique/path",
            type: "Swift"
        )
        
        // First access should create new status
        let status1 = manager.statusFor(project)
        XCTAssertNotNil(status1)
        
        // Second access should return same instance
        let status2 = manager.statusFor(project)
        XCTAssertTrue(status1 === status2)
    }
    
    @MainActor
    func testProjectStatusManagerGetStatusByPath() {
        let manager = ProjectStatusManager.shared
        let path = "/test/another/unique/path"
        
        let status1 = manager.statusFor(projectPath: path)
        let status2 = manager.statusFor(projectPath: path)
        
        XCTAssertTrue(status1 === status2)
    }
    
    @MainActor
    func testProjectStatusManagerClearAll() {
        let manager = ProjectStatusManager.shared
        
        // Create some statuses
        let path1 = "/test/clear/path1"
        let path2 = "/test/clear/path2"
        
        let status1 = manager.statusFor(projectPath: path1)
        let status2 = manager.statusFor(projectPath: path2)
        
        // Set them as processing
        status1.isProcessing = true
        status2.isProcessing = true
        
        // Clear all
        manager.clearAll()
        
        // All statuses should be reset
        XCTAssertFalse(status1.isProcessing)
        XCTAssertFalse(status2.isProcessing)
    }
    
    @MainActor
    func testProjectStatusManagerClearSpecificProject() {
        let manager = ProjectStatusManager.shared
        
        let project = Project(
            name: "Clear Test",
            path: "/test/clear/specific",
            type: "Swift"
        )
        
        let status = manager.statusFor(project)
        status.isProcessing = true
        status.elapsedSeconds = 50
        
        manager.clearStatus(for: project)
        
        XCTAssertFalse(status.isProcessing)
        XCTAssertEqual(status.elapsedSeconds, 0)
    }
    
    // MARK: - ProjectSession Tests
    
    func testProjectSessionInitialization() {
        let session = ProjectSession(
            sessionId: "session-abc",
            projectName: "MyProject",
            projectPath: "/my/project",
            status: "active",
            startedAt: "2024-01-01T12:00:00Z"
        )
        
        XCTAssertEqual(session.sessionId, "session-abc")
        XCTAssertEqual(session.projectName, "MyProject")
        XCTAssertEqual(session.projectPath, "/my/project")
        XCTAssertEqual(session.status, "active")
        XCTAssertEqual(session.startedAt, "2024-01-01T12:00:00Z")
    }
    
    func testProjectSessionCodable() throws {
        let session = ProjectSession(
            sessionId: "session-xyz",
            projectName: "TestProject",
            projectPath: "/test",
            status: "inactive",
            startedAt: "2024-01-01T12:00:00Z"
        )
        
        // Test codable
        let encoder = JSONEncoder()
        let data = try encoder.encode(session)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ProjectSession.self, from: data)
        
        XCTAssertEqual(decoded.sessionId, session.sessionId)
        XCTAssertEqual(decoded.projectName, session.projectName)
        XCTAssertEqual(decoded.projectPath, session.projectPath)
        XCTAssertEqual(decoded.status, session.status)
        XCTAssertEqual(decoded.startedAt, session.startedAt)
    }
}
