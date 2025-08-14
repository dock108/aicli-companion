import XCTest
import SwiftUI
@testable import AICLICompanion

@available(iOS 16.0, macOS 13.0, *)
@MainActor
final class ChatViewModelProjectIsolationTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Reset singleton state before each test
        ChatViewModel.shared.messages.removeAll()
        ChatViewModel.shared.currentProject = nil
        ChatViewModel.shared.currentSessionId = nil
    }
    
    override func tearDown() {
        // Clean up after each test
        ChatViewModel.shared.messages.removeAll()
        ChatViewModel.shared.currentProject = nil
        ChatViewModel.shared.currentSessionId = nil
        super.tearDown()
    }
    
    // MARK: - Project Isolation Tests
    
    func testMessagesAreIsolatedBetweenProjects() async throws {
        let viewModel = ChatViewModel.shared
        
        // Create two test projects
        let project1 = Project(name: "Project 1", path: "/path/to/project1", type: "Test")
        let project2 = Project(name: "Project 2", path: "/path/to/project2", type: "Test")
        
        // Set project 1 and add messages
        viewModel.currentProject = project1
        viewModel.messages.append(Message(content: "Message 1 for Project 1", sender: .user, type: .text))
        viewModel.messages.append(Message(content: "Message 2 for Project 1", sender: .assistant, type: .text))
        
        XCTAssertEqual(viewModel.messages.count, 2, "Project 1 should have 2 messages")
        
        // Switch to project 2
        viewModel.currentProject = project2
        
        // Messages should be empty for project 2
        XCTAssertEqual(viewModel.messages.count, 0, "Project 2 should have no messages")
        
        // Add messages to project 2
        viewModel.messages.append(Message(content: "Message 1 for Project 2", sender: .user, type: .text))
        
        XCTAssertEqual(viewModel.messages.count, 1, "Project 2 should have 1 message")
        
        // Switch back to project 1
        viewModel.currentProject = project1
        
        // Should see project 1's messages again
        XCTAssertEqual(viewModel.messages.count, 2, "Project 1 should still have 2 messages")
        XCTAssertEqual(viewModel.messages[0].content, "Message 1 for Project 1")
        XCTAssertEqual(viewModel.messages[1].content, "Message 2 for Project 1")
        
        // Switch back to project 2
        viewModel.currentProject = project2
        
        // Should see project 2's messages
        XCTAssertEqual(viewModel.messages.count, 1, "Project 2 should still have 1 message")
        XCTAssertEqual(viewModel.messages[0].content, "Message 1 for Project 2")
    }
    
    func testSessionIdsAreIsolatedBetweenProjects() async throws {
        let viewModel = ChatViewModel.shared
        
        // Create two test projects
        let project1 = Project(name: "Project 1", path: "/path/to/project1", type: "Test")
        let project2 = Project(name: "Project 2", path: "/path/to/project2", type: "Test")
        
        // Set project 1 with a session ID
        viewModel.currentProject = project1
        viewModel.currentSessionId = "session-id-project-1"
        
        XCTAssertEqual(viewModel.currentSessionId, "session-id-project-1")
        
        // Switch to project 2
        viewModel.currentProject = project2
        
        // Session ID should be nil for project 2
        XCTAssertNil(viewModel.currentSessionId, "Project 2 should have no session ID")
        
        // Set session ID for project 2
        viewModel.currentSessionId = "session-id-project-2"
        
        XCTAssertEqual(viewModel.currentSessionId, "session-id-project-2")
        
        // Switch back to project 1
        viewModel.currentProject = project1
        
        // Should see project 1's session ID again
        XCTAssertEqual(viewModel.currentSessionId, "session-id-project-1")
        
        // Switch back to project 2
        viewModel.currentProject = project2
        
        // Should see project 2's session ID
        XCTAssertEqual(viewModel.currentSessionId, "session-id-project-2")
    }
    
    func testLoadingStateIsProjectSpecific() async throws {
        let viewModel = ChatViewModel.shared
        
        // Create two test projects
        let project1 = Project(name: "Project 1", path: "/path/to/project1", type: "Test")
        let project2 = Project(name: "Project 2", path: "/path/to/project2", type: "Test")
        
        // Set project 1 and simulate loading
        viewModel.currentProject = project1
        viewModel.isLoading = true
        viewModel.clearLoadingState(for: project2.path)  // This should not affect project 1
        
        // Loading should still be true for project 1
        XCTAssertTrue(viewModel.isLoadingForProject(project1.path))
        XCTAssertFalse(viewModel.isLoadingForProject(project2.path))
        
        // Clear loading for project 1
        viewModel.clearLoadingState(for: project1.path)
        XCTAssertFalse(viewModel.isLoadingForProject(project1.path))
    }
    
    func testClearingSessionClearsOnlyCurrentProject() async throws {
        let viewModel = ChatViewModel.shared
        
        // Create two test projects
        let project1 = Project(name: "Project 1", path: "/path/to/project1", type: "Test")
        let project2 = Project(name: "Project 2", path: "/path/to/project2", type: "Test")
        
        // Set up both projects with messages
        viewModel.currentProject = project1
        viewModel.currentSessionId = "session-1"
        viewModel.messages.append(Message(content: "Project 1 message", sender: .user, type: .text))
        
        viewModel.currentProject = project2
        viewModel.currentSessionId = "session-2"
        viewModel.messages.append(Message(content: "Project 2 message", sender: .user, type: .text))
        
        // Clear messages for project 2
        viewModel.messages.removeAll()
        viewModel.currentSessionId = nil
        viewModel.currentProject = project2  // Trigger save
        
        // Project 2 should be cleared
        XCTAssertEqual(viewModel.messages.count, 0)
        XCTAssertNil(viewModel.currentSessionId)
        
        // Switch to project 1 - it should still have its messages
        viewModel.currentProject = project1
        XCTAssertEqual(viewModel.messages.count, 1)
        XCTAssertEqual(viewModel.messages[0].content, "Project 1 message")
        XCTAssertEqual(viewModel.currentSessionId, "session-1")
    }
    
    func testMessagesAppendToCorrectProject() async throws {
        let viewModel = ChatViewModel.shared
        
        // Create test projects
        let project1 = Project(name: "Project 1", path: "/path/to/project1", type: "Test")
        let project2 = Project(name: "Project 2", path: "/path/to/project2", type: "Test")
        
        // Add message to project 1
        viewModel.currentProject = project1
        let message1 = Message(content: "Message for Project 1", sender: .user, type: .text)
        viewModel.messages.append(message1)
        
        // Switch to project 2 and add different message
        viewModel.currentProject = project2
        let message2 = Message(content: "Message for Project 2", sender: .user, type: .text)
        viewModel.messages.append(message2)
        
        // Verify project 2 has only its message
        XCTAssertEqual(viewModel.messages.count, 1)
        XCTAssertEqual(viewModel.messages[0].content, "Message for Project 2")
        
        // Switch back to project 1
        viewModel.currentProject = project1
        
        // Verify project 1 still has only its message
        XCTAssertEqual(viewModel.messages.count, 1)
        XCTAssertEqual(viewModel.messages[0].content, "Message for Project 1")
    }
}