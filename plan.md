# AICLI Companion Beta Readiness Plan

## Executive Summary
Prepare AICLI Companion for beta release by addressing critical bugs, ensuring core functionality reliability, and establishing minimum viable quality standards. This plan focuses on stability, user experience polish, and essential features only - no new functionality unless blocking beta.

## Current State Analysis

### What We Have Now
- Functional iOS app with chat interface and local message storage
- Working macOS companion app for server management
- Node.js server routing messages between iOS and Claude Code CLI
- Basic project management and session handling
- APNS-based response delivery
- Local-first architecture implemented

### What Needs Fixing for Beta
- Critical stability issues and crash scenarios
- Core user journey blockers
- Essential error handling and recovery
- Minimum viable documentation
- Basic quality assurance testing

## Implementation Plan

### Phase 0: Enable Folder Creation from iOS ✅
Allow users to create new folders in their project path directly from the iOS app.

#### TODO 0.1: Implement Create Folder Feature in iOS ✅
**Requirement**: Users should be able to create new folders within their project directory from iOS.
**Implementation**: Add UI and server endpoint to create directories in the project path.

**Completed Tasks**:
- ✅ Added "New Folder" button to each project row in ProjectSelectionView
- ✅ Created server endpoint `/api/projects/:name/folders` with proper validation
- ✅ Implemented path validation and security checks (directory traversal protection)
- ✅ Added FolderCreationSheet UI for entering folder name
- ✅ Added error handling for permission issues and invalid paths
- ✅ Integrated with AICLIService for API calls
- ✅ Successfully built iOS app with new feature

Files modified:
- `ios/Sources/AICLICompanion/ProjectSelectionView.swift` (added UI and sheet)
- `server/src/routes/projects.js` (added folder creation endpoint)
- `ios/Sources/AICLICompanion/Services/AICLI/ProjectManager.swift` (added API call)
- `ios/Sources/AICLICompanion/AICLIService.swift` (exposed createFolder method)
- `ios/Sources/AICLICompanion/Models/ServerModels.swift` (added error cases)

### Phase 1: Critical Bug Fixes (Day 1)
Focus on showstopper bugs that prevent basic usage.

#### TODO 1.1: Fix Session Timeout Handling
Ensure graceful handling when Claude sessions timeout or expire.
- Implement session expiry detection
- Add user-friendly error messages
- Provide clear recovery path (start new session)
- Test with expired sessions

#### TODO 1.2: Fix APNS Delivery Failures
Handle cases where push notifications fail to deliver Claude responses.
- Add fallback polling mechanism for active sessions
- Implement retry logic for failed APNS
- Show clear error states in UI
- Test with disabled notifications

### Phase 2: Core Stability (Day 1-2)
Ensure the app doesn't crash and handles errors gracefully.

#### TODO 2.1: Crash Protection for Network Errors
Add comprehensive error handling for network failures.
- Wrap all network calls in proper error handling
- Show user-friendly error messages
- Implement automatic retry with backoff
- Test with no network, slow network, intermittent network

#### TODO 2.2: Memory Management Audit
Prevent memory leaks and excessive memory usage.
- Profile iOS app for memory leaks
- Fix any retain cycles in ViewModels
- Limit message history in memory (keep recent, load rest on demand)
- Test with long conversation sessions

#### TODO 2.3: Server Process Stability
Ensure server doesn't crash and recovers gracefully.
- Add process monitoring and auto-restart
- Implement health check endpoint
- Handle Claude Code CLI crashes gracefully
- Add proper cleanup on shutdown

### Phase 3: Essential UX Polish (Day 2)
Fix the most jarring user experience issues.

#### TODO 3.1: Fix Chat Scroll UX Issues
**Critical UX Bug**: Chat scrolling behavior is problematic and disrupts user experience.
- Chat doesn't auto-scroll to bottom when new messages arrive
- Scroll position jumps unexpectedly during Claude's streaming responses
- User loses their reading position when responses are updating
- Keyboard appearance doesn't adjust scroll properly
- Fix auto-scroll to latest message on send/receive
- Maintain user scroll position when they're reading history
- Smooth scroll animations during streaming responses
- Ensure keyboard doesn't obscure latest messages
- Test with long conversations and streaming responses

Files to investigate:
- `ios/Sources/AICLICompanion/Views/Chat/ChatView.swift`
- `ios/Sources/AICLICompanion/Views/Chat/Components/MessageList.swift`
- `ios/Sources/AICLICompanion/ViewModels/ChatViewModel.swift`

#### TODO 3.2: Message Send Reliability
Ensure messages are never lost and users know what's happening.
- Add sending/sent/failed states for messages
- Implement retry for failed sends
- Clear visual feedback for message status
- Prevent duplicate sends

#### TODO 3.3: Loading States and Feedback
Users should never wonder if the app is frozen.
- Add loading indicators for all async operations
- Show progress for long-running tasks
- Implement skeleton screens for initial loads
- Add pull-to-refresh where appropriate

#### TODO 3.4: Error Recovery Flows
Users should always have a clear next action when something fails.
- Design standard error screens with recovery actions
- Add "Try Again" buttons for recoverable errors
- Provide helpful error messages (not technical jargon)
- Include support/feedback option in error states

### Phase 4: Quality Assurance (Day 2-3)
Basic testing to ensure beta readiness.

#### TODO 4.1: Manual Test Checklist
Create and execute manual test plan for core flows.
- [ ] New user onboarding flow
- [ ] Send first message to Claude
- [ ] Switch between projects
- [ ] Receive long Claude response
- [ ] Handle network disconnection
- [ ] Resume conversation after app restart
- [ ] Start/stop server from macOS app
- [ ] Handle Claude Code CLI not installed

#### TODO 4.2: Automated Test Coverage
Ensure critical paths have test coverage.
- Run existing test suites, fix any failures
- Add tests for critical bug fixes
- Verify >80% coverage for critical paths
- Set up CI to run tests on every commit

#### TODO 4.3: Linting and Code Quality
Clean up code to minimum quality standards.
- Run ESLint on server, fix all errors
- Run SwiftLint on iOS/macOS, fix all errors
- Remove commented-out code
- Ensure consistent code style

### Phase 5: Beta Prerequisites (Day 3)
Essential items before beta users touch the app.

#### TODO 5.1: Minimum Viable Documentation
Users need to know how to get started.
- Update README with clear setup instructions
- Add troubleshooting guide for common issues
- Document system requirements clearly
- Create simple quick start guide

#### TODO 5.2: Feedback Mechanism
Beta users need a way to report issues.
- Add feedback button in app settings
- Link to GitHub issues or feedback form
- Include diagnostic info in feedback (with permission)
- Add version number in settings

#### TODO 5.3: Analytics and Crash Reporting
Need visibility into beta usage and issues.
- Implement basic crash reporting (Crashlytics or similar)
- Add anonymous usage analytics for core flows
- Track error rates and types
- Respect user privacy, make it opt-in

#### TODO 5.4: Beta Distribution Setup
Prepare TestFlight or distribution method.
- Set up TestFlight for iOS app
- Create beta testing group
- Prepare beta release notes
- Set up feedback collection process

## Testing Plan

### Smoke Tests (Run after each phase)
1. Can start server from macOS app
2. Can send message from iOS app
3. Can receive Claude response
4. App doesn't crash on basic usage
5. Can switch between projects

### Beta Acceptance Criteria
- [ ] No crashes in core user flows
- [ ] All critical bugs fixed (Phase 1)
- [ ] Error states have recovery paths
- [ ] Basic documentation complete
- [ ] Feedback mechanism in place
- [ ] TestFlight build submitted

## Success Metrics

### Must Have for Beta
- Zero crashes in main user flow
- <5 second response time for UI actions
- 100% message delivery success (with retries)
- Clear error messages for all failure modes
- Working feedback mechanism

### Nice to Have (Post-Beta)
- Performance optimizations
- Advanced features
- UI animations and polish
- Extended documentation
- Comprehensive test coverage

## AI Assistant Instructions

**IMPORTANT**: This is a beta readiness plan. Focus ONLY on fixing critical issues and ensuring basic stability. Do NOT add new features or nice-to-haves.

When working on this plan:
1. Start with Phase 1 - these are blocking issues
2. Test each fix thoroughly before moving on
3. If you discover new critical bugs, add them to Phase 1
4. Mark TODOs with ✅ as you complete them
5. Update the "Current Status" section after each work session
6. If blocked on any item, note it and move to next item
7. Run tests after each phase to ensure no regressions

Priority order:
1. Crashes and data loss bugs
2. Features that don't work at all
3. Confusing error states
4. Performance issues that make app unusable
5. Everything else can wait for post-beta

Remember: The goal is a stable beta, not a perfect app. Fix only what prevents users from having a basically functional experience.

---

**Current Status**: Phase 0 Complete - Folder creation from iOS implemented ✅  
**Next Step**: Phase 1 - TODO 1.1 - Fix Session Timeout Handling  
**Last Updated**: 2025-08-19  
**Target Beta Date**: 3 days from plan start