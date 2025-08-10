# macOS App Test Coverage Implementation Plan

## 🎯 Mission
Increase macOS AICLI Companion Host app test coverage from 22% to 80% through comprehensive unit testing that doesn't launch the app UI or trigger system permissions.

## 📊 Current State Analysis
- **Current Coverage:** 22% (1 test file with 8 basic tests)
- **Total Swift Files:** 34 production files
- **Test Files:** 1 (AICLICompanionHostTests.swift)
- **Architecture:** SwiftUI + Combine, singleton services pattern
- **Key Challenge:** Tests must be true unit tests - no app launch, no UI, no permissions

## 🏗️ Test Implementation Strategy

### Phase 1: Mock Infrastructure Setup
**Priority: CRITICAL - Must complete first**

Create comprehensive mock infrastructure to enable isolated unit testing:
- `MockServerManager.swift` - Mock server lifecycle without actual processes
- `MockSettingsManager.swift` - In-memory settings without UserDefaults
- `MockNetworkMonitor.swift` - Simulated network state changes
- `MockKeychainManager.swift` - In-memory keychain operations
- `MockNotificationManager.swift` - Capture notifications without system calls
- `MockProcess.swift` - Simulate process execution without spawning
- `TestDataFactory.swift` - Generate consistent test data

### Phase 2: Service Layer Testing (Target: 90% coverage)
**Files to test with mocks:**

#### Core Services
- `ServerManager.swift` - Server lifecycle, health checks, auth token generation
- `SettingsManager.swift` - Settings persistence, validation, migration
- `NetworkMonitor.swift` - Network state detection, IP address discovery
- `KeychainManager.swift` - Secure token storage/retrieval
- `NotificationManager.swift` - Notification queuing and delivery

#### Server Management
- `ServerManager+Process.swift` - Process spawning, termination, monitoring
- `ServerManager+Health.swift` - Health check logic, retry mechanisms
- `ServerManager+Sessions.swift` - Session tracking, cleanup
- `ServerManager+Network.swift` - Port availability, network utilities
- `ServerManager+Logs.swift` - Log management, filtering, persistence

### Phase 3: Model Testing (Target: 95% coverage)
**Pure logic testing - no mocks needed:**

- `LogEntry.swift` - Log level logic, formatting, serialization
- `ServerHealth.swift` - Health state transitions, status determination
- `Session.swift` - Session validation, expiry calculation
- `ServerError.swift` - Error categorization, user-friendly messages
- `HealthResponse.swift` - JSON parsing, validation
- `ProjectsResponse.swift` - Project list parsing, sorting

### Phase 4: ViewModel Testing (Target: 85% coverage)
**Test with mock services:**

- `ContentViewModel.swift` - App state management, command handling
- `SettingsViewModel.swift` - Settings validation, apply logic
- `LogsViewModel.swift` - Log filtering, search, export
- `SessionsViewModel.swift` - Session lifecycle, refresh logic

### Phase 5: View Component Testing (Target: 60% coverage)
**Test presentational logic only:**

- `ServerControlView.swift` - Button states, connection string generation
- `LogsView.swift` - Log filtering UI logic, search state
- `SettingsView.swift` - Form validation, tab management
- `SessionsView.swift` - Session display logic, sorting

### Phase 6: Utility Testing (Target: 100% coverage)
**Pure functions and extensions:**

- `Extensions/` - All Swift extensions
- `Utilities/` - Helper functions, formatters
- `Constants.swift` - Configuration validation

## 📝 Test Implementation Guidelines

### Mock Design Principles
```swift
// EXAMPLE: MockServerManager
@MainActor
class MockServerManager: ObservableObject {
    @Published var isRunning = false
    @Published var port = 3001
    var startServerCalled = false
    var stopServerCalled = false
    
    func startServer() async throws {
        startServerCalled = true
        isRunning = true
        // NO actual process spawning
        // NO UI interactions
        // NO permission requests
    }
}
```

### Test Structure Template
```swift
final class ServerManagerTests: XCTestCase {
    var sut: ServerManager!  // System Under Test
    var mockProcess: MockProcess!
    var mockSettings: MockSettingsManager!
    
    override func setUp() {
        super.setUp()
        // Inject mocks, no app launch
        mockProcess = MockProcess()
        mockSettings = MockSettingsManager()
        sut = ServerManager(
            process: mockProcess,
            settings: mockSettings
        )
    }
    
    override func tearDown() {
        // Clean up all state
        sut = nil
        mockProcess = nil
        mockSettings = nil
        super.tearDown()
    }
}
```

## 🚫 What NOT to Do

1. **NO App Launch**: Tests must not instantiate AICLICompanionHostApp
2. **NO UI Creation**: No actual SwiftUI views rendered
3. **NO System Dialogs**: No permission requests, alerts, or notifications
4. **NO Network Calls**: All networking must be mocked
5. **NO File System**: Use in-memory storage for all persistence
6. **NO Process Spawning**: Mock all Process interactions
7. **NO Keychain Access**: Mock all security operations
8. **NO UserDefaults**: Use in-memory settings storage

## ✅ Success Criteria

- [ ] All tests run without launching the app
- [ ] No system permission dialogs appear during tests
- [ ] Tests complete in under 10 seconds total
- [ ] Code coverage reaches 80% minimum
- [ ] All tests pass consistently (no flaky tests)
- [ ] Mock infrastructure supports full isolation
- [ ] CI pipeline validates coverage on every commit

## 🔄 Implementation Order

1. **Week 1**: Mock infrastructure (Phase 1)
2. **Week 1**: Service layer tests (Phase 2)
3. **Week 2**: Model & ViewModel tests (Phases 3-4)
4. **Week 2**: View & Utility tests (Phases 5-6)
5. **Week 2**: Coverage validation & cleanup

## 📊 Coverage Tracking

| Component | Current | Target | Priority |
|-----------|---------|--------|----------|
| Services | 10% | 90% | HIGH |
| Models | 5% | 95% | HIGH |
| ViewModels | 15% | 85% | MEDIUM |
| Views | 20% | 60% | LOW |
| Utilities | 30% | 100% | MEDIUM |
| **TOTAL** | **22%** | **80%** | - |

## 🎯 Current Focus
Starting with Phase 1: Creating mock infrastructure to enable proper unit testing without app launch or system interactions.

---
Last Updated: 2025-08-10
Status: Ready for implementation