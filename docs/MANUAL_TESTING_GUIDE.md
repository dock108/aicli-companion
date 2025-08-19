# Manual Testing Guide for AICLI Companion

## Overview
This comprehensive manual testing guide covers both macOS server (30%) and iOS app (70%) functionality. Each test can be checked off during testing sessions to ensure thorough coverage.

**Total Tests**: 50 scenarios  
**macOS/Server**: 15 tests (30%)  
**iOS App**: 35 tests (70%)

---

## Part A: macOS Server Testing (15 Tests)

### A1. Server Initialization & Startup
- [ ] **A1.1** Server starts successfully with `npm start`
- [ ] **A1.2** Server displays correct port and local IP address
- [ ] **A1.3** Server creates required directories (`sessions/`, `logs/`)
- [ ] **A1.4** Health check endpoint responds at `http://localhost:3001/health`
- [ ] **A1.5** Server handles AUTH_REQUIRED=true mode correctly

### A2. Claude Code CLI Integration
- [ ] **A2.1** Server detects Claude Code CLI installation
- [ ] **A2.2** Server executes Claude commands without errors
- [ ] **A2.3** Server properly streams Claude responses
- [ ] **A2.4** Server handles Claude session IDs correctly
- [ ] **A2.5** Server manages concurrent Claude sessions

### A3. WebSocket & Network
- [ ] **A3.1** WebSocket accepts connections with valid auth token
- [ ] **A3.2** WebSocket rejects connections with invalid token
- [ ] **A3.3** Server handles network disconnections gracefully
- [ ] **A3.4** Server auto-discovery broadcasts work on local network
- [ ] **A3.5** Server properly cleans up closed connections

---

## Part B: iOS App Testing (35 Tests)

### B1. Initial Setup & Connection (5 Tests)
- [ ] **B1.1** App launches without crashes on first run
- [ ] **B1.2** Settings screen accessible from main menu
- [ ] **B1.3** Manual server entry works (IP:Port format)
- [ ] **B1.4** Auto-discovery finds local servers within 5 seconds
- [ ] **B1.5** Connection test button provides clear success/failure feedback

### B2. Authentication & Security (3 Tests)
- [ ] **B2.1** Auth token field accepts and saves token
- [ ] **B2.2** App connects successfully with correct token
- [ ] **B2.3** App shows clear error with incorrect token

### B3. Project Selection & Navigation (5 Tests)
- [ ] **B3.1** Project list loads and displays available directories
- [ ] **B3.2** Project icons display correctly (folder/git indicators)
- [ ] **B3.3** Project selection navigates to chat view
- [ ] **B3.4** Back navigation returns to project list
- [ ] **B3.5** Project context persists across app restarts

### B4. Chat Interface & Messaging (7 Tests)
- [ ] **B4.1** Message input field accepts text
- [ ] **B4.2** Send button becomes active with text present
- [ ] **B4.3** Messages appear immediately in chat view when sent
- [ ] **B4.4** User messages show on right with blue background
- [ ] **B4.5** Claude responses show on left with gray background
- [ ] **B4.6** Timestamps display correctly for all messages
- [ ] **B4.7** Chat scrolls to newest message automatically

### B5. Claude Interaction Features (5 Tests)
- [ ] **B5.1** "Thinking" indicator appears while Claude processes
- [ ] **B5.2** Tool usage indicators show (Read, Write, Bash, etc.)
- [ ] **B5.3** Code blocks render with syntax highlighting
- [ ] **B5.4** Markdown formatting renders correctly
- [ ] **B5.5** Long responses stream in progressively

### B6. Session & Persistence (5 Tests)
- [ ] **B6.1** Messages persist when switching projects
- [ ] **B6.2** Messages reload when returning to same project
- [ ] **B6.3** Session continues after app backgrounding
- [ ] **B6.4** Clear chat creates new session successfully
- [ ] **B6.5** Message history survives app restart

### B7. Status Indicators & Feedback (3 Tests)
- [ ] **B7.1** Connection status indicator shows correct state
- [ ] **B7.2** Project "waiting" status displays during operations
- [ ] **B7.3** Error messages appear clearly when operations fail

### B8. Performance & Responsiveness (2 Tests)
- [ ] **B8.1** UI remains responsive during long Claude responses
- [ ] **B8.2** Scrolling stays smooth with 100+ messages

---

## Part C: Integration Testing (Bonus Scenarios)

### C1. End-to-End Workflows
- [ ] **C1.1** Complete workflow: Connect → Select Project → Send Message → Receive Response
- [ ] **C1.2** Multi-turn conversation maintains context correctly
- [ ] **C1.3** File operations (Read/Write) complete successfully
- [ ] **C1.4** Terminal commands (Bash) execute and display output
- [ ] **C1.5** Background app → Return → Messages intact

### C2. Error Recovery
- [ ] **C2.1** App recovers from server restart
- [ ] **C2.2** App handles network interruption gracefully
- [ ] **C2.3** App shows appropriate errors for server timeout
- [ ] **C2.4** Reconnection works after connection loss
- [ ] **C2.5** Messages queue while offline and send when reconnected

---

## Testing Execution Guide

### Environment Setup
1. **macOS Machine**: Running server with `npm start`
2. **iOS Device**: iPhone/iPad with app installed
3. **Network**: Both devices on same WiFi network
4. **Claude Code CLI**: Installed and authenticated on macOS

### Test Execution Order
1. Start with Part A (Server tests)
2. Move to Part B (iOS tests)
3. Finish with Part C (Integration tests)

### For Each Test
1. Check the box when test passes ✅
2. Note issue details if test fails ❌
3. Mark as blocked if can't test 🚫

### Issue Recording Template
```
Test ID: [e.g., B7.1]
Status: FAIL
Description: [What went wrong]
Steps to Reproduce: [How to trigger]
Expected: [What should happen]
Actual: [What actually happened]
Screenshots: [If applicable]
```

### Severity Levels
- **Critical**: App crashes or data loss
- **High**: Feature completely broken
- **Medium**: Feature partially working
- **Low**: Cosmetic or minor issue

---

## Quick Smoke Test (10 Essential Tests)

For rapid testing, prioritize these core scenarios:

1. [ ] **A1.1** Server starts successfully
2. [ ] **B1.1** App launches without crashes
3. [ ] **B1.5** Connection test succeeds
4. [ ] **B3.1** Project list loads
5. [ ] **B4.3** Messages send successfully
6. [ ] **B4.5** Claude responses appear
7. [ ] **B5.1** Thinking indicator works
8. [ ] **B6.1** Messages persist
9. [ ] **B7.1** Connection status accurate
10. [ ] **C1.1** Complete end-to-end flow works

---

## Testing Notes Section

### Known Issues to Watch For
- Status indicators for waiting projects
- Session ID handling during rapid project switching
- Message duplication on reconnection
- Tool indicator persistence

### Performance Benchmarks
- Server startup: < 3 seconds
- Connection establishment: < 2 seconds
- Message send latency: < 500ms
- Claude response start: < 5 seconds
- UI animation: 60 fps

### Device Compatibility Matrix
| iOS Version | iPhone | iPad | Status |
|------------|--------|------|--------|
| 15.0       | ✅     | ✅   | Supported |
| 16.0       | ✅     | ✅   | Supported |
| 17.0       | ✅     | ✅   | Supported |
| 18.0       | ✅     | ✅   | Supported |

---

## Sign-off Section

**Tester Name**: _____________________  
**Date**: _____________________  
**Version Tested**: _____________________  
**Device(s) Used**: _____________________  

**Overall Result**:
- [ ] All tests passed - Ready for release
- [ ] Minor issues found - Can release with known issues
- [ ] Major issues found - Needs fixes before release
- [ ] Blocked - Cannot complete testing

**Comments**:
```
[Additional notes, observations, or recommendations]
```

---

**Document Version**: 1.0.0  
**Last Updated**: 2025-08-19  
**Next Review**: After next major feature addition