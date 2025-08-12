# User Testing Notes

## Overview
This document tracks issues, observations, and improvements discovered during user testing of the AICLI Companion app.

## Issues Discovered

### Priority: High
<!-- Critical issues that block core functionality -->

- **Push notifications disappearing**: Notifications arrive but don't appear in the message thread. This happens when:
  - User is still in the app when notification arrives
  - User opens the app shortly after notification arrives
  - Possible race condition between notification delivery and app state

- **Message Formatting Issues** (2025-08-12) ✅ FIXED
  - Long messages don't look aesthetically pleasing
  - Raw markdown appearing in push notifications
  - Note: We may have implemented code for this earlier - need to check existing implementation
  - **RESOLUTION**: Added `stripMarkdown()` function to remove markdown formatting from push notification body text
  - **IMPLEMENTATION**: Updates in `server/src/services/push-notification.js`
    - New `stripMarkdown()` method removes code blocks, headers, bold/italic, links, etc.
    - `truncateMessage()` now strips markdown before truncating
    - Truncation tries to break at word boundaries for cleaner display
  - **TESTED**: Added comprehensive tests in `push-notification-markdown.test.js`

### Priority: Medium
<!-- Issues that affect user experience but have workarounds -->

### Priority: Low
<!-- Minor issues or nice-to-have improvements -->

## User Feedback

### Feature Requests

### UX/UI Observations

### Performance Issues

## Action Items
<!-- Tasks to address discovered issues -->

---

**Created**: 2025-08-12
**Last Updated**: 2025-08-12 (Push notification disappearing issue, message formatting issues)