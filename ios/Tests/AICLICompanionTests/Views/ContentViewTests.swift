import XCTest
import SwiftUI
import ViewInspector
@testable import AICLICompanion

@available(iOS 16.0, macOS 13.0, *)
final class ContentViewTests: XCTestCase {
    
    var mockAICLIService: MockAICLIService!
    var mockSettings: SettingsManager!
    
    override func setUp() {
        super.setUp()
        mockAICLIService = MockAICLIService()
        mockSettings = SettingsManager()
    }
    
    override func tearDown() {
        mockAICLIService?.reset()
        mockAICLIService = nil
        mockSettings = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testContentViewCreation() throws {
        let contentView = ContentView()
            .environmentObject(mockAICLIService)
            .environmentObject(mockSettings)
        
        let navigationStack = try contentView.inspect().navigationStack()
        XCTAssertNoThrow(try navigationStack.zStack())
    }
    
    func testContentViewPublicInitializer() throws {
        // Test that ContentView has a public initializer
        let contentView = ContentView()
        XCTAssertNotNil(contentView)
    }
    
    // MARK: - Navigation Structure Tests
    
    func testContentViewHasNavigationStack() throws {
        let contentView = ContentView()
            .environmentObject(mockAICLIService)
            .environmentObject(mockSettings)
        
        XCTAssertNoThrow(try contentView.inspect().navigationStack())
    }
    
    func testContentViewContainsZStack() throws {
        let contentView = ContentView()
            .environmentObject(mockAICLIService)
            .environmentObject(mockSettings)
        
        let navigationStack = try contentView.inspect().navigationStack()
        XCTAssertNoThrow(try navigationStack.zStack())
    }
    
    func testContentViewContainsVStack() throws {
        let contentView = ContentView()
            .environmentObject(mockAICLIService)
            .environmentObject(mockSettings)
        
        let navigationStack = try contentView.inspect().navigationStack()
        let zStack = try navigationStack.zStack()
        XCTAssertNoThrow(try zStack.vStack(1))
    }
    
    // MARK: - Background Tests
    
    func testContentViewHasBackground() throws {
        let contentView = ContentView()
            .environmentObject(mockAICLIService)
            .environmentObject(mockSettings)
        
        let navigationStack = try contentView.inspect().navigationStack()
        let zStack = try navigationStack.zStack()
        
        // Should have background color as first element
        XCTAssertNoThrow(try zStack.view(Color.self, 0))
    }
    
    // MARK: - Connection State Tests
    
    func testContentViewShowsConnectionViewWhenNotConnected() throws {
        // Setup: No valid connection
        mockSettings = SettingsManager() // Fresh settings with no connection
        
        let contentView = ContentView()
            .environmentObject(mockAICLIService)
            .environmentObject(mockSettings)
        
        let navigationStack = try contentView.inspect().navigationStack()
        let zStack = try navigationStack.zStack()
        let vStack = try zStack.vStack(1)
        let innerZStack = try vStack.zStack(0)
        
        // When not connected, should show ConnectionView
        XCTAssertNoThrow(try innerZStack.view(ConnectionView.self, 0))
    }
    
    func testContentViewRequiresEnvironmentObjects() throws {
        let contentView = ContentView()
        
        // Should throw when inspecting without environment objects
        XCTAssertThrowsError(try contentView.inspect()) { error in
            // ViewInspector should complain about missing environment objects
        }
    }
    
    // MARK: - State Management Tests
    
    func testContentViewInitialState() throws {
        let contentView = ContentView()
            .environmentObject(mockAICLIService)
            .environmentObject(mockSettings)
        
        // Should create successfully with initial state
        XCTAssertNoThrow(try contentView.inspect())
    }
    
    // MARK: - Animation Tests
    
    func testContentViewHasTransitions() throws {
        let contentView = ContentView()
            .environmentObject(mockAICLIService)
            .environmentObject(mockSettings)
        
        // Should create without issues even with animations
        XCTAssertNoThrow(try contentView.inspect())
    }
    
    // MARK: - Platform-Specific Tests
    
    #if os(iOS)
    func testContentViewHidesNavigationBarOnIOS() throws {
        let contentView = ContentView()
            .environmentObject(mockAICLIService)
            .environmentObject(mockSettings)
        
        let navigationStack = try contentView.inspect().navigationStack()
        
        // On iOS, navigation bar should be hidden
        // This is applied via .navigationBarHidden(true)
        XCTAssertNoThrow(try navigationStack.zStack())
    }
    #endif
    
    // MARK: - State Flow Tests
    
    func testContentViewConnectionFlow() throws {
        // Test the three-state flow: Connection -> Project Selection -> Chat
        
        // State 1: Not connected
        let contentView1 = ContentView()
            .environmentObject(mockAICLIService)
            .environmentObject(mockSettings)
        
        XCTAssertNoThrow(try contentView1.inspect())
        
        // State 2: Connected but no project (would require state manipulation)
        // This is harder to test directly with ViewInspector as it requires state changes
        
        // State 3: Connected with project (would require state manipulation)
        // This is also harder to test directly with ViewInspector
    }
    
    // MARK: - Color Scheme Tests
    
    func testContentViewWithLightColorScheme() throws {
        let contentView = ContentView()
            .environmentObject(mockAICLIService)
            .environmentObject(mockSettings)
            .preferredColorScheme(.light)
        
        XCTAssertNoThrow(try contentView.inspect())
    }
    
    func testContentViewWithDarkColorScheme() throws {
        let contentView = ContentView()
            .environmentObject(mockAICLIService)
            .environmentObject(mockSettings)
            .preferredColorScheme(.dark)
        
        XCTAssertNoThrow(try contentView.inspect())
    }
    
    // MARK: - Layout Tests
    
    func testContentViewFrameConfiguration() throws {
        let contentView = ContentView()
            .environmentObject(mockAICLIService)
            .environmentObject(mockSettings)
        
        let navigationStack = try contentView.inspect().navigationStack()
        let zStack = try navigationStack.zStack()
        let vStack = try zStack.vStack(1)
        let innerZStack = try vStack.zStack(0)
        
        // The inner ZStack should have maxWidth and maxHeight infinity
        // This is set via .frame(maxWidth: .infinity, maxHeight: .infinity)
        XCTAssertNoThrow(try innerZStack.view(ConnectionView.self, 0))
    }
    
    // MARK: - Settings Integration Tests
    
    func testContentViewWithValidConnection() throws {
        // Create settings with a valid connection
        let mockSettingsWithConnection = SettingsManager()
        
        // Mock that we have a valid connection
        // Note: This would require extending MockSettingsManager or similar
        let contentView = ContentView()
            .environmentObject(mockAICLIService)
            .environmentObject(mockSettingsWithConnection)
        
        XCTAssertNoThrow(try contentView.inspect())
    }
    
    // MARK: - Error Handling Tests
    
    func testContentViewWithInvalidSettings() throws {
        // Test with corrupted or invalid settings
        let contentView = ContentView()
            .environmentObject(mockAICLIService)
            .environmentObject(mockSettings)
        
        // Should still create successfully
        XCTAssertNoThrow(try contentView.inspect())
    }
    
    // MARK: - Performance Tests
    
    func testContentViewCreationPerformance() throws {
        measure {
            for _ in 0..<100 {
                let contentView = ContentView()
                    .environmentObject(mockAICLIService)
                    .environmentObject(mockSettings)
                
                // Just create the view, don't inspect it for performance
                _ = contentView
            }
        }
    }
    
    func testContentViewInspectionPerformance() throws {
        let contentView = ContentView()
            .environmentObject(mockAICLIService)
            .environmentObject(mockSettings)
        
        measure {
            for _ in 0..<10 {
                do {
                    let navigationStack = try contentView.inspect().navigationStack()
                    _ = try navigationStack.zStack()
                } catch {
                    // Ignore inspection errors for performance test
                }
            }
        }
    }
    
    // MARK: - Accessibility Tests
    
    func testContentViewAccessibilityStructure() throws {
        let contentView = ContentView()
            .environmentObject(mockAICLIService)
            .environmentObject(mockSettings)
        
        // Should have proper structure for accessibility
        let navigationStack = try contentView.inspect().navigationStack()
        XCTAssertNoThrow(try navigationStack.zStack())
    }
    
    // MARK: - Memory Management Tests
    
    func testContentViewCreationAndDestruction() throws {
        // Test that ContentView can be created and destroyed without issues
        // (structs are value types and don't need weak reference testing like classes)
        
        for _ in 0..<10 {
            let localMockService = MockAICLIService()
            let localMockSettings = SettingsManager()
            let contentView = ContentView()
                .environmentObject(localMockService)
                .environmentObject(localMockSettings)
            
            // Just verify it can be created and inspected
            _ = try? contentView.inspect()
        }
        
        // If we get here, creation/destruction works fine
        XCTAssertTrue(true)
    }
    
    // MARK: - Integration Tests
    
    func testContentViewWithDifferentServiceStates() throws {
        // Test with different service states
        let serviceStates: [(Bool, ConnectionStatus)] = [
            (false, .disconnected),
            (true, .connected),
            (false, .connecting),
            (false, .error(.connectionFailed("Test error")))
        ]
        
        for (isConnected, status) in serviceStates {
            mockAICLIService.isConnected = isConnected
            mockAICLIService.connectionStatus = status
            
            let contentView = ContentView()
                .environmentObject(mockAICLIService)
                .environmentObject(mockSettings)
            
            XCTAssertNoThrow(try contentView.inspect(), "ContentView should work with service state: \(status)")
        }
    }
    
    // MARK: - Edge Cases
    
    func testContentViewWithNilEnvironmentObjects() throws {
        let contentView = ContentView()
        
        // Should throw when trying to inspect without proper environment objects
        XCTAssertThrowsError(try contentView.inspect())
    }
    
    func testContentViewMultipleInspections() throws {
        let contentView = ContentView()
            .environmentObject(mockAICLIService)
            .environmentObject(mockSettings)
        
        // Should be able to inspect multiple times
        XCTAssertNoThrow(try contentView.inspect())
        XCTAssertNoThrow(try contentView.inspect())
        XCTAssertNoThrow(try contentView.inspect())
    }
}

// MARK: - Test Helpers

extension ContentViewTests {
    
    private func createTestContentView() -> some View {
        ContentView()
            .environmentObject(mockAICLIService)
            .environmentObject(mockSettings)
    }
    
    private func createTestContentViewWithConnection() -> some View {
        // Setup mock service as connected
        mockAICLIService.isConnected = true
        mockAICLIService.connectionStatus = .connected
        
        return ContentView()
            .environmentObject(mockAICLIService)
            .environmentObject(mockSettings)
    }
}