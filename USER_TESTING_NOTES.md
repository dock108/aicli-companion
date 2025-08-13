# User Testing Notes

## Overview
This document tracks issues, observations, and improvements discovered during user testing of the AICLI Companion app.

## Issues Discovered

### Priority: High
<!-- Critical issues that block core functionality -->

- **Message Persistence Issues** (2025-08-13) ✅ FIXED
  - **ISSUE**: Messages were disappearing when switching between projects
  - **ROOT CAUSE**: ChatView was loading from BackgroundSessionCoordinator instead of local message persistence
  - **RESOLUTION**: Updated project switching logic to load from MessagePersistenceService
  - **IMPLEMENTATION**: Fixed `handleProjectChange()` in ChatView.swift to properly load saved conversations
  - **RESULT**: Complete conversation history now persists across project switches and app restarts

- **Local-First Architecture Implementation** (2025-08-13) ✅ COMPLETED  
  - **CHANGE**: Transitioned from complex server polling to WhatsApp/iMessage local-first pattern
  - **IMPLEMENTATION**: Messages stored locally immediately on send/receive
  - **BENEFITS**: Zero message loss, instant UI updates, offline conversation browsing
  - **SIMPLIFIED**: Removed ~300 lines of complex retry/recovery logic

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

- **iPad: Two settings icons visible** - There are two settings icons showing on iPad. The higher one doesn't appear to be visible on iPhone anywhere.

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
**Last Updated**: 2025-08-13 (Message persistence fixed, local-first architecture completed)