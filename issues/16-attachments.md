# Issue #16: Attachments Not Persisting in Chat UI

**Priority**: High  
**Component**: iOS App - Message Display / Attachment Handling  
**Beta Blocker**: Yes - Core functionality broken  
**Discovered**: 2025-08-21

## Problem Description

Attachments (images, files) are successfully sent to the server and Claude responds appropriately to them, but the attachments don't appear in the chat UI above the text message bubble after sending. The attachment disappears from view even though it was processed correctly.

## Root Cause Analysis

The attachment persistence issue was caused by:

1. **Missing Attachment Data in Message Creation**: ChatViewModel was creating the user message without including the attachments array
2. **Attachments Only Sent to Server**: Attachments were passed to the server via `aicliService.sendMessage()` but not included in the local Message object
3. **Local-First Pattern Incomplete**: The local message created for immediate UI display lacked attachment data

## Solution Implemented

### Fixed Message Creation with Attachments
- Modified ChatViewModel.sendMessage to include attachments in the Message constructor
- Ensures attachments are part of the local message that gets persisted
- Maintains consistency between what's shown in UI and what's stored locally

## Changes Made

**File: ChatViewModel.swift**
```swift
// Before: Message created without attachments
let userMessage = Message(
    content: text,
    sender: .user,
    type: .text,
    requestId: requestId
)

// After: Message includes attachments
let userMessage = Message(
    content: text,
    sender: .user,
    type: .text,
    requestId: requestId,
    attachments: attachments  // Include attachments in the local message
)
```

## Technical Details

### Message Model Support
- Message model already has full attachment support via `richContent` property
- AttachmentInfo stores base64Data, thumbnails, and metadata
- RichContent enum properly handles attachment data

### UI Components Working Correctly
- MessageContentRenderer displays attachments for both user and AI messages
- MessageAttachmentList renders attachment previews properly
- ChatInputBar manages attachment state and passes to parent view
- AttachmentPreview shows thumbnails before sending

### The Fix
The only missing piece was including attachments when creating the Message object in ChatViewModel. Now attachments are:
1. Included in the local message immediately
2. Persisted via MessagePersistenceService
3. Displayed in the chat UI
4. Restored when loading conversation history

## Status

**Current Status**: ✅ FIXED - Attachments now persist in chat UI  
**Last Updated**: 2025-08-21

### Implementation Complete

- ✅ Verified Message model supports attachments via richContent
- ✅ Confirmed MessageBubble/ContentRenderer display attachments
- ✅ Verified ChatInputBar properly manages attachment state
- ✅ Fixed ChatViewModel to include attachments in Message creation
- ✅ Attachments now persist in UI after sending
- ✅ Attachments saved to MessagePersistenceService
- ✅ Attachments restored when loading conversation history
- ✅ Code compiled successfully with no errors

Attachments now properly persist in the chat UI and are stored locally, ensuring they remain visible when navigating away and returning to conversations.