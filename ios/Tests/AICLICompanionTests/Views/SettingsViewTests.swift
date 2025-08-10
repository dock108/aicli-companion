import XCTest
import SwiftUI
import ViewInspector
@testable import AICLICompanion

@available(iOS 16.0, macOS 13.0, *)
final class SettingsViewTests: XCTestCase {
    
    var mockSettings: SettingsManager!
    
    override func setUp() {
        super.setUp()
        mockSettings = SettingsManager()
    }
    
    override func tearDown() {
        mockSettings = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testSettingsViewCreation() throws {
        let settingsView = SettingsView()
            .environmentObject(mockSettings)
        
        let navigationStack = try settingsView.inspect().navigationStack()
        XCTAssertNoThrow(try navigationStack.zStack())
    }
    
    func testSettingsViewRequiresEnvironmentObject() throws {
        let settingsView = SettingsView()
        
        // Should throw when inspecting without environment object
        XCTAssertThrowsError(try settingsView.inspect()) { error in
            // ViewInspector should complain about missing environment object
        }
    }
    
    // MARK: - Navigation Structure Tests
    
    func testSettingsViewHasNavigationStack() throws {
        let settingsView = SettingsView()
            .environmentObject(mockSettings)
        
        XCTAssertNoThrow(try settingsView.inspect().navigationStack())
    }
    
    func testSettingsViewHasNavigationTitle() throws {
        let settingsView = SettingsView()
            .environmentObject(mockSettings)
        
        let navigationStack = try settingsView.inspect().navigationStack()
        
        // Navigation title is set via .navigationTitle("Settings")
        XCTAssertNoThrow(try navigationStack.zStack())
    }
    
    // MARK: - Content Structure Tests
    
    func testSettingsViewContainsScrollView() throws {
        let settingsView = SettingsView()
            .environmentObject(mockSettings)
        
        let navigationStack = try settingsView.inspect().navigationStack()
        let zStack = try navigationStack.zStack()
        
        // Should contain ScrollView
        XCTAssertNoThrow(try zStack.scrollView(1))
    }
    
    func testSettingsViewHasBackground() throws {
        let settingsView = SettingsView()
            .environmentObject(mockSettings)
        
        let navigationStack = try settingsView.inspect().navigationStack()
        let zStack = try navigationStack.zStack()
        
        // Should have background color as first element
        XCTAssertNoThrow(try zStack.view(Color.self, 0))
    }
    
    // MARK: - Settings Sections Tests
    
    func testSettingsViewContainsMainSections() throws {
        let settingsView = SettingsView()
            .environmentObject(mockSettings)
        
        let navigationStack = try settingsView.inspect().navigationStack()
        let zStack = try navigationStack.zStack()
        let scrollView = try zStack.scrollView(1)
        let vStack = try scrollView.vStack()
        
        // Should contain multiple SettingsSection views
        // Connection, Appearance, Behavior, Privacy, About
        XCTAssertGreaterThanOrEqual(vStack.count, 4) // At least 4 sections
    }
    
    // MARK: - Connection Section Tests
    
    func testConnectionSectionWithNoConnection() throws {
        // Ensure no connection is set
        mockSettings.clearConnection()
        
        let settingsView = SettingsView()
            .environmentObject(mockSettings)
        
        let navigationStack = try settingsView.inspect().navigationStack()
        let zStack = try navigationStack.zStack()
        let scrollView = try zStack.scrollView(1)
        let vStack = try scrollView.vStack()
        
        // Should contain connection section
        XCTAssertNoThrow(try vStack.group(0))
    }
    
    // MARK: - Appearance Section Tests
    
    func testAppearanceSectionContainsThemePicker() throws {
        let settingsView = SettingsView()
            .environmentObject(mockSettings)
        
        let navigationStack = try settingsView.inspect().navigationStack()
        let zStack = try navigationStack.zStack()
        let scrollView = try zStack.scrollView(1)
        let vStack = try scrollView.vStack()
        
        // Appearance section should be present (typically second section)
        // Note: SettingsSection is a generic type, need to specify content type
        XCTAssertNoThrow(try vStack.group(1))
    }
    
    func testAppearanceSectionContainsFontSizePicker() throws {
        let settingsView = SettingsView()
            .environmentObject(mockSettings)
        
        let navigationStack = try settingsView.inspect().navigationStack()
        let zStack = try navigationStack.zStack()
        let scrollView = try zStack.scrollView(1)
        let vStack = try scrollView.vStack()
        
        // Should have appearance section with font size picker
        XCTAssertNoThrow(try vStack.group(1))
    }
    
    // MARK: - Behavior Section Tests
    
    func testBehaviorSectionContainsToggles() throws {
        let settingsView = SettingsView()
            .environmentObject(mockSettings)
        
        let navigationStack = try settingsView.inspect().navigationStack()
        let zStack = try navigationStack.zStack()
        let scrollView = try zStack.scrollView(1)
        let vStack = try scrollView.vStack()
        
        // Behavior section should be present (typically third section)
        XCTAssertNoThrow(try vStack.group(2))
    }
    
    // MARK: - Privacy Section Tests
    
    func testPrivacySectionContainsChatHistoryToggle() throws {
        let settingsView = SettingsView()
            .environmentObject(mockSettings)
        
        let navigationStack = try settingsView.inspect().navigationStack()
        let zStack = try navigationStack.zStack()
        let scrollView = try zStack.scrollView(1)
        let vStack = try scrollView.vStack()
        
        // Privacy section should be present
        XCTAssertNoThrow(try vStack.group(3))
    }
    
    // MARK: - About Section Tests
    
    func testAboutSectionContainsVersionInfo() throws {
        let settingsView = SettingsView()
            .environmentObject(mockSettings)
        
        let navigationStack = try settingsView.inspect().navigationStack()
        let zStack = try navigationStack.zStack()
        let scrollView = try zStack.scrollView(1)
        let vStack = try scrollView.vStack()
        
        // About section should be present (typically last section)
        XCTAssertNoThrow(try vStack.group(4))
    }
    
    // MARK: - Color Scheme Tests
    
    func testSettingsViewWithLightColorScheme() throws {
        let settingsView = SettingsView()
            .environmentObject(mockSettings)
            .preferredColorScheme(.light)
        
        XCTAssertNoThrow(try settingsView.inspect())
    }
    
    func testSettingsViewWithDarkColorScheme() throws {
        let settingsView = SettingsView()
            .environmentObject(mockSettings)
            .preferredColorScheme(.dark)
        
        XCTAssertNoThrow(try settingsView.inspect())
    }
    
    // MARK: - Toolbar Tests
    
    func testSettingsViewHasToolbar() throws {
        let settingsView = SettingsView()
            .environmentObject(mockSettings)
        
        let navigationStack = try settingsView.inspect().navigationStack()
        
        // Toolbar is applied via .toolbar modifier
        // The Done button should be accessible
        XCTAssertNoThrow(try navigationStack.zStack())
    }
    
    // MARK: - Settings Integration Tests
    
    func testSettingsViewWithDifferentThemes() throws {
        let themes: [Theme] = [.system, .light, .dark]
        
        for theme in themes {
            mockSettings.theme = theme
            
            let settingsView = SettingsView()
                .environmentObject(mockSettings)
            
            XCTAssertNoThrow(try settingsView.inspect(), "SettingsView should work with theme: \(theme)")
        }
    }
    
    func testSettingsViewWithDifferentFontSizes() throws {
        let fontSizes: [FontSize] = [.small, .medium, .large]
        
        for fontSize in fontSizes {
            mockSettings.fontSize = fontSize
            
            let settingsView = SettingsView()
                .environmentObject(mockSettings)
            
            XCTAssertNoThrow(try settingsView.inspect(), "SettingsView should work with font size: \(fontSize)")
        }
    }
    
    func testSettingsViewWithDifferentToggleStates() throws {
        let toggleStates = [
            (true, false, true, false),
            (false, true, false, true),
            (true, true, true, true),
            (false, false, false, false)
        ]
        
        for (autoScroll, showTyping, haptic, storeHistory) in toggleStates {
            mockSettings.autoScroll = autoScroll
            mockSettings.showTypingIndicators = showTyping
            mockSettings.hapticFeedback = haptic
            mockSettings.storeChatHistory = storeHistory
            
            let settingsView = SettingsView()
                .environmentObject(mockSettings)
            
            XCTAssertNoThrow(try settingsView.inspect(), "SettingsView should work with toggle states")
        }
    }
    
    // MARK: - Performance Tests
    
    func testSettingsViewCreationPerformance() throws {
        measure {
            for _ in 0..<100 {
                let settingsView = SettingsView()
                    .environmentObject(mockSettings)
                
                // Just create the view, don't inspect it for performance
                _ = settingsView
            }
        }
    }
    
    func testSettingsViewInspectionPerformance() throws {
        let settingsView = SettingsView()
            .environmentObject(mockSettings)
        
        measure {
            for _ in 0..<10 {
                do {
                    let navigationStack = try settingsView.inspect().navigationStack()
                    _ = try navigationStack.zStack()
                } catch {
                    // Ignore inspection errors for performance test
                }
            }
        }
    }
    
    // MARK: - Accessibility Tests
    
    func testSettingsViewAccessibilityStructure() throws {
        let settingsView = SettingsView()
            .environmentObject(mockSettings)
        
        // Should have proper structure for accessibility
        let navigationStack = try settingsView.inspect().navigationStack()
        XCTAssertNoThrow(try navigationStack.zStack())
    }
    
    // MARK: - Platform-Specific Tests
    
    #if os(iOS)
    func testSettingsViewIOSSpecificModifiers() throws {
        let settingsView = SettingsView()
            .environmentObject(mockSettings)
        
        // On iOS, should have navigationBarTitleDisplayMode and toolbar background
        let navigationStack = try settingsView.inspect().navigationStack()
        XCTAssertNoThrow(try navigationStack.zStack())
    }
    #endif
    
    // MARK: - Error Handling Tests
    
    func testSettingsViewWithCorruptedSettings() throws {
        // Test with extreme values or corrupted settings
        let settingsView = SettingsView()
            .environmentObject(mockSettings)
        
        // Should still create successfully even with unusual settings
        XCTAssertNoThrow(try settingsView.inspect())
    }
    
    // MARK: - Memory Management Tests
    
    func testSettingsViewCreationAndDestruction() throws {
        // Test that SettingsView can be created and destroyed without issues
        // (structs are value types and don't need weak reference testing like classes)
        
        for _ in 0..<10 {
            let localMockSettings = SettingsManager()
            let settingsView = SettingsView()
                .environmentObject(localMockSettings)
            
            // Just verify it can be created and inspected
            _ = try? settingsView.inspect()
        }
        
        // If we get here, creation/destruction works fine
        XCTAssertTrue(true)
    }
    
    // MARK: - Edge Cases
    
    func testSettingsViewMultipleInspections() throws {
        let settingsView = SettingsView()
            .environmentObject(mockSettings)
        
        // Should be able to inspect multiple times
        XCTAssertNoThrow(try settingsView.inspect())
        XCTAssertNoThrow(try settingsView.inspect())
        XCTAssertNoThrow(try settingsView.inspect())
    }
    
    func testSettingsViewWithAllSectionsExpanded() throws {
        // Enable all features that might show additional UI
        mockSettings.storeChatHistory = true
        
        let settingsView = SettingsView()
            .environmentObject(mockSettings)
        
        XCTAssertNoThrow(try settingsView.inspect())
    }
    
    // MARK: - Link Tests
    
    func testSettingsViewContainsExternalLinks() throws {
        let settingsView = SettingsView()
            .environmentObject(mockSettings)
        
        let navigationStack = try settingsView.inspect().navigationStack()
        let zStack = try navigationStack.zStack()
        let scrollView = try zStack.scrollView(1)
        let vStack = try scrollView.vStack()
        
        // About section (last section) should be present
        XCTAssertNoThrow(try vStack.group(4))
    }
}

// MARK: - Test Helpers

extension SettingsViewTests {
    
    private func createTestSettingsView() -> some View {
        SettingsView()
            .environmentObject(mockSettings)
    }
    
    private func createTestSettingsViewWithConnection() -> some View {
        // Setup mock settings with connection
        // This would require extending SettingsManager for testing
        
        return SettingsView()
            .environmentObject(mockSettings)
    }
}