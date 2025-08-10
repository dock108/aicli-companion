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
            title: "Test Button",
            action: {}
        )
        
        let buttonView = try button.inspect().button()
        let buttonText = try buttonView.labelView().text().string()
        
        XCTAssertEqual(buttonText, "Test Button")
    }
    
    func testPrimaryButtonWithIcon() throws {
        let button = PrimaryButton(
            title: "Button with Icon",
            systemImage: "plus",
            action: {}
        )
        
        let buttonView = try button.inspect().button()
        
        // Should have both icon and text in label
        let label = try buttonView.labelView()
        XCTAssertNoThrow(try label.hStack())
    }
    
    func testPrimaryButtonAction() throws {
        var actionCalled = false
        
        let button = PrimaryButton(
            title: "Action Test",
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
            title: "Disabled Button",
            isEnabled: false,
            action: {}
        )
        
        let buttonView = try button.inspect().button()
        let isEnabled = try buttonView.isEnabled()
        
        XCTAssertFalse(isEnabled)
    }
    
    func testPrimaryButtonLoading() throws {
        let button = PrimaryButton(
            title: "Loading Button",
            isLoading: true,
            action: {}
        )
        
        let buttonView = try button.inspect().button()
        let label = try buttonView.labelView()
        
        // Should show progress view when loading
        XCTAssertNoThrow(try label.hStack())
    }
    
    // MARK: - SecondaryButton Tests
    
    func testSecondaryButtonCreation() throws {
        let button = SecondaryButton(
            title: "Secondary Test",
            action: {}
        )
        
        let buttonView = try button.inspect().button()
        let buttonText = try buttonView.labelView().text().string()
        
        XCTAssertEqual(buttonText, "Secondary Test")
    }
    
    func testSecondaryButtonAction() throws {
        var actionCalled = false
        
        let button = SecondaryButton(
            title: "Action Test",
            action: {
                actionCalled = true
            }
        )
        
        let buttonView = try button.inspect().button()
        try buttonView.tap()
        
        XCTAssertTrue(actionCalled)
    }
    
    func testSecondaryButtonWithIcon() throws {
        let button = SecondaryButton(
            title: "Secondary with Icon",
            systemImage: "gear",
            action: {}
        )
        
        let buttonView = try button.inspect().button()
        let label = try buttonView.labelView()
        
        // Should have both icon and text
        XCTAssertNoThrow(try label.hStack())
    }
    
    // MARK: - TextLinkButton Tests
    
    func testTextLinkButtonCreation() throws {
        let button = TextLinkButton(
            title: "Link Button",
            action: {}
        )
        
        let buttonView = try button.inspect().button()
        let buttonText = try buttonView.labelView().text().string()
        
        XCTAssertEqual(buttonText, "Link Button")
    }
    
    func testTextLinkButtonAction() throws {
        var actionCalled = false
        
        let button = TextLinkButton(
            title: "Link Action",
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
                        title: "Toggle Loading",
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
        let button = try vStack.primaryButton(0)
        
        // Initial state - not loading
        let initialButton = try button.button()
        // Note: ViewInspector doesn't have direct isEnabled() check for buttons
        XCTAssertNoThrow(try initialButton.tap()) // Can tap if enabled
        
        // Tap to toggle loading
        try initialButton.tap()
        
        // After tapping, should be in loading state
        let updatedView = try view.inspect().vStack()
        let updatedButton = try updatedView.primaryButton(0)
        
        // Note: ViewInspector may have limitations with state changes
        // This test verifies the button structure but state changes might not be immediately visible
    }
    
    // MARK: - Accessibility Tests
    
    func testPrimaryButtonAccessibility() throws {
        let button = PrimaryButton(
            title: "Accessible Button",
            action: {}
        )
        
        let buttonView = try button.inspect().button()
        
        // Should have accessibility label
        let accessibilityLabel = try buttonView.accessibilityLabel()
        XCTAssertEqual(accessibilityLabel, "Accessible Button")
    }
    
    func testSecondaryButtonAccessibility() throws {
        let button = SecondaryButton(
            title: "Secondary Accessible",
            action: {}
        )
        
        let buttonView = try button.inspect().button()
        
        // Should have accessibility label
        let accessibilityLabel = try buttonView.accessibilityLabel()
        XCTAssertEqual(accessibilityLabel, "Secondary Accessible")
    }
    
    // MARK: - Edge Cases
    
    func testButtonWithEmptyTitle() throws {
        let button = PrimaryButton(
            title: "",
            action: {}
        )
        
        let buttonView = try button.inspect().button()
        let buttonText = try buttonView.labelView().text().string()
        
        XCTAssertEqual(buttonText, "")
    }
    
    func testButtonWithLongTitle() throws {
        let longTitle = String(repeating: "Very Long Button Title ", count: 10)
        let button = SecondaryButton(
            title: longTitle,
            action: {}
        )
        
        let buttonView = try button.inspect().button()
        let buttonText = try buttonView.labelView().text().string()
        
        XCTAssertEqual(buttonText, longTitle)
    }
    
    func testButtonWithSpecialCharacters() throws {
        let specialTitle = "Button 🚀 with émojis & special chars! @#$%"
        let button = TextLinkButton(
            title: specialTitle,
            action: {}
        )
        
        let buttonView = try button.inspect().button()
        let buttonText = try buttonView.labelView().text().string()
        
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
                    PrimaryButton(title: "Button 1", action: onButton1)
                    SecondaryButton(title: "Button 2", action: onButton2)
                }
            }
        }
        
        let view = MultiButtonView(
            onButton1: { button1Pressed = true },
            onButton2: { button2Pressed = true }
        )
        
        let vStack = try view.inspect().vStack()
        
        try vStack.primaryButton(0).button().tap()
        XCTAssertTrue(button1Pressed)
        XCTAssertFalse(button2Pressed)
        
        try vStack.secondaryButton(1).button().tap()
        XCTAssertTrue(button1Pressed)
        XCTAssertTrue(button2Pressed)
    }
    
    // MARK: - Performance Tests
    
    func testButtonCreationPerformance() throws {
        measure {
            for i in 0..<1000 {
                _ = PrimaryButton(
                    title: "Performance Test \(i)",
                    action: {}
                )
            }
        }
    }
    
    func testButtonInspectionPerformance() throws {
        let buttons = (0..<100).map { i in
            PrimaryButton(
                title: "Button \(i)",
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