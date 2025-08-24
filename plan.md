# iOS Test Coverage Improvement Plan

## Current State (August 23, 2025)
- **Line Coverage**: 2.82% (603/21,379 lines)
- **File Coverage**: 11.1% (11/99 files)
- **Total Tests**: 249 passing tests
- **Test Files**: 14 files with 4,261 lines
- **Target Coverage**: 70% (14,965 lines)
- **Gap to Target**: 14,362 lines need testing

## Files Currently Tested
### Models (8 files, 154 tests)
- ✅ Message.swift (MessageCoreTests, 26 tests)
- ✅ Project.swift (ProjectStatusTests, 15 tests)
- ✅ ServerConnection.swift (ServerModelsTests, 30 tests)
- ✅ RichContent.swift (RichContentTests, 24 tests)
- ✅ SecuritySettings.swift (SecuritySettingsTests, 35 tests)
- ✅ WebSocketMessage.swift (WebSocketModelsTests, 24 tests)

### Services (3 files, 95 tests)
- ✅ KeychainManager.swift (KeychainManagerTests, 26 tests)
- ✅ PerformanceLogger.swift (PerformanceLoggerTests, 20 tests)
- ✅ MessageValidator.swift (MessageValidatorTests, 50 tests)

## Testing Roadmap

### Phase 1: Critical Core Services (Target: 21.4% coverage)
**Timeline**: Week 1-2
**Files**: 10 services, ~3,959 lines
**Priority**: CRITICAL - These are the foundation of the app

1. **PushNotificationService.swift** (772 lines, +3.6%)
   - Test push notification registration
   - Test message delivery
   - Test error handling
   - Mock APNS interactions

2. **AICLIService/MessageOperations.swift** (460 lines, +2.2%)
   - Test message sending/receiving
   - Test session management
   - Test error recovery
   - Mock Claude CLI interactions

3. **WebSocketManager.swift** (~400 lines, +1.9%)
   - Test connection lifecycle
   - Test reconnection logic
   - Test message routing
   - Mock WebSocket events

4. **SecurityManager.swift** (367 lines, +1.7%)
   - Test authentication
   - Test authorization
   - Test secure storage
   - Test permission handling

5. **ConnectionReliabilityManager.swift** (365 lines, +1.7%)
   - Test connection monitoring
   - Test retry logic
   - Test fallback mechanisms

6. **ServiceDiscoveryManager.swift** (402 lines, +1.9%)
   - Test service discovery
   - Test server selection
   - Test network scanning

7. **PerformanceMonitor.swift** (384 lines, +1.8%)
   - Test metric collection
   - Test performance tracking
   - Test memory monitoring

8. **ConversationExporter.swift** (328 lines, +1.5%)
   - Test export formats
   - Test data serialization
   - Test file operations

9. **MessagePersistenceService.swift** (~250 lines, +1.2%)
   - Test message storage
   - Test retrieval logic
   - Test data migration

10. **ConversationPersistenceService.swift** (~231 lines, +1.1%)
    - Test conversation storage
    - Test session recovery
    - Test data integrity

### Phase 2: View Models & Business Logic (Target: 32.2% coverage)
**Timeline**: Week 2-3
**Files**: 6 view models, ~2,300 lines
**Priority**: HIGH - Business logic is easier to test than UI

1. **ChatViewModel.swift** (~500 lines, +2.3%)
   - Test message flow
   - Test state management
   - Test user interactions

2. **AutoResponseManager.swift** (398 lines, +1.9%)
   - Test auto-response logic
   - Test permission handling
   - Test response generation

3. **ProjectStatusManager.swift** (~300 lines, +1.4%)
   - Test status tracking
   - Test project lifecycle
   - Test status updates

4. **ConnectionViewModel.swift** (~300 lines, +1.4%)
   - Test connection state
   - Test server management
   - Test error handling

5. **SettingsViewModel.swift** (~342 lines, +1.6%)
   - Test settings persistence
   - Test preference updates
   - Test validation logic

### Phase 3: UI Components & Rendering (Target: 47.5% coverage)
**Timeline**: Week 3-4
**Files**: 10 components, ~3,275 lines
**Priority**: MEDIUM - Can use snapshot testing for efficiency

1. **MarkdownParser.swift** (349 lines, +1.6%)
2. **RichContentRenderer.swift** (~305 lines, +1.4%)
3. **ClaudeOutputParser.swift** (~298 lines, +1.4%)
4. **AttachmentPicker.swift** (432 lines, +2.0%)
5. **AttachmentPreview.swift** (329 lines, +1.5%)
6. **MessageBubble.swift** (~262 lines, +1.2%)
7. **ToolActivity.swift** (424 lines, +2.0%)
8. **ClaudeStatusIndicator.swift** (326 lines, +1.5%)
9. **ConnectionQualityIndicator.swift** (345 lines, +1.6%)
10. **NavigationStateManager.swift** (~205 lines, +1.0%)

### Phase 4: Main Views (Target: 58.8% coverage)
**Timeline**: Week 4-5
**Files**: 4 main views, ~2,404 lines
**Priority**: MEDIUM - Use ViewInspector or snapshot testing

1. **ConnectionView.swift** (648 lines, +3.0%)
2. **SettingsView.swift** (638 lines, +3.0%)
3. **ProjectSelectionView.swift** (567 lines, +2.7%)
4. **ChatView.swift** (551 lines, +2.6%)

### Phase 5: Remaining High-Value Files (Target: 70.0% coverage)
**Timeline**: Week 5-6
**Files**: 9 files, ~2,400 lines
**Priority**: LOW-MEDIUM - Fill gaps to reach 70%

1. **SecuritySettingsView.swift** (447 lines, +2.1%)
2. **PerformanceDashboard.swift** (388 lines, +1.8%)
3. **VimModeView.swift** (~294 lines, +1.4%)
4. **ProjectContextView.swift** (~277 lines, +1.3%)
5. **MessageStreamManager.swift** (~250 lines, +1.2%)
6. **DependencyContainer.swift** (~220 lines, +1.0%)
7. **Settings.swift** (~216 lines, +1.0%)
8. **AnimationConstants.swift** (~158 lines, +0.7%)
9. **ClipboardManager.swift** (~150 lines, +0.7%)

## Testing Strategy

### Approach by File Type
1. **Services**: Mock external dependencies, test business logic
2. **View Models**: Test state management and data flow
3. **Views**: Snapshot testing or ViewInspector for UI verification
4. **Utilities**: Direct unit tests with edge cases
5. **Models**: Already completed ✅

### Test Types to Implement
- Unit tests for all business logic
- Integration tests for service interactions
- Snapshot tests for UI components
- Performance tests for critical paths
- Mock implementations for external dependencies

### Tools & Frameworks
- XCTest (primary framework)
- Consider ViewInspector for SwiftUI testing (after Xcode upgrade)
- Manual mocking (no external dependencies)
- XCTestExpectation for async testing

## Success Metrics
- ✅ All tests passing in CI/CD
- ✅ 70% line coverage achieved
- ✅ Critical paths have >90% coverage
- ✅ No flaky tests
- ✅ Test execution time <2 minutes

## Risk Mitigation
- **CI Environment Issues**: Already fixed KeychainManager CI skipping
- **Async Testing**: Use proper expectations and timeouts
- **SwiftUI Testing**: May need Xcode 16 for ViewInspector
- **Test Maintenance**: Keep tests simple and focused

## Next Immediate Steps
1. Start with PushNotificationService.swift (largest file)
2. Create mock for APNS interactions
3. Write comprehensive test suite
4. Move to AICLIService next
5. Continue down priority list

## Notes
- Current tests achieve 80-100% coverage on tested files
- Focus on high-use paths and critical functionality
- Avoid testing SwiftUI layout details
- Prioritize testable business logic over UI