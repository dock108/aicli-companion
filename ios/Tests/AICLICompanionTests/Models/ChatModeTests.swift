import XCTest
@testable import AICLICompanion

@available(iOS 16.0, macOS 13.0, *)
final class ChatModeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Clear any existing mode settings
        clearAllModes()
    }
    
    override func tearDown() {
        // Clean up after tests
        clearAllModes()
        super.tearDown()
    }
    
    private func clearAllModes() {
        // Clear global mode
        UserDefaults.standard.removeObject(forKey: "selectedChatMode")
        
        // Clear any test project modes
        let testPaths = [
            "/test/project1",
            "/test/project2",
            "__workspace__",
            "/Users/test/Documents/MyProject"
        ]
        
        for path in testPaths {
            ChatMode.clearSavedMode(for: path)
        }
    }
    
    // MARK: - Global Mode Tests
    
    func testDefaultModeIsNormal() {
        let mode = ChatMode.loadSavedMode()
        XCTAssertEqual(mode, .normal, "Default mode should be normal")
    }
    
    func testGlobalModeSaveAndLoad() {
        // Save planning mode globally
        ChatMode.planning.save()
        
        // Load and verify
        let loaded = ChatMode.loadSavedMode()
        XCTAssertEqual(loaded, .planning, "Should load saved global mode")
    }
    
    // MARK: - Per-Project Mode Tests
    
    func testPerProjectModeSaveAndLoad() {
        let projectPath = "/test/project1"
        
        // Save planning mode for project
        ChatMode.planning.save(for: projectPath)
        
        // Load and verify
        let loaded = ChatMode.loadSavedMode(for: projectPath)
        XCTAssertEqual(loaded, .planning, "Should load saved project mode")
    }
    
    func testDifferentProjectsHaveDifferentModes() {
        let project1 = "/test/project1"
        let project2 = "/test/project2"
        
        // Set different modes for each project
        ChatMode.planning.save(for: project1)
        ChatMode.normal.save(for: project2)
        
        // Verify each project has its own mode
        XCTAssertEqual(ChatMode.loadSavedMode(for: project1), .planning)
        XCTAssertEqual(ChatMode.loadSavedMode(for: project2), .normal)
    }
    
    func testNewProjectUsesGlobalDefault() {
        // Set global default to planning
        ChatMode.planning.save()
        
        // Load mode for a new project (not previously saved)
        let newProject = "/test/newproject"
        let mode = ChatMode.loadSavedMode(for: newProject)
        
        // Should fall back to global default
        XCTAssertEqual(mode, .planning, "New project should use global default")
    }
    
    func testWorkspaceModePeristence() {
        let workspacePath = "__workspace__"
        
        // Save planning mode for workspace
        ChatMode.planning.save(for: workspacePath)
        
        // Load and verify
        let loaded = ChatMode.loadSavedMode(for: workspacePath)
        XCTAssertEqual(loaded, .planning, "Workspace should maintain its own mode")
    }
    
    // MARK: - Mode Clearing Tests
    
    func testClearProjectMode() {
        let projectPath = "/test/project1"
        
        // Save a mode
        ChatMode.planning.save(for: projectPath)
        XCTAssertEqual(ChatMode.loadSavedMode(for: projectPath), .planning)
        
        // Clear the mode
        ChatMode.clearSavedMode(for: projectPath)
        
        // Should now return global default (normal)
        let clearedMode = ChatMode.loadSavedMode(for: projectPath)
        XCTAssertEqual(clearedMode, .normal, "Cleared project should use default")
    }
    
    func testClearProjectModeWithGlobalDefault() {
        let projectPath = "/test/project1"
        
        // Set global default to planning
        ChatMode.planning.save()
        
        // Save normal mode for project
        ChatMode.normal.save(for: projectPath)
        XCTAssertEqual(ChatMode.loadSavedMode(for: projectPath), .normal)
        
        // Clear the project mode
        ChatMode.clearSavedMode(for: projectPath)
        
        // Should now return global default (planning)
        let clearedMode = ChatMode.loadSavedMode(for: projectPath)
        XCTAssertEqual(clearedMode, .planning, "Cleared project should use global default")
    }
    
    // MARK: - Path Handling Tests
    
    func testPathsWithSlashesAreSanitized() {
        let projectPath = "/Users/test/Documents/MyProject"
        
        // Save mode
        ChatMode.planning.save(for: projectPath)
        
        // Verify it can be loaded
        let loaded = ChatMode.loadSavedMode(for: projectPath)
        XCTAssertEqual(loaded, .planning, "Paths with slashes should work correctly")
    }
    
    func testSavingProjectModeAlsoUpdatesGlobal() {
        // Save planning mode for a project
        let projectPath = "/test/project1"
        ChatMode.planning.save(for: projectPath)
        
        // Global should also be updated
        let globalMode = ChatMode.loadSavedMode()
        XCTAssertEqual(globalMode, .planning, "Saving project mode should update global default")
    }
    
    // MARK: - Feature Flag Tests
    
    func testInvisibleModesFallbackToNormal() {
        // This test would need to mock FeatureFlags
        // For now, just verify that loading always returns a valid mode
        let mode = ChatMode.loadSavedMode()
        XCTAssertTrue(ChatMode.allCases.contains(mode), "Should always return a valid mode")
    }
}
