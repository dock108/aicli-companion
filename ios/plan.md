# Server and macOS Compatibility Update Plan

## Executive Summary
Update the server and macOS app to fully support the new iOS features we've implemented, including attachment handling, Jesus Take the Wheel mode (auto-response), and Claude Thinking Indicator.

## Current State Analysis

### What We Have Now
- iOS app with attachment support (base64 encoded in HTTP payload)
- iOS auto-response mode (Jesus Take the Wheel) with UI controls
- iOS Claude Thinking Indicator showing duration, tokens, and activity
- Server using APNS for message delivery
- macOS app without these new features

### What We're Building
- Server support for processing attachments from iOS
- Server metadata support for auto-response and thinking indicators
- macOS app feature parity with iOS

## Implementation Plan

### Phase 1: Server Attachment Support (Critical) ✅

#### TODO 1.1: Update Chat API to Accept Attachments ✅
- ✅ Modified `/server/src/routes/chat.js` to handle `attachments` field
- ✅ Extract base64 data from HTTP payload
- ✅ Validate attachment size (10MB default) and MIME types
- ✅ Pass attachment data to AICLI service

#### TODO 1.2: Update AICLI Service for Attachments ✅
- ✅ Modified `sendPrompt()` in `/server/src/services/aicli.js`
- ✅ Create temporary files from base64 attachment data
- ✅ Add file paths to Claude CLI command arguments
- ✅ Clean up temporary files after processing

#### TODO 1.3: Update APNS for Rich Attachment Notifications ✅
- ✅ Extended push notification payload for attachment metadata
- ✅ Include attachment info in Claude response notifications
- ✅ Show attachment count in notification title

### Phase 2: Server Auto-Response Support ✅

#### TODO 2.1: Add Auto-Response Metadata to Chat API ✅
- ✅ Accept auto-response flags in chat requests
- ✅ Track auto-response state in session metadata
- ✅ Pass auto-response info through to Claude

#### TODO 2.2: Create Auto-Response Control Endpoints ✅
- ✅ Add `/api/chat/auto-response/pause` endpoint
- ✅ Add `/api/chat/auto-response/resume` endpoint
- ✅ Add `/api/chat/auto-response/stop` endpoint
- ✅ Implement proper session-based state management

#### TODO 2.3: Include Auto-Response Status in APNS ✅
- ✅ Add auto-response metadata to push payloads
- ✅ Include iteration count and status
- ✅ Support pause/resume signals via APNS
- ✅ Created sendAutoResponseControlNotification method

### Phase 3: Server Thinking Indicator Support

#### TODO 3.1: Extract Claude Thinking Metadata
- Parse Claude CLI output for progress information
- Extract duration, token count, and activity type
- Track thinking state during processing

#### TODO 3.2: Stream Progress via APNS
- Include thinking metadata in push notifications
- Send periodic progress updates for long operations
- Add escape/interrupt support signals

#### TODO 3.3: Create Progress Polling Endpoint
- Add `/api/chat/:sessionId/progress` endpoint
- Return real-time thinking status
- Support non-APNS clients

### Phase 4: macOS App Feature Parity

#### TODO 4.1: macOS Attachment Support
- Add attachment picker UI matching iOS
- Implement drag-and-drop for files
- Add attachment preview in messages
- Support same MIME types as iOS

#### TODO 4.2: macOS Auto-Response Controls
- Add auto-response toggle in menu bar
- Show status indicator when active
- Implement pause/resume/stop controls
- Match iOS auto-response UI behavior

#### TODO 4.3: macOS Thinking Indicator
- Add thinking indicator to activity monitor
- Show token count and duration
- Display escape hint for long operations
- Match iOS visual design

### Phase 5: Infrastructure and Testing

#### TODO 5.1: Server Configuration Updates
- Add MAX_ATTACHMENT_SIZE environment variable
- Configure TEMP_FILE_PATH for attachments
- Update server documentation
- Add attachment handling to README

#### TODO 5.2: Error Handling and Validation
- Implement 10MB attachment size limit
- Validate supported MIME types
- Add proper error messages
- Handle cleanup on failures

#### TODO 5.3: Comprehensive Testing
- Unit tests for attachment processing
- Integration tests for auto-response flow
- Test thinking indicator metadata
- Ensure >80% code coverage
- Test APNS delivery with rich content

## Testing Plan

### Phase 1 Tests
- [ ] iOS can send attachment to server
- [ ] Server receives and processes attachment
- [ ] Claude CLI receives file path
- [ ] APNS delivers response with attachment info

### Phase 2 Tests  
- [ ] Auto-response mode activates correctly
- [ ] Pause/resume/stop endpoints work
- [ ] Session state tracks auto-response
- [ ] APNS includes auto-response metadata

### Phase 3 Tests
- [ ] Thinking metadata extracted from Claude
- [ ] Progress updates sent via APNS
- [ ] Polling endpoint returns correct status
- [ ] Long operation hints displayed

### Phase 4 Tests
- [ ] macOS attachment picker works
- [ ] macOS auto-response controls functional
- [ ] macOS thinking indicator displays
- [ ] Feature parity with iOS achieved

### Phase 5 Tests
- [ ] Size limits enforced
- [ ] Invalid attachments rejected
- [ ] Temp files cleaned up
- [ ] All tests pass with >80% coverage

## Success Metrics
- iOS attachment sending works end-to-end
- Auto-response mode fully functional
- Thinking indicator shows real progress
- macOS has complete feature parity
- Zero regression in existing functionality
- All linting passes (ESLint for server, SwiftLint for macOS)

## AI Assistant Instructions
1. Complete TODOs in order within each phase
2. Test each component before marking complete
3. Update this plan with ✅ as tasks complete
4. Run linting after each file change
5. Commit after each phase completion

**Current Status**: Phase 2 Complete ✅, Starting Phase 3  
**Next Step**: TODO 3.1 - Extract Claude Thinking Metadata  
**Last Updated**: 2025-08-12