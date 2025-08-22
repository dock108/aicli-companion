# Issue #10: Clickable File Links in Chat

**Priority**: Medium  
**Component**: iOS App - Message Display / Server Integration  
**Beta Blocker**: No  
**Discovered**: 2025-08-21  
**Status**: New  

## Problem Description

Implement clickable file names in chat messages that connect to the server and display the formatted file content. When Claude mentions file paths in responses (e.g., "Modified src/server.js:42"), users should be able to tap/click on these file references to view the actual file with proper syntax highlighting.

## Investigation Areas

1. Detect file path patterns in message content (e.g., `file.ext`, `path/to/file.ext`, `file.ext:lineNumber`)
2. Make detected file paths clickable/tappable with visual indication (underline, color)
3. On tap, request file content from server via new API endpoint
4. Display file in a modal/sheet with syntax highlighting based on file extension
5. Support line number navigation if specified (file.ext:42 jumps to line 42)
6. Handle various file path formats Claude might use
7. Implement file content caching to avoid repeated server requests
8. Add "Copy Path" and "Copy Content" actions in file viewer
9. Handle files that don't exist or user lacks permissions to read

## Expected Behavior

User sees "Modified src/components/Header.jsx:156" in Claude's response, taps on it, and a formatted view of Header.jsx opens with line 156 highlighted. File content is properly syntax highlighted and readable.

## Files to Investigate

- `ios/Sources/AICLICompanion/Views/Chat/Components/MessageBubble.swift` (detect and style file links)
- `ios/Sources/AICLICompanion/Views/FileViewer/FileViewerSheet.swift` (create file viewer)
- `ios/Sources/AICLICompanion/Services/FileContentService.swift` (fetch file content)
- `server/src/routes/files.js` (add GET endpoint for file content)
- `ios/Sources/AICLICompanion/Utils/MessageParser.swift` (parse file references)
- Consider using Highlightr or similar for syntax highlighting

## Solution Implemented

### 1. File Path Detection
- Regex patterns for various formats
- Support for line numbers
- Visual styling for links

### 2. File Viewer
- Syntax highlighting
- Line number navigation
- Copy functionality

### 3. Server Integration
- Secure file access endpoint
- Path validation
- Permission checks

## Testing Requirements

### Manual Testing Steps
1. Send messages with file paths
2. Test clicking on file links
3. Verify syntax highlighting
4. Test line number navigation

### Test Scenarios
- [ ] File path detection
- [ ] Click handling
- [ ] Syntax highlighting
- [ ] Security validation

## Technical Considerations

- Security: Validate file paths to prevent directory traversal
- Performance: Cache viewed files for session duration
- UX: Show loading state while fetching file content
- Support common path formats: relative, absolute, with line numbers

## Status

**Current Status**: New  
**Last Updated**: 2025-08-22