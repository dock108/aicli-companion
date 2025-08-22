# Issue #7: Enhanced Claude Environment Details Display

**Priority**: Low  
**Component**: iOS App - Debug/Info Panel  
**Beta Blocker**: No  
**Discovered**: 2025-08-19  
**Status**: New  

## Problem Description

Create an enhanced view for Claude environment information and raw output. This would provide developers with detailed debugging information about Claude sessions, responses, and performance metrics.

## Investigation Areas

1. Expandable debug panel showing full Claude CLI environment details
2. Raw JSON/stream output viewer for debugging
3. Session metadata display (session ID, creation time, message count)
4. Token usage statistics if available from Claude CLI
5. Response timing and latency metrics
6. Tool usage breakdown (which tools Claude used and how often)
7. Collapsible sections for different types of information
8. Copy-to-clipboard functionality for raw data
9. Optional verbose mode toggle for detailed logging

## Expected Behavior

Users can access a detailed debug view showing all available Claude session information, raw responses, and performance metrics in an organized, expandable interface.

## Files to Investigate

- `ios/Sources/AICLICompanion/Views/Debug/EnvironmentDetailsView.swift` (to be created)
- `ios/Sources/AICLICompanion/ViewModels/DebugViewModel.swift` (to be created)
- `server/src/services/aicli-telemetry.js` (enhance existing)
- `server/src/routes/debug.js` (to be created for debug endpoints)

## Solution Implemented

### 1. Debug Panel UI
- Expandable sections for different data types
- Clean, organized layout
- Dark mode support

### 2. Data Collection
- Session metadata tracking
- Performance metrics
- Tool usage statistics

### 3. Export Features
- Copy to clipboard
- Export as JSON
- Share functionality

## Testing Requirements

### Manual Testing Steps
1. Open debug panel
2. Verify all sections populate
3. Test copy/export functions
4. Check performance impact

### Test Scenarios
- [ ] Debug panel display
- [ ] Data accuracy
- [ ] Export functionality
- [ ] Performance overhead

## Status

**Current Status**: New  
**Last Updated**: 2025-08-22