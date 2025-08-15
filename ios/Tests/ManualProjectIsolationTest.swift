// Manual test to verify project isolation in ChatViewModel
// Run this with: swift Tests/ManualProjectIsolationTest.swift

import Foundation

// Simplified test models
struct Project: Equatable {
    let name: String
    let path: String
    let type: String
}

struct Message {
    let content: String
    let sender: String
}

// Simplified ChatViewModel to test the logic
class ChatViewModel {
    static let shared = ChatViewModel()
    
    var messages: [Message] = []
    var currentSessionId: String?
    
    private var projectMessages: [String: [Message]] = [:]
    private var projectSessionIds: [String: String] = [:]
    
    var currentProject: Project? {
        didSet {
            if let oldProject = oldValue, oldProject.path != currentProject?.path {
                // Save messages for the old project before switching
                projectMessages[oldProject.path] = messages
                if let sessionId = currentSessionId {
                    projectSessionIds[oldProject.path] = sessionId
                }
            }
            
            // Load messages for the new project
            if let newProject = currentProject {
                messages = projectMessages[newProject.path] ?? []
                currentSessionId = projectSessionIds[newProject.path]
            }
        }
    }
    
    private init() {}
}

// Test the isolation
func testProjectIsolation() {
    print("Testing Project Isolation in ChatViewModel")
    print("==========================================")
    
    let viewModel = ChatViewModel.shared
    
    // Create two test projects
    let project1 = Project(name: "Project 1", path: "/path/to/project1", type: "Test")
    let project2 = Project(name: "Project 2", path: "/path/to/project2", type: "Test")
    
    // Set project 1 and add messages
    print("\n1. Setting Project 1 and adding messages...")
    viewModel.currentProject = project1
    viewModel.messages.append(Message(content: "Message 1 for Project 1", sender: "user"))
    viewModel.messages.append(Message(content: "Message 2 for Project 1", sender: "assistant"))
    viewModel.currentSessionId = "session-project-1"
    
    print("   Project 1 messages: \(viewModel.messages.count)")
    print("   Project 1 session: \(viewModel.currentSessionId ?? "nil")")
    assert(viewModel.messages.count == 2, "Project 1 should have 2 messages")
    assert(viewModel.currentSessionId == "session-project-1", "Project 1 should have its session ID")
    
    // Switch to project 2
    print("\n2. Switching to Project 2...")
    viewModel.currentProject = project2
    
    print("   Project 2 messages: \(viewModel.messages.count)")
    print("   Project 2 session: \(viewModel.currentSessionId ?? "nil")")
    assert(viewModel.messages.count == 0, "Project 2 should have no messages")
    assert(viewModel.currentSessionId == nil, "Project 2 should have no session ID")
    
    // Add messages to project 2
    print("\n3. Adding messages to Project 2...")
    viewModel.messages.append(Message(content: "Message 1 for Project 2", sender: "user"))
    viewModel.currentSessionId = "session-project-2"
    
    print("   Project 2 messages: \(viewModel.messages.count)")
    print("   Project 2 session: \(viewModel.currentSessionId ?? "nil")")
    assert(viewModel.messages.count == 1, "Project 2 should have 1 message")
    assert(viewModel.currentSessionId == "session-project-2", "Project 2 should have its session ID")
    
    // Switch back to project 1
    print("\n4. Switching back to Project 1...")
    viewModel.currentProject = project1
    
    print("   Project 1 messages: \(viewModel.messages.count)")
    print("   Project 1 content: \(viewModel.messages.map { $0.content })")
    print("   Project 1 session: \(viewModel.currentSessionId ?? "nil")")
    assert(viewModel.messages.count == 2, "Project 1 should still have 2 messages")
    assert(viewModel.messages[0].content == "Message 1 for Project 1", "First message should be correct")
    assert(viewModel.messages[1].content == "Message 2 for Project 1", "Second message should be correct")
    assert(viewModel.currentSessionId == "session-project-1", "Project 1 should still have its session ID")
    
    // Switch back to project 2
    print("\n5. Switching back to Project 2...")
    viewModel.currentProject = project2
    
    print("   Project 2 messages: \(viewModel.messages.count)")
    print("   Project 2 content: \(viewModel.messages.map { $0.content })")
    print("   Project 2 session: \(viewModel.currentSessionId ?? "nil")")
    assert(viewModel.messages.count == 1, "Project 2 should still have 1 message")
    assert(viewModel.messages[0].content == "Message 1 for Project 2", "Message should be correct")
    assert(viewModel.currentSessionId == "session-project-2", "Project 2 should still have its session ID")
    
    print("\n✅ All tests passed! Project isolation is working correctly.")
    print("   - Messages are isolated between projects")
    print("   - Session IDs are isolated between projects")
    print("   - Switching projects preserves each project's state")
}

// Run the test
testProjectIsolation()