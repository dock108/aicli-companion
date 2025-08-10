# SwiftLint File Length Violations - Refactoring Plan

## Current Status
- **Target**: All files under 400 lines (SwiftLint requirement)
- **Violations**: 5 files with serious file length violations
- **Strategy**: Split large files into focused, single-responsibility modules

## File Analysis & Refactoring Strategy

### 1. SettingsView.swift (1050 lines) - CRITICAL
**Current Structure:**
- Main SettingsView (25 lines)
- GeneralSettingsView (205 lines)
- ServerSettingsView (93 lines) 
- SecuritySettingsView (372 lines) - **TOO LARGE**
- NgrokSetupView (120 lines)
- Step Views (3 x 30 lines each)
- AdvancedSettingsView (55 lines)
- SettingsDocument (20 lines)

**Refactoring Plan:**
1. **Split SecuritySettingsView** (372 lines → 3 files):
   - `SecuritySettingsView.swift` (120 lines) - Main view + Authentication
   - `TunnelSettingsView.swift` (120 lines) - Internet access + ngrok config
   - `NgrokSetupView.swift` (130 lines) - Move to separate file with step views

2. **Extract Common Components:**
   - `SettingsComponents.swift` (80 lines) - Reusable setting components
   - `SettingsDocument.swift` (25 lines) - Move to separate file

**Result:** 5 files averaging ~200 lines each

### 2. ActivityMonitorView.swift (711 lines)
**Current Structure:**
- ActivityMonitorView (48 lines)
- HeaderView (59 lines)
- 4 Tab Views (OverviewTab, SessionsTab, LogsTab, PerformanceTab)
- 12 Component Views (StatItem, Cards, Toolbars, etc.)

**Refactoring Plan:**
1. **Create Tab-Specific Files:**
   - `ActivityOverviewTab.swift` (150 lines) - OverviewTab + related components
   - `ActivitySessionsTab.swift` (120 lines) - SessionsTab + SessionDetailCard
   - `ActivityLogsTab.swift` (150 lines) - LogsTab + LogsToolbar + LogEntryView
   - `ActivityPerformanceTab.swift` (180 lines) - PerformanceTab + Charts + NetworkStats

2. **Shared Components:**
   - `ActivityComponents.swift` (110 lines) - HeaderView + StatItem + InfoRow + StatusRow

**Result:** 5 files averaging ~140 lines each

### 3. MenuBarView.swift (510 lines)
**Current Structure:**
- MenuBarView (52 lines)
- 12 Component Views (HeaderSection, ServerStatus, QuickActions, etc.)

**Refactoring Plan:**
1. **Group by Functionality:**
   - `MenuBarView.swift` (80 lines) - Main view + basic structure
   - `MenuBarServerSection.swift` (150 lines) - ServerStatusSection + StartStopButton
   - `MenuBarActionsSection.swift` (140 lines) - QuickActionsSection + QuickActionButton
   - `MenuBarSessionsSection.swift` (140 lines) - ActiveSessionsSection + SessionRow

**Result:** 4 files averaging ~125 lines each

### 4. ServerManagerProcess.swift (530 lines) 
**Current Structure:**
- Server Process Management (145 lines)
- Helper Methods (170 lines) 
- Executable Discovery (90 lines)
- Executable Discovery Helpers (125 lines)

**Refactoring Plan:**
1. **Split by Responsibility:**
   - `ServerManagerProcess.swift` (180 lines) - Core process management + validation
   - `ServerExecutableDiscovery.swift` (180 lines) - All executable finding logic
   - `ServerEnvironmentSetup.swift` (170 lines) - Environment + directory + command setup

**Result:** 3 files averaging ~175 lines each

## Implementation Priority

### Phase 1: Critical Fix (SettingsView.swift - 1050 lines)
**Priority: HIGH** - This is the only "serious" violation causing CI failure

1. Create `Views/Settings/` directory
2. Split SecuritySettingsView into 3 files
3. Extract common components
4. Update imports and references

### Phase 2: Large Views (ActivityMonitorView.swift - 711 lines)
**Priority: MEDIUM**

1. Create `Views/ActivityMonitor/` directory  
2. Split into tab-specific files
3. Extract shared components

### Phase 3: Medium Files (MenuBarView.swift - 510 lines)
**Priority: MEDIUM**

1. Create `Views/MenuBar/` directory
2. Split by functional sections

### Phase 4: Models (ServerManagerProcess.swift - 530 lines)
**Priority: LOW** - Still functional, just a warning

1. Create `Models/ServerManager/` directory
2. Split by responsibility areas

## Directory Structure After Refactoring

```
Views/
├── Settings/
│   ├── SettingsView.swift                 (~25 lines)
│   ├── GeneralSettingsView.swift          (~205 lines)
│   ├── ServerSettingsView.swift           (~93 lines)
│   ├── SecuritySettingsView.swift         (~120 lines)
│   ├── TunnelSettingsView.swift           (~120 lines)
│   ├── NgrokSetupView.swift               (~130 lines)
│   ├── AdvancedSettingsView.swift         (~55 lines)
│   ├── SettingsComponents.swift           (~80 lines)
│   └── SettingsDocument.swift             (~25 lines)
├── ActivityMonitor/
│   ├── ActivityMonitorView.swift          (~48 lines)
│   ├── ActivityOverviewTab.swift          (~150 lines)
│   ├── ActivitySessionsTab.swift          (~120 lines)  
│   ├── ActivityLogsTab.swift              (~150 lines)
│   ├── ActivityPerformanceTab.swift       (~180 lines)
│   └── ActivityComponents.swift           (~110 lines)
├── MenuBar/
│   ├── MenuBarView.swift                  (~80 lines)
│   ├── MenuBarServerSection.swift         (~150 lines)
│   ├── MenuBarActionsSection.swift        (~140 lines)
│   └── MenuBarSessionsSection.swift       (~140 lines)
└── [Other existing views...]

Models/
├── ServerManager/
│   ├── ServerManagerProcess.swift         (~180 lines)
│   ├── ServerExecutableDiscovery.swift    (~180 lines)
│   └── ServerEnvironmentSetup.swift       (~170 lines)
└── [Other existing models...]
```

## Implementation Steps

### For Each File Split:
1. **Create new directory** (if needed)
2. **Extract code sections** maintaining all functionality
3. **Update imports** in new files
4. **Update references** in existing files  
5. **Test compilation** after each split
6. **Run SwiftLint** to verify line counts
7. **Commit changes** with descriptive messages

### Validation:
- All files under 400 lines
- No functionality lost
- Build succeeds
- SwiftLint passes
- No circular imports

## Expected Outcome
- **From**: 5 serious violations (4 files > 400 lines, 1 type > 250 lines)
- **To**: 0 violations - all files under 400 lines
- **Total Files**: ~18 focused files instead of 4 large files
- **Maintainability**: Significantly improved
- **CI**: Passes SwiftLint checks

## Risk Mitigation
- Split one file at a time
- Test compilation after each split
- Maintain git history with atomic commits
- Keep backup of working state
- Use Xcode refactoring tools where possible

This plan will resolve all SwiftLint file length violations while improving code organization and maintainability.