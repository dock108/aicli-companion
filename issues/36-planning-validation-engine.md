# Issue #36: Planning Session Validation Engine

**Priority**: Medium  
**Component**: iOS App - Validation Dashboard (Server: Validation APIs)  
**Beta Blocker**: No  
**Discovered**: 2025-08-31  
**Status**: New  
**Resolved**: [YYYY-MM-DD if resolved]

## Problem Description

When starting a new project in the iOS app, developers often jump into coding without fully defining requirements, leading to rework and technical debt. The iOS app provides the validation dashboard and UI feedback, while the server provides validation logic APIs. We need an intelligent validation engine that:

1. **Analyzes Planning Conversations**: Continuously assess requirement completeness
2. **Identifies Gaps**: Detect missing specifications across all domains
3. **Provides Readiness Scoring**: Give confidence metrics for project readiness
4. **Offers Guided Assistance**: Generate checklists and suggestions for missing items
5. **Supports Override**: Allow proceeding with warnings when deliberately skipping items

This ensures projects start with solid foundations while maintaining developer autonomy.

## Expected Behavior

**Continuous Validation During Planning:**
1. User creates new project and enters planning session
2. System analyzes each message for requirement specifications
3. Real-time assessment of completeness across domains:
   - Database schema and relationships
   - API contracts and endpoints
   - UI/UX specifications
   - Authentication/authorization
   - Performance requirements
   - Deployment architecture
4. Dynamic readiness score updates
5. Contextual suggestions for missing items

**Readiness Assessment Messages:**
- ✅ **Ready**: "All critical requirements identified! Ready to start development."
- ⚠️ **Partial**: "Missing: API authentication flow, database indexes, error handling strategy"
- 🚨 **Incomplete**: "Database schema needs: user-post relationships, cascade rules, indexes"
- 📋 **Checklist**: "Generated 7-item checklist for remaining specifications"
- 🎮 **Override**: "You're flying without instruments here! Missing [items], but let's go if you're feeling adventurous..."

**Smart Gap Detection:**
- Identifies implicit requirements from context
- Suggests commonly forgotten items
- Learns from project type patterns
- Prioritizes critical vs. nice-to-have

## Investigation Areas

1. **Requirement Extraction**:
   - NLP for specification detection
   - Domain-specific pattern recognition
   - Completeness criteria per domain

2. **Scoring Algorithms**:
   - Weighted importance of different requirements
   - Confidence calculations
   - Project-type specific scoring

3. **User Experience**:
   - Non-intrusive validation display
   - Progressive disclosure of gaps
   - Actionable suggestions

## Solution Approach

### 1. Validation Engine Core

**New: `server/src/services/planning-validator.js`**
```javascript
class PlanningValidator {
  constructor() {
    this.domains = [
      'database', 'api', 'ui_ux', 'auth', 
      'performance', 'deployment', 'testing'
    ];
    this.requirements = new Map();
  }
  
  async validateConversation(messages) {
    // Extract requirements from messages
    // Assess completeness per domain
    // Calculate readiness score
    // Generate gap report
  }
  
  calculateReadinessScore() {
    // Weight critical vs optional
    // Consider project type
    // Return 0-100 score
  }
  
  generateChecklist() {
    // List missing requirements
    // Prioritize by importance
    // Provide actionable items
  }
}
```

**New: `server/src/services/requirements-analyzer.js`**
```javascript
class RequirementsAnalyzer {
  extractRequirements(text) {
    // Pattern matching for specifications
    // Entity extraction (tables, endpoints, etc.)
    // Relationship detection
  }
  
  detectDatabaseSchema(messages) {
    // Find table definitions
    // Extract relationships
    // Identify constraints
    // Check for indexes
  }
  
  detectAPIContracts(messages) {
    // Find endpoint definitions
    // Extract request/response formats
    // Identify authentication needs
  }
  
  detectUIRequirements(messages) {
    // Find screen/component mentions
    // Extract user flows
    // Identify interaction patterns
  }
}
```

**New: `server/src/services/readiness-scorer.js`**
```javascript
class ReadinessScorer {
  constructor() {
    this.weights = {
      database: { schema: 0.9, indexes: 0.6, migrations: 0.4 },
      api: { endpoints: 0.9, auth: 0.8, validation: 0.7 },
      ui_ux: { screens: 0.8, flows: 0.7, responsive: 0.5 },
      auth: { strategy: 0.9, roles: 0.7, sessions: 0.6 },
      performance: { targets: 0.6, caching: 0.5, optimization: 0.4 },
      deployment: { environment: 0.8, ci_cd: 0.6, monitoring: 0.5 }
    };
  }
  
  calculateScore(requirements, projectType) {
    // Apply weights based on project type
    // Calculate domain scores
    // Aggregate to overall score
    // Return score with confidence
  }
  
  getReadinessLevel(score) {
    if (score >= 85) return 'ready';
    if (score >= 70) return 'partial';
    if (score >= 50) return 'incomplete';
    return 'insufficient';
  }
}
```

### 2. Validation Rules Configuration

**New: `server/config/validation-rules.json`**
```json
{
  "project_types": {
    "web_app": {
      "required": ["database.schema", "api.endpoints", "ui_ux.screens", "auth.strategy"],
      "recommended": ["performance.targets", "deployment.environment"],
      "optional": ["monitoring", "analytics"]
    },
    "api_service": {
      "required": ["api.endpoints", "database.schema", "auth.strategy"],
      "recommended": ["api.documentation", "rate_limiting"],
      "optional": ["ui_ux"]
    }
  },
  
  "completeness_criteria": {
    "database.schema": {
      "must_have": ["tables", "primary_keys", "relationships"],
      "should_have": ["indexes", "constraints", "migrations"],
      "nice_to_have": ["seed_data", "backup_strategy"]
    }
  }
}
```

### 3. iOS Validation Dashboard

**New Views:**
```swift
// PlanningDashboard.swift
struct PlanningDashboard: View {
    @ObservedObject var validator: PlanningValidator
    
    var body: some View {
        VStack {
            ReadinessScoreCard(score: validator.readinessScore)
            DomainCompleteness(domains: validator.domainScores)
            MissingRequirementsList(gaps: validator.gaps)
            OverrideControls(onOverride: handleOverride)
        }
    }
}

// ReadinessIndicator.swift
struct ReadinessIndicator: View {
    let level: ReadinessLevel
    
    var body: some View {
        HStack {
            Image(systemName: level.icon)
                .foregroundColor(level.color)
            Text(level.message)
            if level == .partial {
                Button("Show Gaps") { showGapAnalysis() }
            }
        }
    }
}

// RequirementsChecklist.swift
struct RequirementsChecklist: View {
    @Binding var requirements: [Requirement]
    
    // Interactive checklist
    // Mark items as complete
    // Add custom requirements
}
```

### 4. Integration with Chat

**Validation During Planning:**
```swift
extension ChatViewModel {
    func analyzeForRequirements(_ message: Message) {
        planningValidator.analyze(message)
        updateReadinessScore()
        
        if shouldShowValidationHint() {
            showInlineHint(validator.currentGaps)
        }
    }
    
    func transitionToImplementation() {
        guard validator.isReady || userOverride else {
            showReadinessWarning()
            return
        }
        startDevelopmentPhase()
    }
}
```

## Files to Create/Modify

**New Server Files:**
```
server/src/services/planning-validator.js
server/src/services/requirements-analyzer.js
server/src/services/readiness-scorer.js
server/src/services/gap-detector.js
server/config/validation-rules.json
server/src/routes/validation.js
server/test/services/planning-validator.test.js
server/test/services/requirements-analyzer.test.js
```

**New iOS Files:**
```
ios/Sources/AICLICompanion/Services/PlanningValidation/PlanningValidator.swift
ios/Sources/AICLICompanion/Services/PlanningValidation/RequirementsTracker.swift
ios/Sources/AICLICompanion/Views/PlanningDashboard/PlanningDashboard.swift
ios/Sources/AICLICompanion/Views/PlanningDashboard/ReadinessScoreCard.swift
ios/Sources/AICLICompanion/Views/PlanningDashboard/RequirementsChecklist.swift
ios/Sources/AICLICompanion/Views/PlanningDashboard/GapAnalysis.swift
ios/Sources/AICLICompanion/Models/RequirementModels.swift
```

**Modified Files:**
```
ios/Sources/AICLICompanion/Views/Chat/ChatView.swift (Add validation UI)
ios/Sources/AICLICompanion/Views/Chat/ViewModels/ChatViewModel.swift (Integration)
server/src/services/websocket-message-handler.js (Real-time validation)
```

## Testing Requirements

### Unit Tests
- [ ] Requirement extraction accuracy
- [ ] Scoring algorithm correctness
- [ ] Gap detection completeness
- [ ] Project-type specific rules

### Integration Tests
- [ ] Real-time validation during chat
- [ ] Checklist generation
- [ ] Override mechanism
- [ ] State persistence

### Manual Testing
1. Plan various project types
2. Verify requirement detection
3. Test readiness scoring accuracy
4. Validate gap suggestions
5. Test override flow

## Implementation Checklist

**Phase 1: Core Analysis (Week 1)**
- [ ] Create requirements-analyzer.js
- [ ] Implement basic pattern matching
- [ ] Build domain-specific extractors
- [ ] Add extraction tests

**Phase 2: Scoring System (Week 2)**
- [ ] Implement readiness-scorer.js
- [ ] Create validation rules config
- [ ] Build gap detection logic
- [ ] Add scoring tests

**Phase 3: Validation Engine (Week 3)**
- [ ] Create planning-validator.js
- [ ] Integrate analyzers and scorers
- [ ] Add checklist generation
- [ ] Build API endpoints

**Phase 4: iOS Integration (Week 4)**
- [ ] Build PlanningDashboard views
- [ ] Integrate with ChatViewModel
- [ ] Add real-time updates
- [ ] Polish UI/UX

## Success Metrics

- **Detection Accuracy**: >85% requirement identification
- **False Positive Rate**: <10% incorrect gap detection
- **User Acceptance**: 70% proceed with validation suggestions
- **Project Success**: 50% reduction in requirement-related rework

## Dependencies

- Issue #35 (Project Creation) - Needs project context for validation
- Issue #34 (Auto-Response) - Can trigger validation checks
- Existing chat infrastructure

## Related Issues

- **Depends On**: #35 (Project Creation & Template Management)
- **Enhances**: #34 (Enhanced Auto-Response System)
- **Original**: #34-autonomous-coding-agent-ORIGINAL (Full vision)

## Future Enhancements

- Machine learning for requirement extraction
- Historical project analysis for better predictions
- Team-specific requirement patterns
- Integration with external requirement management tools

## Notes

This validation engine should be helpful but not annoying. It should feel like a knowledgeable colleague pointing out potential issues, not a gatekeeper blocking progress.

The override mechanism is crucial - developers should always have the freedom to proceed when they disagree with the validation.

---

**Last Updated**: 2025-08-31  
**Assigned To**: [Unassigned]  
**Labels**: enhancement, validation, requirements-analysis, planning