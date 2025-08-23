# Issue #31: Planning/Issues Mode for Documentation-Only Operations

**Priority**: High  
**Component**: iOS App/Server - Mode Selection  
**Beta Blocker**: No (but very useful for safe planning)  
**Discovered**: 2025-08-22  
**Status**: New  

## Problem Description

We need a "Planning Mode" or "Issues Mode" in the app that restricts Claude to only modify documentation files (*.md, *.txt, *.doc, etc.) for planning and issue tracking purposes. This mode would automatically add a prompt prefix/suffix or JSON wrapper to enforce these restrictions, preventing accidental code modifications during planning sessions.

## Investigation Areas

1. Add mode toggle in iOS app UI (Planning/Code/Normal)
2. Implement prompt modification on server or client side
3. Define allowed file extensions for planning mode
4. Add visual indicator showing current mode
5. Persist mode selection per project or globally
6. Consider server-side enforcement of restrictions
7. Handle mode in both chat and auto-response scenarios
8. Clear user feedback about mode restrictions

## Expected Behavior

- User toggles "Planning Mode" in iOS app
- All messages sent in this mode are prefixed/wrapped with restrictions
- Claude can only read code files but write only to documentation files
- Clear visual indicator showing "Planning Mode Active"
- Mode persists across app restarts (per project or global setting)

## Files to Investigate

### iOS Side
- `ios/Sources/AICLICompanion/Views/Chat/ChatInputView.swift` (mode toggle UI)
- `ios/Sources/AICLICompanion/ViewModels/ChatViewModel.swift` (mode state)
- `ios/Sources/AICLICompanion/Services/AICLIService.swift` (prompt modification)
- `ios/Sources/AICLICompanion/Models/ChatMode.swift` (new mode enum)

### Server Side
- `server/src/routes/chat.js` (mode handling)
- `server/src/services/aicli-message-handler.js` (prompt wrapping)
- `server/src/utils/mode-enforcement.js` (new - mode restrictions)

## Implementation Approach

### 1. Mode Definition
```swift
enum ChatMode: String, CaseIterable {
    case normal = "Normal"
    case planning = "Planning"  // Docs only
    case code = "Code"         // Code focused
    
    var icon: String {
        switch self {
        case .normal: return "text.bubble"
        case .planning: return "doc.text"
        case .code: return "chevron.left.slash.chevron.right"
        }
    }
    
    var description: String {
        switch self {
        case .normal: return "Full access"
        case .planning: return "Documentation only"
        case .code: return "Code generation focus"
        }
    }
}
```

### 2. Prompt Modification

#### Option A: Prefix/Suffix
```javascript
function wrapForPlanningMode(userPrompt) {
  const prefix = `IMPORTANT: You are in PLANNING MODE. You may ONLY create or modify documentation files (*.md, *.txt, *.doc, *.plan, *.todo). You may READ any file but can only WRITE to documentation files. DO NOT modify any code files.\n\n`;
  
  const suffix = `\n\nREMEMBER: Planning mode active - only modify documentation files.`;
  
  return prefix + userPrompt + suffix;
}
```

#### Option B: JSON Wrapper
```javascript
function wrapForPlanningMode(userPrompt) {
  return JSON.stringify({
    mode: "planning",
    restrictions: {
      allowedWriteExtensions: [".md", ".txt", ".doc", ".plan", ".todo", ".rst"],
      allowedOperations: ["read_any", "write_docs_only"],
      message: "Only create/modify documentation files"
    },
    userPrompt: userPrompt
  });
}
```

#### Option C: System Prompt Override
```javascript
function getPlanningModeSystemPrompt() {
  return `You are Claude in PLANNING MODE. In this mode, you:
  - Can READ any file to understand the codebase
  - Can ONLY WRITE to documentation files (*.md, *.txt, *.doc, *.plan, *.todo)
  - Must REFUSE to modify code files with a polite explanation
  - Should focus on planning, documentation, and issue tracking
  - Create comprehensive plans and documentation
  
  If asked to modify code, respond: "I'm in Planning Mode and can only modify documentation files. Would you like me to create a plan for these changes instead?"`;
}
```

### 3. UI Implementation

```swift
// Mode selector in ChatInputView
HStack {
    Menu {
        ForEach(ChatMode.allCases, id: \.self) { mode in
            Button(action: { 
                selectedMode = mode 
                saveModeSetting(mode)
            }) {
                Label(mode.rawValue, systemImage: mode.icon)
            }
        }
    } label: {
        HStack {
            Image(systemName: selectedMode.icon)
            Text(selectedMode.rawValue)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(modeBackgroundColor)
        .cornerRadius(8)
    }
    
    // Rest of input field
}

// Visual indicator
var modeBackgroundColor: Color {
    switch selectedMode {
    case .planning: return .orange.opacity(0.2)
    case .code: return .blue.opacity(0.2)
    case .normal: return .clear
    }
}
```

### 4. Allowed Extensions for Planning Mode

```javascript
const PLANNING_MODE_EXTENSIONS = [
  '.md',      // Markdown
  '.txt',     // Plain text
  '.doc',     // Documentation
  '.docx',    // Word docs
  '.plan',    // Plan files
  '.todo',    // Todo lists
  '.rst',     // reStructuredText
  '.adoc',    // AsciiDoc
  '.org',     // Org mode
  '.wiki',    // Wiki format
  '.notes',   // Notes files
  'README',   // README files (any extension)
  'TODO',     // TODO files (any extension)
  'PLAN',     // PLAN files (any extension)
  'ISSUES',   // ISSUES files (any extension)
];
```

## Benefits

- **Safety**: Prevents accidental code changes during planning
- **Focus**: Keeps Claude focused on documentation tasks
- **Clarity**: Clear separation between planning and implementation
- **Confidence**: Users can plan without worrying about code changes
- **Organization**: Encourages proper documentation practices

## Testing Requirements

### Manual Testing Steps
1. Enable Planning Mode
2. Try to modify a code file (should refuse)
3. Create/modify documentation files (should work)
4. Read code files (should work)
5. Switch modes and verify behavior changes

### Test Scenarios
- [ ] Mode toggle UI works
- [ ] Mode persists across sessions
- [ ] Planning mode restrictions enforced
- [ ] Clear error messages when trying to modify code
- [ ] All documentation formats supported
- [ ] Mode indicator visible

## User Experience

### Mode Selection Flow
1. User taps mode button in chat input area
2. Menu shows three options with descriptions
3. Selected mode shows colored indicator
4. Mode name visible at all times
5. Optional: Confirmation when switching from Planning to Normal

### Error Message in Planning Mode
```
📝 Planning Mode Active

I cannot modify code files while in Planning Mode. I can:
• Create or update documentation files
• Create detailed implementation plans
• Write issues and TODOs
• Read any file to understand the code

Would you like me to create a plan for these changes instead?
```

## Configuration Options

```javascript
// Server environment variables
PLANNING_MODE_STRICT=true  // Enforce server-side
PLANNING_MODE_EXTENSIONS=.md,.txt,.doc  // Customizable

// iOS Settings
- Default Mode (per project or global)
- Remember Last Mode
- Show Mode Warning
- Allowed Extensions (advanced)
```

## Related Issues

- Could integrate with Issue #4 (Auto-iteration mode)
- Complements Issue #28 (Activity monitoring)
- Useful for Issue creation workflow

## Status

**Current Status**: New  
**Last Updated**: 2025-08-22