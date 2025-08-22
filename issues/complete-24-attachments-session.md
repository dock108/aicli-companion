# Issue #24: Attachments May Break Session ID

**Priority**: High  
**Component**: iOS App/Server - Session Management  
**Beta Blocker**: Potentially (Session continuity issue)  
**Discovered**: 2025-08-21  
**Status**: New  

## Problem Description

Investigate potential issue where sending attachments (images, files) in chat may break or reset the Claude session ID, causing loss of conversation context. 

**Note**: User will provide logs for the affected session later.

## Investigation Areas

1. Check if attachments are being sent with the correct session ID
2. Verify server properly passes session ID when messages include attachments
3. Check if Claude Code CLI handles attachments differently regarding sessions
4. Investigate if multipart/form-data requests preserve session headers
5. Review how the iOS app constructs requests with attachments
6. Check if session ID is lost during attachment processing
7. Verify attachment messages are properly linked to existing sessions
8. Test with various attachment types and sizes

## Expected Behavior

Attachments should be sent within the existing session context. Claude should maintain conversation history and context even when images or files are included in messages.

## Files to Investigate

- `ios/Sources/AICLICompanion/Services/AICLIService.swift` (attachment request construction)
- `server/src/routes/chat.js` (attachment handling endpoint)
- `server/src/services/aicli-message-handler.js` (session ID passing with attachments)
- `ios/Sources/AICLICompanion/ViewModels/ChatViewModel.swift` (attachment sending logic)
- Check how multipart requests handle session headers

## Testing Requirements

### Manual Testing Steps
1. Send text message, note session ID
2. Send attachment in same conversation
3. Send follow-up text message
4. Verify all three messages share same session ID
5. Check if Claude maintains context across attachment

### Test Scenarios
- [ ] Text → Attachment → Text flow
- [ ] Multiple attachments in sequence
- [ ] Large file attachments
- [ ] Different attachment types (image, text, etc.)
- [ ] Session ID persistence verification

## Root Cause Analysis

From the log analysis in `/Users/michaelfuscoletti/Desktop/session_id_bug.txt`:
- Line 97 showed `[Session: new]` when attachment was sent instead of using existing session
- Line 98 showed `"hasSessionId":false` in request
- Session `1a3d55cb` existed but wasn't used with attachments
- The iOS app wasn't persisting and retrieving session IDs per project

## Solution Implemented

### 1. Session ID Persistence in iOS App
Added session ID storage/retrieval in `MessageOperations.swift`:
```swift
private func getSessionId(for projectPath: String) -> String? {
    let key = "claude_session_\(projectPath.replacingOccurrences(of: "/", with: "_"))"
    return UserDefaults.standard.string(forKey: key)
}

private func storeSessionId(_ sessionId: String, for projectPath: String) {
    let key = "claude_session_\(projectPath.replacingOccurrences(of: "/", with: "_"))"
    UserDefaults.standard.set(sessionId, forKey: key)
}
```

### 2. Include Session ID in All Requests
Modified `createChatRequest` to include stored session ID (lines 208-214):
```swift
if let sessionId = getSessionId(for: projectPath) {
    requestBody["sessionId"] = sessionId
    print("📝 Including session ID in request: \(sessionId)")
}
```

### 3. Store Session ID from All Response Types
Updated `parseSuccessResponse` to store session IDs from:
- Standard ClaudeChatResponse (lines 315-317)
- APNS acknowledgment responses (lines 332-334)
- Legacy response format (lines 348-350)

## Status

**Current Status**: Resolved  
**Last Updated**: 2025-08-22  
**Solution**: Implemented persistent session ID storage per project using UserDefaults