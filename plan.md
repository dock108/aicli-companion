# macOS App Test Coverage Improvement Plan

## Executive Summary
Improving test coverage for the macOS AICLI Companion Host app from 17.6% to 80% and re-enabling CI test enforcement. This will ensure code quality, prevent regressions, and establish a robust testing foundation.

## Current State Analysis

### Test Status
- **Total Tests**: 202
- **Passing**: ~200
- **Failing**: 2 (ServerDiscoveryTests)
- **Test Success Rate**: ~99%

### Coverage Metrics
- **App Target Coverage**: 17.6% (1671/9476 lines)
- **Test Target Coverage**: 82.0%
- **Overall Coverage**: 38.7%

### Coverage Gaps
- **0% Coverage**: All View files (18 files)
- **Partial Coverage**: ServerManager, SettingsManager, ProcessOutputHandling
- **Good Coverage**: KeychainManager, NetworkMonitor, NotificationManager

## Implementation Plan

### Phase 1: Fix Remaining Test Failures (Day 1 - IMMEDIATE)

#### TODO 1.1: Fix ServerDiscoveryTests.testFindServerDirectoryFallback
**File**: `macos-app/AICLICompanionHostTests/ServerDiscoveryTests.swift`
- Issue: Line 60 - XCTAssertTrue failing on log check
- Fix: Update log expectations to match new directory discovery logic
- Test: Verify with custom serverDirectory setting

#### TODO 1.2: Fix ServerDiscoveryTests.testLoggingDuringDiscovery
**File**: `macos-app/AICLICompanionHostTests/ServerDiscoveryTests.swift`
- Issue: Line 253 - XCTAssertTrue(logs.count > 0) failing
- Fix: Ensure findServerDirectory generates logs even when using custom path
- Test: Check log generation in all paths

#### TODO 1.3: Verify All Tests Pass
- Run full test suite without code signing
- Ensure no intermittent failures
- Generate baseline coverage report
- Document any flaky tests

### Phase 2: Model Layer Testing (Days 2-3)

#### TODO 2.1: Create ServerManagerLoggingTests
**File**: `macos-app/AICLICompanionHostTests/ServerManagerLoggingTests.swift`
```swift
class ServerManagerLoggingTests: XCTestCase {
    // Test log levels
    // Test log rotation
    // Test log filtering
    // Test log export
    // Test max log entries
}
```

#### TODO 2.2: Create ServerManagerNetworkingTests
**File**: `macos-app/AICLICompanionHostTests/ServerManagerNetworkingTests.swift`
```swift
class ServerManagerNetworkingTests: XCTestCase {
    // Test health check
    // Test connection monitoring
    // Test network status
    // Test API calls
    // Test timeout handling
}
```

#### TODO 2.3: Expand ProcessOutputHandlingTests
**File**: `macos-app/AICLICompanionHostTests/ProcessOutputHandlingTests.swift`
- Add Cloudflare tunnel URL variations
- Test partial output buffering
- Test error stream handling
- Test auth token extraction edge cases
- Test multiline output parsing

#### TODO 2.4: Expand ServerManagerProcessTests
**File**: `macos-app/AICLICompanionHostTests/ServerManagerProcessTests.swift`
- Test process crash recovery
- Test zombie process cleanup
- Test concurrent start/stop operations
- Test environment variable edge cases
- Test custom executable paths

### Phase 3: ViewModel Extraction (Days 4-5)

#### TODO 3.1: Extract ActivityMonitorViewModel
**File**: `macos-app/AICLICompanionHost/ViewModels/ActivityMonitorViewModel.swift`
```swift
@MainActor
class ActivityMonitorViewModel: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var serverHealth: ServerHealth = .unknown
    @Published var metrics: ServerMetrics
    
    func refreshData() async { }
    func exportLogs() -> URL? { }
    func clearSessions() { }
}
```

#### TODO 3.2: Extract SettingsViewModel
**File**: `macos-app/AICLICompanionHost/ViewModels/SettingsViewModel.swift`
```swift
@MainActor
class SettingsViewModel: ObservableObject {
    @Published var settings: AppSettings
    @Published var needsRestart: Bool = false
    
    func applySettings() async throws { }
    func resetToDefaults() { }
    func exportSettings() -> Data? { }
}
```

#### TODO 3.3: Extract SecuritySettingsViewModel
**File**: `macos-app/AICLICompanionHost/ViewModels/SecuritySettingsViewModel.swift`
```swift
@MainActor
class SecuritySettingsViewModel: ObservableObject {
    @Published var blockedCommands: [String] = []
    @Published var safeDirectories: [String] = []
    @Published var securityPreset: String = "standard"
    
    func applyPreset(_ preset: String) { }
    func validateCommand(_ command: String) -> Bool { }
    func addSafeDirectory(_ path: String) { }
}
```

#### TODO 3.4: Extract MenuBarViewModel
**File**: `macos-app/AICLICompanionHost/ViewModels/MenuBarViewModel.swift`
```swift
@MainActor
class MenuBarViewModel: ObservableObject {
    @Published var connectionString: String = ""
    @Published var serverStatus: ServerStatus
    @Published var quickActions: [QuickAction] = []
    
    func toggleServer() async { }
    func copyConnectionString() { }
    func openSettings() { }
}
```

### Phase 4: ViewModel Testing (Day 6) ✅

#### TODO 4.1: Create ActivityMonitorViewModelTests ✅
**File**: `macos-app/AICLICompanionHostTests/ViewModels/ActivityMonitorViewModelTests.swift`
- Test data refresh ✅
- Test session management ✅
- Test metrics calculation ✅
- Test log export ✅

#### TODO 4.2: Create SettingsViewModelTests ✅
**File**: `macos-app/AICLICompanionHostTests/ViewModels/SettingsViewModelTests.swift`
- Test settings application ✅
- Test restart detection ✅
- Test settings export/import ✅
- Test validation ✅

#### TODO 4.3: Create SecuritySettingsViewModelTests ✅
**File**: `macos-app/AICLICompanionHostTests/ViewModels/SecuritySettingsViewModelTests.swift`
- Test preset application ✅
- Test command validation ✅
- Test directory management ✅
- Test rule evaluation ✅

#### TODO 4.4: Create MenuBarViewModelTests ✅
**File**: `macos-app/AICLICompanionHostTests/ViewModels/MenuBarViewModelTests.swift`
- Test server toggle ✅
- Test status updates ✅
- Test quick actions ✅
- Test connection string generation ✅

### Phase 5: View Testing with ViewInspector (Day 7) ✅

#### TODO 5.1: Add ViewInspector Package ✅ (Skipped - used basic view testing)
**File**: `macos-app/Package.swift` (or via Xcode)
```swift
dependencies: [
    .package(url: "https://github.com/nalexn/ViewInspector", from: "0.9.0")
]
```

#### TODO 5.2: Create View Test Helpers
**File**: `macos-app/AICLICompanionHostTests/Helpers/ViewTestHelpers.swift`
```swift
import ViewInspector
extension Inspection: InspectionEmissary { }
// Custom inspection helpers
```

#### TODO 5.3: Create SettingsViewTests
**File**: `macos-app/AICLICompanionHostTests/Views/SettingsViewTests.swift`
- Test form rendering
- Test tab selection
- Test input validation
- Test save/cancel actions

#### TODO 5.4: Create SecuritySettingsViewTests
**File**: `macos-app/AICLICompanionHostTests/Views/SecuritySettingsViewTests.swift`
- Test preset picker
- Test command list
- Test directory picker
- Test toggle states

#### TODO 5.5: Create ActivityMonitorViewTests
**File**: `macos-app/AICLICompanionHostTests/Views/ActivityMonitorViewTests.swift`
- Test chart rendering
- Test session list
- Test refresh button
- Test export functionality

### Phase 6: CI/CD Re-enablement (Day 8)

#### TODO 6.1: Update CI Workflow
**File**: `.github/workflows/ci.yml`
```yaml
- name: Run macOS Tests with Coverage
  # Remove continue-on-error
  run: |
    cd macos-app
    xcodebuild test -project AICLICompanionHost.xcodeproj \
      -scheme AICLICompanionHost \
      -destination 'platform=macOS' \
      -enableCodeCoverage YES \
      CODE_SIGNING_ALLOWED=NO

- name: Check macOS Coverage Threshold
  run: |
    # Uncomment and update coverage check
    # Enforce 80% minimum coverage
```

#### TODO 6.2: Add Coverage Badge
**File**: `README.md`
- Add coverage badge from CI artifacts
- Link to coverage reports
- Document coverage goals

#### TODO 6.3: Setup Test Caching
- Cache DerivedData appropriately
- Cache test results
- Optimize test execution time

#### TODO 6.4: Fix Any Flaky Tests
- Add retries for network-dependent tests
- Mock time-sensitive operations
- Ensure test isolation

#### TODO 6.5: Create Test Documentation
**File**: `macos-app/TESTING.md`
- Document testing strategy
- Explain test organization
- Provide examples
- List coverage goals

## Testing Strategy

### Unit Test Principles
1. **Fast**: Mock all external dependencies
2. **Isolated**: No test interdependencies
3. **Repeatable**: Deterministic results
4. **Self-Validating**: Clear pass/fail
5. **Timely**: Write tests with code

### Coverage Goals by Component
- **Models**: 90% coverage (business logic)
- **ViewModels**: 85% coverage (UI logic)
- **Views**: 60% coverage (UI structure)
- **Utilities**: 95% coverage (helpers)
- **Overall**: 80% minimum

### Test Organization
```
AICLICompanionHostTests/
├── Models/           # Model tests
├── ViewModels/       # ViewModel tests
├── Views/           # View tests
├── Utilities/       # Utility tests
├── Helpers/         # Test helpers
├── Mocks/          # Mock objects
└── Fixtures/       # Test data
```

## Success Metrics

### Immediate (Phase 1)
- ✅ All tests passing (100% pass rate)
- ✅ No test failures in CI

### Short Term (Phases 2-3)
- 📈 50% code coverage
- ✅ All models have tests
- ✅ ViewModels extracted

### Medium Term (Phases 4-5)
- 📈 70% code coverage
- ✅ ViewModels fully tested
- ✅ Basic view tests in place

### Long Term (Phase 6)
- 📈 80%+ code coverage
- ✅ CI enforcement enabled
- ⏱️ Tests run in <2 minutes
- 📊 Coverage trends tracked

## Implementation Timeline

### Week 1
- **Day 1**: Fix failing tests, establish baseline
- **Day 2-3**: Model layer tests
- **Day 4-5**: Extract ViewModels

### Week 2
- **Day 6**: ViewModel tests
- **Day 7**: View tests with ViewInspector
- **Day 8**: CI/CD re-enablement

## Risk Mitigation

### Potential Risks
1. **ViewInspector limitations**: Some SwiftUI components may be hard to test
   - Mitigation: Focus on testable components, use snapshot testing for complex views

2. **Test execution time**: More tests may slow CI
   - Mitigation: Parallelize tests, use test sharding

3. **Flaky tests**: Async operations may be unreliable
   - Mitigation: Proper mocking, increase timeouts

4. **Coverage plateau**: Hard to achieve last 10-20%
   - Mitigation: Focus on critical paths, accept some UI gaps

## AI Assistant Instructions

When implementing this plan:
1. Start with Phase 1 - fix the 2 failing tests immediately
2. Create ViewModels before their tests for better structure
3. Use dependency injection for testability
4. Mock FileManager, Process, and Network operations
5. Keep tests fast - target <100ms per test
6. Document any test that takes >500ms
7. Use XCTestExpectation for async tests
8. Group related tests with MARK comments

## Next Steps

1. Fix the 2 failing ServerDiscoveryTests
2. Run coverage report to confirm baseline
3. Create ServerManagerLoggingTests
4. Begin ViewModel extraction
5. Update this plan with progress markers

**Current Status**: Phase 5 - Ready for View Testing with ViewInspector
**Next TODO**: 5.1 - Add ViewInspector Package
**Coverage**: 17.6% → ~40% (estimated) → Target 80%
**Last Updated**: 2025-08-12
**Progress**: Phases 1-4 Complete ✅ | 4 ViewModels created | 8 new test files added