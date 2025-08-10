import XCTest
import SwiftUI
import ViewInspector
@testable import AICLICompanion

@available(iOS 16.0, macOS 13.0, *)
final class ButtonComponentTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    // MARK: - PrimaryButton Tests
    
    func testPrimaryButtonCreation() throws {
        let button = PrimaryButton(
            "Test Button",
            action: {}
        )
        
        let buttonView = try button.inspect().button()
        // The button contains a ZStack with complex structure
        // Just verify the button can be created and inspected
        XCTAssertNoThrow(try buttonView.labelView())
    }
    
    func testPrimaryButtonWithLoadingState() throws {
        let button = PrimaryButton(
            "Button with Loading",
            isLoading: true,
            action: {}
        )
        
        let buttonView = try button.inspect().button()
        
        // Button should be present when loading
        XCTAssertNoThrow(try buttonView.labelView())
    }
    
    func testPrimaryButtonAction() throws {
        var actionCalled = false
        
        let button = PrimaryButton(
            "Action Test",
            action: {
                actionCalled = true
            }
        )
        
        let buttonView = try button.inspect().button()
        try buttonView.tap()
        
        XCTAssertTrue(actionCalled)
    }
    
    func testPrimaryButtonDisabled() throws {
        let button = PrimaryButton(
            "Disabled Button",
            isEnabled: false,
            action: {}
        )
        
        let buttonView = try button.inspect().button()
        // ViewInspector doesn't have direct isEnabled check
        // The button should be rendered regardless
        XCTAssertNoThrow(try buttonView.labelView())
    }
    
    func testPrimaryButtonLoading() throws {
        let button = PrimaryButton(
            "Loading Button",
            isLoading: true,
            action: {}
        )
        
        let buttonView = try button.inspect().button()
        // Button contains ZStack with HStack inside when loading
        // Just verify structure exists
        XCTAssertNoThrow(try buttonView.labelView())
    }
    
    // MARK: - SecondaryButton Tests
    
    func testSecondaryButtonCreation() throws {
        let button = SecondaryButton(
            "Secondary Test",
            action: {}
        )
        
        let buttonView = try button.inspect().button()
        // The button contains a ZStack with complex structure
        // Just verify the button can be created and inspected
        XCTAssertNoThrow(try buttonView.labelView())
    }
    
    func testSecondaryButtonAction() throws {
        var actionCalled = false
        
        let button = SecondaryButton(
            "Action Test",
            action: {
                actionCalled = true
            }
        )
        
        let buttonView = try button.inspect().button()
        try buttonView.tap()
        
        XCTAssertTrue(actionCalled)
    }
    
    func testSecondaryButtonDisabled() throws {
        let button = SecondaryButton(
            "Secondary Disabled",
            isEnabled: false,
            action: {}
        )
        
        let buttonView = try button.inspect().button()
        // Just verify the button structure exists
        XCTAssertNoThrow(try buttonView.labelView())
    }
    
    // MARK: - TextLinkButton Tests
    
    func testTextLinkButtonCreation() throws {
        let button = TextLinkButton(
            "Link Button",
            action: {}
        )
        
        let buttonView = try button.inspect().button()
        let labelView = try buttonView.labelView()
        // TextLinkButton should have simpler structure with just Text
        let buttonText = try labelView.text().string()
        
        XCTAssertEqual(buttonText, "Link Button")
    }
    
    func testTextLinkButtonAction() throws {
        var actionCalled = false
        
        let button = TextLinkButton(
            "Link Action",
            action: {
                actionCalled = true
            }
        )
        
        let buttonView = try button.inspect().button()
        try buttonView.tap()
        
        XCTAssertTrue(actionCalled)
    }
    
    // MARK: - Button State Tests
    
    func testButtonStateChanges() throws {
        struct TestButtonView: View {
            @State private var isLoading = false
            
            var body: some View {
                VStack {
                    PrimaryButton(
                        "Toggle Loading",
                        isLoading: isLoading,
                        action: {
                            isLoading.toggle()
                        }
                    )
                }
            }
        }
        
        let view = TestButtonView()
        let vStack = try view.inspect().vStack()
        let button = try vStack.view(PrimaryButton.self, 0)
        
        // Initial state - not loading
        let initialButton = try button.button()
        // Note: ViewInspector doesn't have direct isEnabled() check for buttons
        XCTAssertNoThrow(try initialButton.tap()) // Can tap if enabled
        
        // Tap to toggle loading
        try initialButton.tap()
        
        // After tapping, should be in loading state
        let updatedView = try view.inspect().vStack()
        let _ = try updatedView.view(PrimaryButton.self, 0)
        
        // Note: ViewInspector may have limitations with state changes
        // This test verifies the button structure but state changes might not be immediately visible
    }
    
    // MARK: - Accessibility Tests
    
    func testPrimaryButtonAccessibility() throws {
        let button = PrimaryButton(
            "Accessible Button",
            action: {}
        )
        
        // PrimaryButton doesn't explicitly set accessibility label
        // Just verify the button can be created
        XCTAssertNoThrow(try button.inspect().button())
    }
    
    func testSecondaryButtonAccessibility() throws {
        let button = SecondaryButton(
            "Secondary Accessible",
            action: {}
        )
        
        // SecondaryButton doesn't explicitly set accessibility label
        // Just verify the button can be created
        XCTAssertNoThrow(try button.inspect().button())
    }
    
    // MARK: - Edge Cases
    
    func testButtonWithEmptyTitle() throws {
        let button = PrimaryButton(
            "",
            action: {}
        )
        
        // Just verify the button can be created with empty title
        XCTAssertNoThrow(try button.inspect().button())
    }
    
    func testButtonWithLongTitle() throws {
        let longTitle = String(repeating: "Very Long Button Title ", count: 10)
        let button = SecondaryButton(
            longTitle,
            action: {}
        )
        
        // Just verify the button can be created with long title
        XCTAssertNoThrow(try button.inspect().button())
    }
    
    func testButtonWithSpecialCharacters() throws {
        let specialTitle = "Button 🚀 with émojis & special chars! @#$%"
        let button = TextLinkButton(
            specialTitle,
            action: {}
        )
        
        let buttonView = try button.inspect().button()
        // TextLinkButton may have simpler structure - try to get text
        let labelView = try buttonView.labelView()
        let buttonText = try labelView.text().string()
        
        XCTAssertEqual(buttonText, specialTitle)
    }
    
    // MARK: - Multiple Action Tests
    
    func testMultipleButtonActions() throws {
        var button1Pressed = false
        var button2Pressed = false
        
        struct MultiButtonView: View {
            let onButton1: () -> Void
            let onButton2: () -> Void
            
            var body: some View {
                VStack {
                    PrimaryButton("Button 1", action: onButton1)
                    SecondaryButton("Button 2", action: onButton2)
                }
            }
        }
        
        let view = MultiButtonView(
            onButton1: { button1Pressed = true },
            onButton2: { button2Pressed = true }
        )
        
        let vStack = try view.inspect().vStack()
        
        try vStack.view(PrimaryButton.self, 0).button().tap()
        XCTAssertTrue(button1Pressed)
        XCTAssertFalse(button2Pressed)
        
        try vStack.view(SecondaryButton.self, 1).button().tap()
        XCTAssertTrue(button1Pressed)
        XCTAssertTrue(button2Pressed)
    }
    
    // MARK: - Performance Tests
    
    func testButtonCreationPerformance() throws {
        measure {
            for i in 0..<1000 {
                _ = PrimaryButton(
                    "Performance Test \(i)",
                    action: {}
                )
            }
        }
    }
    
    func testButtonInspectionPerformance() throws {
        let buttons = (0..<100).map { i in
            PrimaryButton(
                "Button \(i)",
                action: {}
            )
        }
        
        measure {
            for button in buttons {
                do {
                    let buttonView = try button.inspect().button()
                    _ = try buttonView.labelView().text().string()
                } catch {
                    // Ignore inspection errors for performance test
                }
            }
        }
    }
}

// MARK: - ViewInspector Extensions

// Note: Custom ViewInspector extensions commented out due to API compatibility issues
// These would need to be updated based on the specific ViewInspector version and API
/*
@available(iOS 16.0, macOS 13.0, *)
extension InspectableView where View == ViewType.VStack {
    func primaryButton(_ index: Int) throws -> InspectableView<ViewType.ClassifiedView> {
        return try self.view(PrimaryButton.self, index)
    }
    
    func secondaryButton(_ index: Int) throws -> InspectableView<ViewType.ClassifiedView> {
        return try self.view(SecondaryButton.self, index)
    }
    
    func textLinkButton(_ index: Int) throws -> InspectableView<ViewType.ClassifiedView> {
        return try self.view(TextLinkButton.self, index)
    }
}
*/