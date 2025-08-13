//
//  ViewTestHelpers.swift
//  AICLICompanionHostTests
//
//  Helper utilities for View testing
//

import XCTest
import SwiftUI
import Combine
@testable import AICLICompanionHost

// Note: ViewInspector needs to be added via Swift Package Manager in Xcode
// Add package: https://github.com/nalexn/ViewInspector

#if canImport(ViewInspector)
import ViewInspector

extension Inspection: InspectionEmissary { }
#endif

// MARK: - Test Helpers

@MainActor
class ViewTestCase: XCTestCase {
    var cancellables = Set<AnyCancellable>()

    // Common setup for view tests
    override func setUp() async throws {
        try await super.setUp()
        cancellables = Set<AnyCancellable>()
        // Reset shared state
        ServerManager.shared.isRunning = false
        SettingsManager.shared.resetToDefaults()
    }

    override func tearDown() async throws {
        cancellables.removeAll()
        try await super.tearDown()
    }

    // Helper to create a hosting controller for testing
    func hostView<V: View>(_ view: V) -> NSHostingController<V> {
        return NSHostingController(rootView: view)
    }

    // Helper to wait for async updates
    func waitForAsync(timeout: TimeInterval = 1.0) {
        let expectation = XCTestExpectation(description: "Async update")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: timeout)
    }
}

// MARK: - Mock Objects

class MockServerManagerForViews: ObservableObject {
    @Published var isRunning = false
    @Published var isProcessing = false
    @Published var serverHealth: ServerHealth = .unknown
    @Published var connectionString = ""
    @Published var logs: [LogEntry] = []
    @Published var activeSessions: [Session] = []

    func startServer() async throws {
        isProcessing = true
        try await Task.sleep(nanoseconds: 100_000_000)
        isRunning = true
        isProcessing = false
    }

    func stopServer() async {
        isProcessing = true
        try? await Task.sleep(nanoseconds: 100_000_000)
        isRunning = false
        isProcessing = false
    }
}

class MockSettingsManagerForViews: ObservableObject {
    @Published var serverPort = 3001
    @Published var autoStartServer = false
    @Published var enableNotifications = true
    @Published var theme = "auto"

    func resetToDefaults() {
        serverPort = 3001
        autoStartServer = false
        enableNotifications = true
        theme = "auto"
    }
}

// MARK: - View Inspection Extensions

#if canImport(ViewInspector)
extension View {
    func inspect() throws -> InspectableView<ViewType.View<Self>> {
        return try InspectableView<ViewType.View<Self>>(self, parent: nil)
    }
}
#endif

// MARK: - Test Data Generators

struct TestDataGenerator {

    static func createTestSession(id: String = UUID().uuidString) -> Session {
        return Session(
            sessionId: id,
            deviceName: "Test Device \(id)",
            connectedAt: Date(),
            signalStrength: 100.0
        )
    }

    static func createTestLogEntry(level: LogLevel = .info) -> LogEntry {
        return LogEntry(
            level: level,
            message: "Test log message at \(Date())"
        )
    }

    static func createTestLogs(count: Int, withErrors: Bool = false) -> [LogEntry] {
        var logs: [LogEntry] = []
        for i in 0..<count {
            let level: LogLevel = withErrors && i % 3 == 0 ? .error : .info
            logs.append(LogEntry(
                level: level,
                message: "Log entry \(i)"
            ))
        }
        return logs
    }
}

// MARK: - Assertion Helpers

extension XCTestCase {

    func assertViewExists<V: View>(_ view: V, file: StaticString = #file, line: UInt = #line) {
        let mirror = Mirror(reflecting: view)
        XCTAssertNotNil(mirror, "View should exist", file: file, line: line)
    }

    func assertPublishedValue<T: Equatable>(
        _ keyPath: KeyPath<ServerManager, T>,
        equals expected: T,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let actual = ServerManager.shared[keyPath: keyPath]
        XCTAssertEqual(actual, expected, file: file, line: line)
    }
}

// MARK: - SwiftUI Preview Helpers

#if DEBUG
struct PreviewWrapper<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(width: 800, height: 600)
            .environmentObject(ServerManager.shared)
            .environmentObject(SettingsManager.shared)
    }
}
#endif
