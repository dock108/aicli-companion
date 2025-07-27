# User Acceptance Testing (UAT) Scenarios

## Overview

This document outlines the UAT test scenarios for the Claude Code Mobile Companion App. Each scenario represents a real-world use case that should be tested manually on actual devices.

## Test Environment

- **iOS Devices**: iPhone 12 or newer, iPad Air or newer
- **iOS Versions**: iOS 15.0+
- **Server**: Running on local machine accessible via network
- **Network**: Both WiFi and Cellular connections

## UAT Test Scenarios

### Scenario 1: First-Time Setup and Connection

**Objective**: Verify new user can successfully set up and connect to companion server

**Prerequisites**:

- Fresh app installation
- Server running on local machine

**Steps**:

1. Launch the app for the first time
2. Navigate to connection settings
3. Enable auto-discovery
4. Select discovered server from list
5. Enter authentication token
6. Test connection
7. Save connection profile

**Expected Results**:

- Server appears in discovery list within 5 seconds
- Connection test succeeds
- Profile is saved and persists after app restart

**Pass Criteria**: ✅ All steps complete without errors

---

### Scenario 2: Basic Chat Interaction

**Objective**: Verify basic Claude Code interaction works correctly

**Prerequisites**:

- Connected to server
- Valid working directory set

**Steps**:

1. Open chat interface
2. Type "What files are in the current directory?"
3. Send message
4. Wait for Claude response
5. Verify file listing is displayed correctly
6. Ask follow-up question about specific file
7. Verify response maintains context

**Expected Results**:

- Messages send immediately
- Claude responses appear with proper formatting
- File listings show with syntax highlighting
- Context is maintained between messages

**Pass Criteria**: ✅ All interactions complete successfully

---

### Scenario 3: Tool Usage Visualization

**Objective**: Verify tool activity indicators work correctly

**Prerequisites**:

- Connected to server
- In a project directory

**Steps**:

1. Ask Claude to "Read the README.md file"
2. Observe tool activity indicator
3. Ask Claude to "Search for TODO comments in all JavaScript files"
4. Observe multiple tool activities
5. Ask Claude to "Run npm test"
6. Observe command execution indicator

**Expected Results**:

- Tool indicators appear immediately when tools start
- Tool names and parameters are visible
- Progress indicators animate smoothly
- Indicators disappear when tools complete

**Pass Criteria**: ✅ All tool activities display correctly

---

### Scenario 4: File Management Integration

**Objective**: Verify file browser integration works

**Prerequisites**:

- Connected to server
- In a project directory

**Steps**:

1. Tap file browser button in chat
2. Navigate through directory structure
3. Select a code file
4. Choose "Analyze this file"
5. Return to chat and see analysis
6. Select multiple files
7. Ask Claude to compare them

**Expected Results**:

- File browser opens smoothly
- Directory navigation is responsive
- File selection works correctly
- Selected files appear in chat context
- Claude analyzes selected files

**Pass Criteria**: ✅ File management features work as expected

---

### Scenario 5: Offline Queue Management

**Objective**: Verify offline functionality works correctly

**Prerequisites**:

- Connected to server initially
- Some chat history exists

**Steps**:

1. Disable network connection
2. Type new message
3. Attempt to send (should queue)
4. Type 2 more messages and queue them
5. Re-enable network
6. Observe queue processing
7. Verify all messages sent in order

**Expected Results**:

- Offline indicator appears immediately
- Messages queue with visual indication
- Queue badge shows count
- Messages send automatically on reconnection
- Order is preserved

**Pass Criteria**: ✅ Offline queue works correctly

---

### Scenario 6: Development Workflow Support

**Objective**: Verify project-aware features work

**Prerequisites**:

- Connected to server
- In a Git repository with uncommitted changes

**Steps**:

1. Open workflow panel
2. View Git status card
3. Tap "View changes"
4. Ask Claude about the changes
5. Check build system detection
6. Run suggested build command
7. View test results if available

**Expected Results**:

- Git status shows correctly
- Changes are formatted properly
- Build system is detected accurately
- Commands execute from UI
- Results display in chat

**Pass Criteria**: ✅ Workflow features integrate smoothly

---

### Scenario 7: Conversation Management

**Objective**: Verify conversation features work correctly

**Prerequisites**:

- Multiple conversations exist
- Some with significant history

**Steps**:

1. Open conversation history
2. Search for specific keyword
3. Filter by date range
4. Mark conversation as favorite
5. Export conversation as JSON
6. Share exported file
7. Delete old conversation
8. Verify it's removed

**Expected Results**:

- Search returns relevant results
- Filters work correctly
- Favorites appear at top
- Export creates valid JSON
- Share sheet appears
- Deletion is immediate

**Pass Criteria**: ✅ All management features work

---

### Scenario 8: Performance Under Load

**Objective**: Verify app performs well with large conversations

**Prerequisites**:

- Long conversation (100+ messages)
- Multiple code blocks and tool outputs

**Steps**:

1. Open long conversation
2. Scroll to bottom quickly
3. Scroll up through history
4. Tap on code blocks to expand
5. Copy large code output
6. Search within conversation
7. Monitor app responsiveness

**Expected Results**:

- Scrolling remains smooth (60 fps)
- No noticeable lag
- Memory usage stays reasonable
- Code blocks render quickly
- Search completes fast
- No crashes or freezes

**Pass Criteria**: ✅ Performance remains acceptable

---

### Scenario 9: Accessibility Testing

**Objective**: Verify app is fully accessible

**Prerequisites**:

- VoiceOver enabled
- Reduce Motion enabled
- Large text size set

**Steps**:

1. Navigate entire app with VoiceOver
2. Send and receive messages
3. Use all major features
4. Verify announcements work
5. Test with keyboard (iPad)
6. Verify color contrast
7. Test haptic feedback

**Expected Results**:

- All elements have proper labels
- Navigation is logical
- Announcements are clear
- Keyboard navigation works
- Colors meet WCAG standards
- Haptics provide feedback

**Pass Criteria**: ✅ App is fully accessible

---

### Scenario 10: Error Handling and Recovery

**Objective**: Verify app handles errors gracefully

**Prerequisites**:

- Various network conditions
- Server can be stopped/started

**Steps**:

1. Stop server while connected
2. Verify error message appears
3. Try to send message (should fail gracefully)
4. Restart server
5. Verify auto-reconnection
6. Test with invalid token
7. Test with network timeout

**Expected Results**:

- Clear error messages appear
- No crashes or data loss
- Reconnection is automatic
- Invalid token shows proper error
- Timeouts are handled gracefully
- User can always recover

**Pass Criteria**: ✅ All errors handled properly

---

## UAT Sign-off Checklist

- [ ] All scenarios tested on iPhone
- [ ] All scenarios tested on iPad
- [ ] Tested on minimum iOS version (15.0)
- [ ] Tested on latest iOS version
- [ ] Tested on WiFi connection
- [ ] Tested on cellular connection
- [ ] Tested with poor network conditions
- [ ] No critical bugs found
- [ ] Performance is acceptable
- [ ] Accessibility requirements met

## Defect Tracking

| Scenario | Issue | Severity | Status |
| -------- | ----- | -------- | ------ |
|          |       |          |        |

## Notes

- Each scenario should be tested by at least 2 different testers
- Any failures should be documented with steps to reproduce
- Screenshots/recordings should be captured for any issues
- Re-test all failed scenarios after fixes
