# macOS App Testing Analysis & Improvement Plan

## Current Status

### Test Results
- **Total Tests**: 202
- **Passing**: 182 
- **Failing**: 20
- **Test Success Rate**: 90.1%

### Code Coverage
- **Overall Coverage**: 38.7%
- **App Target Coverage**: 17.6% (1671/9476 lines)
- **Test Target Coverage**: 82.0%

## Failing Tests Analysis

### 1. AICLICompanionHostTests (1 failure)
- `testServerManagerInitialization`: Expected port 3001 but got 8080
  - **Root Cause**: Default port changed in settings
  - **Fix**: Update test expectation to 3001

### 2. ProcessOutputHandlingTests (11 failures)
- `testDetectCloudflareURLVariations`: Pattern matching issues
- `testParseCloudflaredURL`: URL parsing logic changed
- `testParseErrorMessages`: Error format detection failing
- `testParseWarningMessages`: Warning format not recognized
- `testProcessTerminationHandling`: NSTask not launched exception

### 3. ServerManagerProcessTests (7 failures)
- `testFindServerDirectoryWithCustomPath`: Path resolution issue
- `testSetupServerEnvironmentBasic`: Port mismatch (3001 vs 8080)
- `testStartServerProcessSetsIsProcessing`: Process not starting
- `testStartServerWhenAlreadyRunning`: Error handling issue
- `testStopServerCleansUpState`: Process cleanup incomplete

## Coverage Gaps Analysis

### Critical Areas with 0% Coverage

1. **All View Files** (0% coverage)
   - LogsView.swift
   - SettingsView.swift
   - SecuritySettingsView.swift
   - ActivityMonitorView.swift
   - MenuBarView.swift
   - TunnelSettingsView.swift
   - NgrokSetupView.swift
   - QRCodeView.swift

2. **View Components** (0% coverage)
   - ActivityMonitorCards.swift
   - ActivityMonitorCharts.swift
   - ActivityMonitorComponents.swift
   - MenuBarComponents.swift
   - SettingsComponents.swift

3. **Model Files with Low/No Coverage**
   - ServerManager.swift (partial)
   - ServerManagerLogging.swift
   - ServerManagerNetworking.swift
   - SettingsManager.swift (partial)

## Action Plan

### Phase 1: Fix Failing Tests (Priority: HIGH)

#### 1.1 Port Configuration Issues
- Update all tests expecting port 8080 to use 3001
- Ensure consistent port configuration across tests
- Add parameterized testing for different port scenarios

#### 1.2 Process Output Handling
- Fix Cloudflare URL detection patterns
- Update error message parsing to match current formats
- Handle NSTask exceptions properly
- Add timeout handling for process operations

#### 1.3 Server Manager Process Tests
- Fix path resolution for custom server directories
- Ensure proper process lifecycle management
- Add proper cleanup in tearDown methods
- Mock file system operations where needed

### Phase 2: Increase Code Coverage (Priority: HIGH)

#### 2.1 View Testing Strategy
Since SwiftUI views are hard to unit test directly, we need:
- **ViewInspector Integration**: Add ViewInspector library for SwiftUI testing
- **Snapshot Testing**: Use SnapshotTesting for UI verification
- **ViewModel Testing**: Extract business logic to testable ViewModels

#### 2.2 Create Missing Test Files
```
- SecuritySettingsViewTests.swift
- ActivityMonitorViewTests.swift
- MenuBarViewTests.swift
- TunnelSettingsViewTests.swift
- ServerManagerLoggingTests.swift
- ServerManagerNetworkingTests.swift
```

#### 2.3 Test Coverage Targets
- **Immediate Goal**: 50% coverage (fix tests + add critical model tests)
- **Short Term Goal**: 70% coverage (add ViewModel tests)
- **Long Term Goal**: 80%+ coverage (complete UI testing)

### Phase 3: Testing Infrastructure Improvements

#### 3.1 Mock Infrastructure
- Create comprehensive mocks for:
  - FileManager operations
  - Process/NSTask operations
  - Network operations
  - UserDefaults
  - Keychain

#### 3.2 Test Helpers
- Create test fixtures for common scenarios
- Add assertion helpers for async operations
- Implement test data builders

#### 3.3 CI/CD Improvements
- Enable test parallelization
- Add test result reporting
- Implement coverage tracking over time
- Add test flakiness detection

## Implementation Priority

### Week 1 (Immediate)
1. Fix all 20 failing tests
2. Update port configurations
3. Fix process handling issues

### Week 2 (Short Term)
1. Extract ViewModels from Views
2. Create ViewModel tests
3. Add ServerManager comprehensive tests
4. Target: 50% coverage

### Week 3-4 (Medium Term)
1. Add ViewInspector for UI testing
2. Create View tests
3. Add integration tests
4. Target: 70% coverage

### Month 2 (Long Term)
1. Add snapshot testing
2. Complete test coverage for all components
3. Add performance tests
4. Target: 80%+ coverage

## Testing Best Practices to Implement

1. **Test Naming**: Use descriptive names following `test_<scenario>_<expectedResult>`
2. **Arrange-Act-Assert**: Structure all tests consistently
3. **Single Responsibility**: Each test should verify one behavior
4. **Fast Tests**: Mock external dependencies
5. **Deterministic**: No random values or timing dependencies
6. **Independent**: Tests should not depend on execution order
7. **Documentation**: Add comments for complex test scenarios

## Metrics to Track

- Test execution time
- Coverage percentage per module
- Test flakiness rate
- Time to fix failing tests
- Coverage trend over time

## Next Steps

1. Create GitHub issues for each failing test category
2. Set up coverage reporting in CI
3. Add pre-commit hooks for test execution
4. Schedule weekly test review meetings
5. Document testing guidelines in CONTRIBUTING.md