import XCTest
@testable import AICLICompanion

final class AICLICompanionTests: XCTestCase {
    func testHapticManagerInitialization() throws {
        let manager = HapticManager.shared

        XCTAssertNotNil(manager)

        // Test that methods don't crash on macOS (they should be no-ops)
        manager.lightImpact()
        manager.success()
        manager.messageSent()
    }

    func testKeychainManagerInitialization() throws {
        let manager = KeychainManager()

        XCTAssertNotNil(manager)
    }

    func testAICLIServiceInitialization() throws {
        let service = AICLIService()

        XCTAssertNotNil(service)

        // Ensure proper cleanup
        service.disconnect()

        // Allow async operations to complete
        let expectation = XCTestExpectation(description: "Cleanup")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func testPackageBuildSuccess() throws {
        // This test simply verifies that the package builds and imports successfully
        XCTAssertTrue(true, "Package builds and imports successfully")
    }
}
