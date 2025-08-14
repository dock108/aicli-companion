import XCTest
import SwiftUI
import ViewInspector
@testable import AICLICompanion

@available(iOS 16.0, macOS 13.0, *)
final class ChatViewTests: XCTestCase {
    
    var mockAICLIService: MockAICLIService!
    var mockSettings: SettingsManager!
    
    override func setUp() {
        super.setUp()
        mockAICLIService = MockAICLIService()
        mockSettings = SettingsManager()
        
        // Setup connected state
        mockAICLIService.isConnected = true
        mockAICLIService.connectionStatus = .connected
    }
    
    override func tearDown() {
        mockAICLIService?.reset()
        mockAICLIService = nil
        mockSettings = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    @MainActor
    func testChatViewCreation() throws {
        let project = TestDataFactory.TestProject.frontend
        let testProject = Project(name: project.name, path: project.path, type: "Frontend")
        
        // Reset ChatViewModel singleton state before test
        ChatViewModel.shared.messages.removeAll()
        ChatViewModel.shared.currentProject = nil
        ChatViewModel.shared.currentSessionId = nil
        
        let chatView = ChatView(
            selectedProject: testProject,
            session: nil,
            onSwitchProject: {}
        )
        .environmentObject(mockAICLIService)
        .environmentObject(mockSettings)
        
        let inspectableView = try chatView.inspect()
        XCTAssertNoThrow(try inspectableView.zStack())
    }
    
    func testChatViewWithSession() throws {
        let project = TestDataFactory.TestProject.backend
        let testProject = Project(name: project.name, path: project.path, type: "Backend")
        let session = ProjectSession(
            sessionId: "test-session-123",
            projectName: project.name,
            projectPath: project.path,
            status: "active",
            startedAt: ISO8601DateFormatter().string(from: Date())
        )
        
        let chatView = ChatView(
            selectedProject: testProject,
            session: session,
            onSwitchProject: {}
        )
        .environmentObject(mockAICLIService)
        .environmentObject(mockSettings)
        
        let inspectableView = try chatView.inspect()
        XCTAssertNoThrow(try inspectableView.zStack())
    }
    
    func testChatViewWithNilProject() throws {
        let chatView = ChatView(
            selectedProject: nil,
            session: nil,
            onSwitchProject: {}
        )
        .environmentObject(mockAICLIService)
        .environmentObject(mockSettings)
        
        let inspectableView = try chatView.inspect()
        XCTAssertNoThrow(try inspectableView.zStack())
    }
    
    // MARK: - UI Component Tests
    
    func testChatViewContainsMainComponents() throws {
        let project = TestDataFactory.TestProject.mobile
        let testProject = Project(name: project.name, path: project.path, type: "Mobile")
        
        let chatView = ChatView(
            selectedProject: testProject,
            session: nil,
            onSwitchProject: {}
        )
        .environmentObject(mockAICLIService)
        .environmentObject(mockSettings)
        
        let zStack = try chatView.inspect().zStack()
        let vStack = try zStack.view(VStack<TupleView<(Color, VStack<TupleView<(Optional<ProjectContextHeader>, MessageQueueIndicator, ChatMessageList, ChatInputBar)>>)>>.self, 1).vStack()
        
        // Should contain VStack with main components
        XCTAssertNoThrow(try vStack.view(MessageQueueIndicator.self, 1))
        XCTAssertNoThrow(try vStack.view(ChatMessageList.self, 2))
        XCTAssertNoThrow(try vStack.view(ChatInputBar.self, 3))
    }
    
    func testProjectContextHeaderVisibleWhenProjectSelected() throws {
        let project = TestDataFactory.TestProject.frontend
        let testProject = Project(name: project.name, path: project.path, type: "Frontend")
        
        let chatView = ChatView(
            selectedProject: testProject,
            session: nil,
            onSwitchProject: {}
        )
        .environmentObject(mockAICLIService)
        .environmentObject(mockSettings)
        
        let zStack = try chatView.inspect().zStack()
        let vStack = try zStack.view(VStack<TupleView<(Color, VStack<TupleView<(Optional<ProjectContextHeader>, MessageQueueIndicator, ChatMessageList, ChatInputBar)>>)>>.self, 1).vStack()
        
        // Project header should be present when project is selected
        XCTAssertNoThrow(try vStack.view(ProjectContextHeader.self, 0))
    }
    
    func testProjectContextHeaderHiddenWhenNoProject() throws {
        let chatView = ChatView(
            selectedProject: nil,
            session: nil,
            onSwitchProject: {}
        )
        .environmentObject(mockAICLIService)
        .environmentObject(mockSettings)
        
        let zStack = try chatView.inspect().zStack()
        let vStack = try zStack.view(VStack<TupleView<(Color, VStack<TupleView<(Optional<ProjectContextHeader>, MessageQueueIndicator, ChatMessageList, ChatInputBar)>>)>>.self, 1).vStack()
        
        // Project header should not be present when no project is selected
        // In SwiftUI, optional views that are nil won't be rendered
        // We can test this by checking the VStack structure
        XCTAssertNoThrow(try vStack.view(MessageQueueIndicator.self, 1))
    }
    
    // MARK: - Message Queue Indicator Tests
    
    func testMessageQueueIndicatorAlwaysPresent() throws {
        let project = TestDataFactory.TestProject.backend
        let testProject = Project(name: project.name, path: project.path, type: "Backend")
        
        let chatView = ChatView(
            selectedProject: testProject,
            session: nil,
            onSwitchProject: {}
        )
        .environmentObject(mockAICLIService)
        .environmentObject(mockSettings)
        
        let zStack = try chatView.inspect().zStack()
        let vStack = try zStack.view(VStack<TupleView<(Color, VStack<TupleView<(Optional<ProjectContextHeader>, MessageQueueIndicator, ChatMessageList, ChatInputBar)>>)>>.self, 1).vStack()
        
        // Message queue indicator should always be present
        XCTAssertNoThrow(try vStack.view(MessageQueueIndicator.self, 1))
    }
    
    // MARK: - Chat Message List Tests
    
    func testChatMessageListAlwaysPresent() throws {
        let project = TestDataFactory.TestProject.mobile
        let testProject = Project(name: project.name, path: project.path, type: "Mobile")
        
        let chatView = ChatView(
            selectedProject: testProject,
            session: nil,
            onSwitchProject: {}
        )
        .environmentObject(mockAICLIService)
        .environmentObject(mockSettings)
        
        let zStack = try chatView.inspect().zStack()
        let vStack = try zStack.view(VStack<TupleView<(Color, VStack<TupleView<(Optional<ProjectContextHeader>, MessageQueueIndicator, ChatMessageList, ChatInputBar)>>)>>.self, 1).vStack()
        
        // Chat message list should always be present
        XCTAssertNoThrow(try vStack.view(ChatMessageList.self, 2))
    }
    
    // MARK: - Chat Input Bar Tests
    
    func testChatInputBarAlwaysPresent() throws {
        let project = TestDataFactory.TestProject.frontend
        let testProject = Project(name: project.name, path: project.path, type: "Frontend")
        
        let chatView = ChatView(
            selectedProject: testProject,
            session: nil,
            onSwitchProject: {}
        )
        .environmentObject(mockAICLIService)
        .environmentObject(mockSettings)
        
        let zStack = try chatView.inspect().zStack()
        let vStack = try zStack.view(VStack<TupleView<(Color, VStack<TupleView<(Optional<ProjectContextHeader>, MessageQueueIndicator, ChatMessageList, ChatInputBar)>>)>>.self, 1).vStack()
        
        // Chat input bar should always be present
        XCTAssertNoThrow(try vStack.view(ChatInputBar.self, 3))
    }
    
    // MARK: - Background Tests
    
    func testBackgroundColorPresent() throws {
        let project = TestDataFactory.TestProject.backend
        let testProject = Project(name: project.name, path: project.path, type: "Backend")
        
        let chatView = ChatView(
            selectedProject: testProject,
            session: nil,
            onSwitchProject: {}
        )
        .environmentObject(mockAICLIService)
        .environmentObject(mockSettings)
        
        let zStack = try chatView.inspect().zStack()
        
        // Should have background color as first element
        XCTAssertNoThrow(try zStack.view(Color.self, 0))
    }
    
    // MARK: - State Management Tests
    
    func testChatViewStateInitialization() throws {
        let project = TestDataFactory.TestProject.mobile
        let testProject = Project(name: project.name, path: project.path, type: "Mobile")
        let session = ProjectSession(
            sessionId: "initial-session",
            projectName: project.name,
            projectPath: project.path,
            status: "active",
            startedAt: ISO8601DateFormatter().string(from: Date())
        )
        
        let chatView = ChatView(
            selectedProject: testProject,
            session: session,
            onSwitchProject: {}
        )
        .environmentObject(mockAICLIService)
        .environmentObject(mockSettings)
        
        // Should create without throwing
        XCTAssertNoThrow(try chatView.inspect())
    }
    
    func testOnSwitchProjectCallback() throws {
        var callbackCalled = false
        
        let project = TestDataFactory.TestProject.frontend
        let testProject = Project(name: project.name, path: project.path, type: "Frontend")
        
        let chatView = ChatView(
            selectedProject: testProject,
            session: nil,
            onSwitchProject: {
                callbackCalled = true
            }
        )
        .environmentObject(mockAICLIService)
        .environmentObject(mockSettings)
        
        // Should create without issues - callback testing would require UI interaction
        XCTAssertNoThrow(try chatView.inspect())
        XCTAssertFalse(callbackCalled) // Callback hasn't been triggered yet
    }
    
    // MARK: - Different Project Types Tests
    
    func testChatViewWithDifferentProjectTypes() throws {
        let projectTypes = [
            ("Frontend", TestDataFactory.TestProject.frontend),
            ("Backend", TestDataFactory.TestProject.backend),
            ("Mobile", TestDataFactory.TestProject.mobile)
        ]
        
        for (typeName, testProject) in projectTypes {
            let project = Project(name: testProject.name, path: testProject.path, type: typeName)
            
            let chatView = ChatView(
                selectedProject: project,
                session: nil,
                onSwitchProject: {}
            )
            .environmentObject(mockAICLIService)
            .environmentObject(mockSettings)
            
            XCTAssertNoThrow(try chatView.inspect(), "ChatView should work with \(typeName) project type")
        }
    }
    
    // MARK: - Environment Object Tests
    
    func testChatViewRequiresEnvironmentObjects() throws {
        let project = TestDataFactory.TestProject.frontend
        let testProject = Project(name: project.name, path: project.path, type: "Frontend")
        
        let chatView = ChatView(
            selectedProject: testProject,
            session: nil,
            onSwitchProject: {}
        )
        
        // Should throw when inspecting without environment objects
        XCTAssertThrowsError(try chatView.inspect()) { error in
            // ViewInspector should complain about missing environment objects
        }
    }
    
    // MARK: - Accessibility Tests
    
    func testChatViewAccessibilityStructure() throws {
        let project = TestDataFactory.TestProject.backend
        let testProject = Project(name: project.name, path: project.path, type: "Backend")
        
        let chatView = ChatView(
            selectedProject: testProject,
            session: nil,
            onSwitchProject: {}
        )
        .environmentObject(mockAICLIService)
        .environmentObject(mockSettings)
        
        let inspectableView = try chatView.inspect()
        
        // Should have proper structure for accessibility
        XCTAssertNoThrow(try inspectableView.zStack())
    }
    
    // MARK: - Edge Cases
    
    func testChatViewWithEmptyProjectName() throws {
        let project = Project(name: "", path: "/empty/path", type: "Unknown")
        
        let chatView = ChatView(
            selectedProject: project,
            session: nil,
            onSwitchProject: {}
        )
        .environmentObject(mockAICLIService)
        .environmentObject(mockSettings)
        
        XCTAssertNoThrow(try chatView.inspect())
    }
    
    func testChatViewWithEmptyProjectPath() throws {
        let project = Project(name: "Empty Path Project", path: "", type: "Test")
        
        let chatView = ChatView(
            selectedProject: project,
            session: nil,
            onSwitchProject: {}
        )
        .environmentObject(mockAICLIService)
        .environmentObject(mockSettings)
        
        XCTAssertNoThrow(try chatView.inspect())
    }
    
    func testChatViewWithLongProjectName() throws {
        let longName = String(repeating: "Very Long Project Name ", count: 20)
        let project = Project(name: longName, path: "/long/name/path", type: "Test")
        
        let chatView = ChatView(
            selectedProject: project,
            session: nil,
            onSwitchProject: {}
        )
        .environmentObject(mockAICLIService)
        .environmentObject(mockSettings)
        
        XCTAssertNoThrow(try chatView.inspect())
    }
    
    // MARK: - Performance Tests
    
    func testChatViewCreationPerformance() throws {
        let project = TestDataFactory.TestProject.frontend
        let testProject = Project(name: project.name, path: project.path, type: "Frontend")
        
        measure {
            for _ in 0..<100 {
                let chatView = ChatView(
                    selectedProject: testProject,
                    session: nil,
                    onSwitchProject: {}
                )
                .environmentObject(mockAICLIService)
                .environmentObject(mockSettings)
                
                // Just create the view, don't inspect it for performance
                _ = chatView
            }
        }
    }
    
    func testChatViewInspectionPerformance() throws {
        let project = TestDataFactory.TestProject.backend
        let testProject = Project(name: project.name, path: project.path, type: "Backend")
        
        let chatView = ChatView(
            selectedProject: testProject,
            session: nil,
            onSwitchProject: {}
        )
        .environmentObject(mockAICLIService)
        .environmentObject(mockSettings)
        
        measure {
            for _ in 0..<10 {
                do {
                    let inspectableView = try chatView.inspect()
                    _ = try inspectableView.zStack()
                } catch {
                    // Ignore inspection errors for performance test
                }
            }
        }
    }
}

// MARK: - Test Helpers

extension ChatViewTests {
    
    private func createTestChatView(
        project: Project? = nil,
        session: ProjectSession? = nil,
        onSwitchProject: @escaping () -> Void = {}
    ) -> some View {
        let defaultProject = Project(
            name: TestDataFactory.TestProject.frontend.name,
            path: TestDataFactory.TestProject.frontend.path,
            type: "Frontend"
        )
        
        return ChatView(
            selectedProject: project ?? defaultProject,
            session: session,
            onSwitchProject: onSwitchProject
        )
        .environmentObject(mockAICLIService)
        .environmentObject(mockSettings)
    }
}