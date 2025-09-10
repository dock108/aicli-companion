# Issue 091025-1: Developer Quick Actions in Chat

**Priority**: Low  
**Component**: iOS App - Chat UI Enhancement  
**Beta Blocker**: No  
**Discovered**: 2025-09-10  
**Status**: Open  
**Type**: Feature Enhancement  

## Feature Description

Add contextual quick action buttons/prompts in the chat interface that trigger common developer tasks with relevant project context. These would be pre-configured prompts that users can tap to quickly execute routine development workflows without typing out full requests.

## User Story

As a developer using AICLI Companion, I want quick access to common development tasks so that I can trigger routine actions without typing repetitive prompts, saving time and ensuring consistent task execution.

## Proposed Solution

### 1. Universal Developer Actions
Quick actions that work across all projects:

#### Code Review Actions
- **"Review Recent Changes"** - Triggers: "Review the changes made in the last commit and provide feedback on code quality, potential bugs, and suggestions for improvement"
- **"Review This File"** - With file selector: "Please review [selected file] for code quality, performance, security issues, and best practices"
- **"Security Audit"** - Triggers: "Perform a security audit of the recent changes, looking for potential vulnerabilities"

#### Documentation Actions
- **"Document This Code"** - With file/function selector: "Generate comprehensive documentation for [selected code]"
- **"Update README"** - Triggers: "Update the README.md based on recent changes to the project"
- **"Generate API Docs"** - Triggers: "Generate API documentation for the public interfaces"

#### Issue Management
- **"Create Issue"** - Opens template: "Create a new issue for: [user fills in]"
- **"Fix TODO Comments"** - Triggers: "Find and address all TODO comments in the codebase"
- **"Bug Report Template"** - Pre-fills: "I found a bug: [Description]. Steps to reproduce: 1. [step]..."

#### Testing Actions
- **"Write Tests"** - With file selector: "Write comprehensive tests for [selected file/function]"
- **"Run Tests"** - Triggers: "Run all tests and fix any failures"
- **"Coverage Report"** - Triggers: "Generate a test coverage report and suggest areas needing tests"

#### Project-Level Commands
- **"Run Linter"** - Auto-detects and runs: `npm run lint`, `swiftlint`, `rubocop`, `pylint`, etc.
- **"Run Tests"** - Auto-detects and runs: `npm test`, `swift test`, `pytest`, `go test`, etc.
- **"Build Project"** - Auto-detects and runs: `npm run build`, `swift build`, `make`, `cargo build`
- **"Format Code"** - Auto-detects and runs: `prettier`, `swiftformat`, `black`, `gofmt`
- **"Type Check"** - Auto-detects and runs: `tsc`, `mypy`, `flow check`
- **"Clean"** - Auto-detects and runs: `npm run clean`, `swift package clean`, `make clean`
- **"Install Dependencies"** - Auto-detects and runs: `npm install`, `pod install`, `pip install -r requirements.txt`
- **"Update Dependencies"** - Auto-detects and runs: `npm update`, `swift package update`, `bundle update`
- **"Run Dev Server"** - Auto-detects and runs: `npm run dev`, `npm start`, `python manage.py runserver`
- **"Run Benchmarks"** - If available: `npm run bench`, `go test -bench`, `cargo bench`

#### Refactoring Actions
- **"Suggest Refactoring"** - With file selector: "Analyze [selected code] and suggest refactoring improvements"
- **"Clean Code"** - Triggers: "Review the codebase for code smells and suggest cleanups"
- **"Performance Optimize"** - Triggers: "Analyze performance bottlenecks and suggest optimizations"

### 2. Smart Command Detection

The app should automatically detect available commands in the project:

#### Auto-Detection Strategy
1. **Package Manager Detection**
   - Check for `package.json` → Extract npm scripts
   - Check for `Package.swift` → Swift package commands
   - Check for `Gemfile` → Ruby/Rails commands
   - Check for `requirements.txt`/`setup.py` → Python commands
   - Check for `go.mod` → Go commands
   - Check for `Cargo.toml` → Rust commands

2. **Script Extraction**
   ```swift
   struct ProjectCommands {
       let detected: [DetectedCommand]
       let custom: [CustomCommand]
       
       struct DetectedCommand {
           let name: String
           let command: String
           let source: String // "package.json", "Makefile", etc.
           let category: CommandCategory
           let confidence: Double // How sure we are this command exists
       }
   }
   ```

3. **Common Patterns Recognition**
   - Makefile targets
   - npm/yarn scripts from package.json
   - Gradle/Maven tasks
   - Rake tasks
   - Django management commands
   - Composer scripts

4. **Intelligent Suggestions**
   ```swift
   // Example detection logic
   func detectProjectCommands() -> [DetectedCommand] {
       var commands: [DetectedCommand] = []
       
       // Check package.json
       if let packageJson = readPackageJson() {
           for (scriptName, scriptCommand) in packageJson.scripts {
               commands.append(DetectedCommand(
                   name: prettifyName(scriptName),
                   command: "npm run \(scriptName)",
                   source: "package.json",
                   category: categorize(scriptName),
                   confidence: 1.0
               ))
           }
       }
       
       // Check for SwiftLint
       if fileExists(".swiftlint.yml") {
           commands.append(DetectedCommand(
               name: "Lint Code",
               command: "swiftlint",
               source: ".swiftlint.yml",
               category: .quality,
               confidence: 0.9
           ))
       }
       
       return commands
   }
   ```

### 3. Project-Specific Actions
Customizable templates stored per project:

#### Custom Templates Structure
```swift
struct QuickAction {
    let id: UUID
    let title: String
    let icon: String // SF Symbol name
    let category: ActionCategory
    let prompt: String
    let requiresFileSelection: Bool
    let requiresUserInput: [InputField]?
}

struct InputField {
    let placeholder: String
    let type: InputType // text, multiline, number, picker
    let options: [String]? // for picker type
}

enum ActionCategory {
    case review
    case documentation
    case testing
    case refactoring
    case build
    case custom
}
```

#### Examples of Project-Specific Actions
- **"Deploy to Staging"** - Project-specific deployment command
- **"Run Migration"** - Database migration for backend projects
- **"Update Translations"** - For internationalized apps
- **"Generate Mocks"** - For projects using mock data
- **"Sync Schema"** - For GraphQL/database projects

### 3. UI/UX Design

#### Access Points
1. **Floating Action Button (FAB)** - Quick access menu in chat
2. **Long-press on send button** - Shows action menu
3. **Slash commands** - Type "/" to see available actions
4. **Toolbar above keyboard** - Scrollable quick action chips

#### Visual Design
```
┌─────────────────────────────────┐
│  💬 Chat with Claude             │
├─────────────────────────────────┤
│                                 │
│  [Previous messages...]         │
│                                 │
├─────────────────────────────────┤
│ ┌─────────────────────────────┐ │
│ │ Quick Actions:              │ │
│ │ [📝 Review] [🧪 Test] [📚 Doc]│ │
│ │ [🔧 Fix] [🚀 Deploy] [+ More]│ │
│ └─────────────────────────────┘ │
├─────────────────────────────────┤
│ Type a message...          [📎] │
└─────────────────────────────────┘
```

#### Action Selection Flow
1. User taps quick action
2. If requires file selection → Show file picker
3. If requires user input → Show input dialog
4. Compose final prompt with context
5. Send to Claude automatically
6. Show loading state with action description

### 4. Implementation Details

#### Data Storage
```swift
// Store in UserDefaults or CloudKit
struct ProjectQuickActions: Codable {
    let projectId: String
    let customActions: [QuickAction]
    let enabledUniversalActions: Set<String>
    let actionHistory: [ActionHistoryItem] // Track usage for suggestions
}

struct ActionHistoryItem: Codable {
    let actionId: String
    let timestamp: Date
    let frequency: Int
}
```

#### Context Injection
When a quick action is triggered, automatically inject:
- Current project path
- Git branch information
- Recent file changes
- Project type/language
- Any open issues from the session

#### Smart Suggestions
- Show most-used actions first
- Suggest actions based on:
  - Time of day (e.g., "Run tests" before commits)
  - Recent activity (e.g., "Document" after adding new code)
  - Project phase (e.g., "Deploy" actions when on main branch)

### 5. Command Execution UI

#### Command Palette View
```
┌─────────────────────────────────┐
│  🚀 Project Commands            │
├─────────────────────────────────┤
│ Detected from package.json:     │
│ ├─ 📦 npm install               │
│ ├─ 🧪 npm test                  │
│ ├─ 🔍 npm run lint              │
│ ├─ 🏗️ npm run build             │
│ └─ 🚀 npm run dev               │
│                                 │
│ Detected from .swiftlint.yml:   │
│ ├─ 🔍 swiftlint                 │
│ └─ 🔧 swiftlint --fix           │
│                                 │
│ Custom Commands:                │
│ ├─ 📱 Deploy to TestFlight      │
│ └─ 🔄 Sync Database             │
│                                 │
│ [+ Add Custom Command]          │
└─────────────────────────────────┘
```

#### Command Execution Flow
1. User taps command
2. Show confirmation with command preview:
   ```
   Run Command?
   > npm run lint
   
   This will check your code for style issues.
   
   [Cancel] [Run]
   ```
3. Execute with real-time output display
4. Show results in chat with proper formatting
5. Offer follow-up actions based on results

#### Smart Command Chaining
```swift
struct CommandChain {
    let name: String
    let commands: [String]
    let stopOnError: Bool
    
    // Example chains
    static let preCommit = CommandChain(
        name: "Pre-commit Check",
        commands: ["npm run lint", "npm test", "npm run build"],
        stopOnError: true
    )
    
    static let fullCheck = CommandChain(
        name: "Full Project Check",
        commands: ["swiftlint", "swift test", "swift build"],
        stopOnError: false
    )
}
```

### 6. Configuration UI

#### Settings Screen Addition
```
Settings > Quick Actions
├── Universal Actions (toggle list)
├── Custom Actions
│   ├── Add Custom Action
│   ├── Edit Actions
│   └── Import/Export Templates
├── Display Options
│   ├── Show in toolbar
│   ├── Show FAB
│   └── Enable slash commands
└── Usage Statistics
```

#### Template Sharing
- Export action templates as JSON
- Import from URL or file
- Share via CloudKit between devices
- Community template repository (future)

## Benefits

1. **Increased Productivity** - Common tasks are one tap away
2. **Consistency** - Standardized prompts ensure consistent results
3. **Discoverability** - Users learn what Claude can do
4. **Reduced Typing** - Especially helpful on mobile
5. **Project Context** - Actions automatically include relevant context
6. **Customization** - Teams can standardize their workflows

## Technical Requirements

### iOS Implementation
- Modify `ChatInputBar.swift` to add action toolbar
- Create `QuickActionsView.swift` component
- Add `QuickActionsManager.swift` service
- Extend `ChatViewModel.swift` to handle action triggers
- Store configuration in `SettingsManager.swift`

### Server-Side Support
- No server changes required initially
- Future: Store team templates in server
- Future: Analytics on action usage

## Success Metrics

- Number of quick actions used per session
- Time saved (measure typing reduction)
- User feedback on usefulness
- Custom action creation rate
- Most/least used actions

## MVP Scope

For initial implementation, focus on:
1. 5-6 universal actions (Review, Test, Document, Fix TODOs, Run Tests, Create Issue)
2. Simple tap-to-trigger (no file selection initially)
3. Toolbar above keyboard display
4. Basic customization (enable/disable actions)
5. Store in UserDefaults

## Future Enhancements

1. **AI-Powered Suggestions** - Claude suggests relevant actions based on conversation
2. **Voice Triggers** - "Hey Claude, run tests"
3. **Workflows** - Chain multiple actions together
4. **Team Sharing** - Share action templates with team
5. **IDE Integration** - Sync with VS Code/Xcode quick actions
6. **Contextual Parameters** - Auto-detect relevant files/functions
7. **Action Results** - Special formatting for action results
8. **Scheduling** - Schedule recurring actions
9. **Conditional Actions** - Only show when certain conditions are met
10. **Action Marketplace** - Community-contributed action templates

## Real-World Examples

### For This Project (AICLI Companion)
Detected commands would include:
- **iOS Project**:
  - `swiftlint` - Lint Swift code
  - `swift build` - Build the iOS app
  - `swift test` - Run Swift tests
  - `xcodebuild test` - Run UI tests
  
- **Server Project**:
  - `npm run lint` - Lint JavaScript code
  - `npm test` - Run server tests
  - `npm run prettier:check` - Check code formatting
  - `npm run prettier:fix` - Fix code formatting
  - `npm run test:coverage` - Run tests with coverage

### Command Learning
The system could learn from user behavior:
1. Track which commands users run manually in chat
2. Suggest adding frequently used commands as quick actions
3. Learn command sequences (e.g., always run lint before test)
4. Suggest command chains based on patterns

### Error Handling & Recovery
When a command fails:
1. Parse error output
2. Suggest fix actions (e.g., "Run npm install?" if module not found)
3. Offer to have Claude analyze and fix the error
4. Learn from fixes for future suggestions

## Related Issues
- Could enhance: Chat UI/UX improvements
- Synergizes with: Auto-response features
- Similar to: VS Code Claude extension quick commands

## Implementation Checklist
- [ ] Design quick actions UI/UX
- [ ] Implement QuickActionsManager
- [ ] Add action toolbar to ChatInputBar
- [ ] Create default action templates
- [ ] Add settings configuration UI
- [ ] Implement action trigger logic
- [ ] Add context injection system
- [ ] Create custom action builder UI
- [ ] Add usage analytics
- [ ] Write tests
- [ ] Document feature for users

## User Testing Scenarios
1. Trigger each universal action
2. Create custom action
3. Use action with file selection
4. Use action with user input
5. Test on different device sizes
6. Verify context injection
7. Test action history/suggestions

## Notes

This feature would significantly improve the mobile development experience by reducing the friction of common tasks. It's especially valuable for repetitive workflows and helps users discover Claude's capabilities.

The key is to make actions:
- **Fast** - One tap to trigger
- **Smart** - Include relevant context automatically
- **Flexible** - Customizable per project/user
- **Discoverable** - Easy to find and understand

Priority is low as this is a nice-to-have enhancement, but it could become a differentiating feature that makes AICLI Companion the preferred mobile interface for Claude-assisted development.