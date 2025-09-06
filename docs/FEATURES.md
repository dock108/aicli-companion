# AICLI Companion Features

## Feature Visibility Status
Last Updated: 2025-09-06

### Chat Modes
| Feature | App Visibility | Internal Status | Flag | Description |
|---------|---------------|-----------------|------|-------------|
| Normal Mode | ✅ Visible | Complete | `showNormalMode = true` | Full access to all operations |
| Planning Mode | ✅ Visible | Complete | `showPlanningMode = true` | Can only modify docs (*.md, *.txt, etc.) |
| Code Mode | ❌ Hidden | Complete | `showCodeMode = false` | Fast code generation mode |

### Workspace Mode Tools
| Feature | App Visibility | Internal Status | Flag | Description |
|---------|---------------|-----------------|------|-------------|
| New Project | ✅ Visible | Complete | `showProjectCreation = true` | Create projects with AI guidance |
| Planning Validation | ❌ Hidden | Complete | `showPlanningValidation = false` | Analyze project readiness |
| Code Review | ❌ Hidden | In Development | `showCodeReview = false` | AI-powered code review |
| Refactor Assistant | ❌ Hidden | In Development | `showRefactorAssistant = false` | Intelligent refactoring suggestions |

### Core Features (Always On)
| Feature | Status | Control | Description |
|---------|--------|---------|-------------|
| Queue System | ❌ Disabled | `isQueueSystemEnabled = false` | Message queueing system |
| Attachments | ✅ Active | Settings-based | File attachments in chat |
| CloudKit Sync | ✅ Active | Settings-based | iCloud synchronization |
| WebSocket | ✅ Active | Always on | Real-time communication |
| Push Notifications | ✅ Active | User permission required | Message delivery via APNS |

### Experimental Features (Hidden)
| Feature | Status | Flag | Description |
|---------|--------|------|-------------|
| Auto Mode | ❌ Hidden | `showAutoModeUI = false` | Automatic response generation |
| Queue UI | ❌ Hidden | `showQueueUI = false` | Queue status indicators |

## Visibility Control

### App Visibility States
- **✅ Visible**: Feature is shown to users in the app
- **❌ Hidden**: Feature exists but is not visible to users

### Internal Status
- **Complete**: Feature is fully implemented and tested
- **In Development**: Feature is being built
- **Experimental**: Feature is in early testing

### To Change Visibility
1. Update the flag in `ios/Sources/AICLICompanion/FeatureFlags.swift`
2. Rebuild the iOS app
3. Feature will appear/disappear from UI

## Current Configuration Summary

### What Users See:
**Chat Modes:**
- ✅ Normal mode - Full access
- ✅ Planning mode - Documentation only

**Workspace Tools:**
- ✅ New Project - Create projects with AI guidance

### What's Hidden:
**Chat Modes:**
- ❌ Code mode - Fast generation mode

**Workspace Tools:**
- ❌ Planning Validation - Readiness analysis
- ❌ Code Review - Coming soon
- ❌ Refactor Assistant - Coming soon

**System Features:**
- ❌ Queue System - Message queueing
- ❌ Auto Mode - Automatic responses

## Feature Descriptions

### Chat Modes

#### Normal Mode
- Full access to all file operations
- Can read and write any file type
- Standard permission prompts
- Default mode for general use

#### Planning Mode
- Limited to documentation files only
- Can modify: *.md, *.txt, README, TODO, PLAN, etc.
- Can still read all files including code
- Ideal for project planning and documentation

#### Code Mode (Hidden)
- Optimized for fast code generation
- Fewer permission prompts
- Streamlined for development tasks
- Currently in testing

### Workspace Mode Tools

#### New Project
- AI-guided project creation wizard
- Template selection
- Automatic project structure setup
- Git initialization support

#### Planning Validation (Hidden)
- Analyzes project readiness
- Domain-specific scoring (Database, API, UI/UX, Security, etc.)
- Identifies blockers and missing requirements
- Provides actionable suggestions
- Generates prioritized action items

#### Code Review (Coming Soon)
- AI-powered code analysis
- Best practices checking
- Security vulnerability detection
- Performance optimization suggestions

#### Refactor Assistant (Coming Soon)
- Intelligent code refactoring
- Pattern detection and improvement
- Code smell identification
- Automated refactoring suggestions

## Development Notes

### Adding New Features
1. Add feature flag in `FeatureFlags.swift`
2. Implement feature with flag check
3. Update this documentation
4. Test with flag on/off
5. Deploy with flag initially set to `false`

### Feature Flag Naming Convention
- Visibility flags: `show{FeatureName}`
- Enable flags: `enable{FeatureName}`
- System flags: `is{Feature}Enabled`

### Testing Features
To test hidden features:
1. Set the flag to `true` in `FeatureFlags.swift`
2. Rebuild and run the app
3. Verify feature appears and functions correctly
4. Set flag back to `false` before committing

## Version History

### v1.0.0 (2025-09-06)
- Initial feature flag system implementation
- Hidden: Code mode, Planning Validation, Queue System
- Visible: Normal mode, Planning mode, New Project tool