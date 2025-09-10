# Issue #35: Project Creation & Template Management System

**Priority**: High  
**Component**: iOS App - Project Management UI (Server: File Operations)  
**Beta Blocker**: No  
**Discovered**: 2025-08-31  
**Status**: New  
**Resolved**: [YYYY-MM-DD if resolved]

## Problem Description

Currently, users must manually create project folders and configuration files outside the iOS app. We need an integrated project creation system where the iOS app provides all UI for project management, while the server handles file operations and template storage. The system needs:

1. **In-App Project Creation**: Create new projects directly from the iOS app
2. **Template Generation**: Auto-generate professional template files (CLAUDE.md, plan.md, issues/)
3. **Project Management**: Browse, switch, and organize projects
4. **Template Customization**: Edit and version templates for different project types

This shifts the development workflow "further left" into the app, providing a complete development environment for production-grade applications.

## Expected Behavior

**Project Creation Flow:**
1. User taps "New Project" in iOS app
2. Wizard prompts for:
   - Project name
   - Project type (Web App, API, Mobile App, CLI Tool, etc.)
   - Technology stack
   - Team size (affects template complexity)
3. Server creates project folder structure
4. Auto-generates template files:
   - `CLAUDE.md` - AI guidelines and persistence rules
   - `plan.md` - TDD planning document
   - `issues/template.md` - Issue template
   - `README.md` - Project documentation
   - `.github/workflows/` - CI/CD templates (optional)
5. Opens project in chat with planning session

**Project Management:**
- Browse existing projects
- Switch between projects (maintains context)
- Archive/delete old projects
- Export project templates
- Import shared templates

**Template Features:**
- Version control (v1.0.0 system)
- Project-type specific templates
- Customizable sections
- Variable substitution ({{project_name}}, {{tech_stack}}, etc.)

## Investigation Areas

1. **File System Management**:
   - Server-side project folder creation
   - Template file generation
   - Permission handling
   - Storage organization

2. **Template System Design**:
   - Template structure and format
   - Variable substitution engine
   - Version management
   - Default vs. custom templates

3. **iOS UI/UX**:
   - Project creation wizard design
   - Project browser interface
   - Template editor component
   - Project switching flow

## Solution Approach

### 1. Server-Side Project Management

**New: `server/src/services/project-creator.js`**
```javascript
class ProjectCreator {
  async createProject(config) {
    // Create project directory
    // Generate folder structure
    // Apply templates
    // Initialize git (optional)
  }
  
  async listProjects(userId) {
    // Scan projects directory
    // Return project metadata
  }
  
  async deleteProject(projectId) {
    // Archive or delete project
    // Clean up resources
  }
}
```

**New: `server/src/services/template-generator.js`**
```javascript
class TemplateGenerator {
  async generateTemplates(projectConfig) {
    // Load base templates
    // Apply variable substitution
    // Generate customized files
  }
  
  substituteVariables(template, variables) {
    // Replace {{variables}}
    // Apply conditional sections
  }
  
  versionTemplate(template, version) {
    // Track template versions
    // Support upgrades
  }
}
```

**New: `server/templates/` directory structure**
```
templates/
  base/
    CLAUDE.md.template
    plan.md.template
    README.md.template
  issues/
    template.md
    bug-report.md
    feature-request.md
  project-types/
    web-app/
    mobile-app/
    api-service/
    cli-tool/
  workflows/
    node.yml
    swift.yml
    python.yml
```

### 2. Template Content

**CLAUDE.md.template**
```markdown
# Development Guidelines for {{project_name}}

## Core Principles
1. {{principle_1}}
2. {{principle_2}}
3. {{principle_3}}

## Project Context
- **Type**: {{project_type}}
- **Stack**: {{tech_stack}}
- **Team Size**: {{team_size}}

## Persistence Rules
- Always maintain test coverage above 80%
- Follow existing code patterns
- Document all major decisions

## Current Sprint
{{current_sprint}}

## Known Issues
{{known_issues}}
```

**plan.md.template**
```markdown
# {{project_name}} - Technical Planning Document

## Project Overview
{{project_description}}

## Architecture
### Technology Stack
- **Frontend**: {{frontend_tech}}
- **Backend**: {{backend_tech}}
- **Database**: {{database}}
- **Deployment**: {{deployment_target}}

## Development Phases
### Phase 1: Foundation
- [ ] Project setup
- [ ] Basic architecture
- [ ] Core models

### Phase 2: Features
{{feature_list}}

### Phase 3: Polish
- [ ] Performance optimization
- [ ] Security audit
- [ ] Documentation

## Testing Strategy
{{testing_approach}}
```

### 3. iOS Project Management UI

**New Views:**
```swift
// ProjectCreationWizard.swift
struct ProjectCreationWizard: View {
    @State private var projectName = ""
    @State private var projectType = ProjectType.webApp
    @State private var techStack = TechStack.default
    
    // Multi-step wizard UI
}

// ProjectBrowser.swift
struct ProjectBrowser: View {
    @ObservedObject var projectManager: ProjectManager
    
    // Grid/List view of projects
    // Search and filter
    // Quick actions (open, archive, delete)
}

// TemplateEditor.swift
struct TemplateEditor: View {
    @Binding var template: ProjectTemplate
    
    // Syntax highlighted editor
    // Variable insertion helpers
    // Preview mode
}
```

### 4. API Endpoints

**New endpoints in `server/src/routes/projects.js`**
```
POST /api/projects/create
GET /api/projects/list
GET /api/projects/:id
DELETE /api/projects/:id
PUT /api/projects/:id/archive

GET /api/templates/list
GET /api/templates/:type
POST /api/templates/custom
```

## Files to Create/Modify

**New Server Files:**
```
server/src/services/project-creator.js
server/src/services/template-generator.js
server/src/routes/projects-enhanced.js
server/templates/base/*.template
server/templates/issues/*.md
server/templates/project-types/**/*
server/test/services/project-creator.test.js
server/test/services/template-generator.test.js
```

**New iOS Files:**
```
ios/Sources/AICLICompanion/Services/ProjectManagement/ProjectManager.swift
ios/Sources/AICLICompanion/Services/ProjectManagement/TemplateService.swift
ios/Sources/AICLICompanion/Views/ProjectCreation/ProjectCreationWizard.swift
ios/Sources/AICLICompanion/Views/ProjectCreation/ProjectTypeSelector.swift
ios/Sources/AICLICompanion/Views/ProjectBrowser/ProjectBrowser.swift
ios/Sources/AICLICompanion/Views/ProjectBrowser/ProjectCard.swift
ios/Sources/AICLICompanion/Views/TemplateEditor/TemplateEditor.swift
ios/Sources/AICLICompanion/Models/ProjectTemplate.swift
```

**Modified Files:**
```
ios/Sources/AICLICompanion/Views/ContentView.swift (Add project browser tab)
ios/Sources/AICLICompanion/Services/Chat/ChatViewModel.swift (Project context)
server/src/services/aicli-session-manager.js (Project association)
```

## Testing Requirements

### Unit Tests
- [ ] Project creation logic
- [ ] Template generation with variables
- [ ] Template versioning system
- [ ] Project listing and filtering

### Integration Tests
- [ ] End-to-end project creation
- [ ] Template file generation
- [ ] Project switching in chat
- [ ] File system operations

### Manual Testing
1. Create projects of different types
2. Verify template generation
3. Test template customization
4. Validate project switching
5. Test edge cases (special characters, long names)

## Implementation Checklist

**Phase 1: Core Infrastructure (Week 1)**
- [ ] Create project-creator.js service
- [ ] Implement basic template-generator.js
- [ ] Create base template files
- [ ] Add project creation API endpoint

**Phase 2: Template System (Week 2)**
- [ ] Build complete template library
- [ ] Implement variable substitution
- [ ] Add template versioning
- [ ] Create template tests

**Phase 3: iOS UI (Week 3)**
- [ ] Build ProjectCreationWizard
- [ ] Implement ProjectBrowser
- [ ] Add TemplateEditor
- [ ] Integrate with chat context

**Phase 4: Polish (Week 4)**
- [ ] Add project search/filter
- [ ] Implement template import/export
- [ ] Add project archival
- [ ] Performance optimization

## Success Metrics

- **Creation Speed**: <5 seconds for new project setup
- **Template Quality**: Professional, production-ready templates
- **User Adoption**: 80% of users create projects in-app
- **Template Reuse**: Average 3+ projects per template

## Dependencies

- Issue #34 (Enhanced Auto-Response) - Projects need intelligent automation
- Existing project management infrastructure
- File system access on server

## Related Issues

- **Depends On**: #34 (Enhanced Auto-Response System)
- **Blocks**: #36 (Planning Session Validation Engine)
- **Original**: #34-autonomous-coding-agent-ORIGINAL (Full vision)

## Notes

This issue focuses on the project creation and template management infrastructure. The intelligent automation (#34) and planning validation (#36) are separate concerns that build upon this foundation.

The template system should be extensible to support community templates in the future.

---

**Last Updated**: 2025-08-31  
**Assigned To**: [Unassigned]  
**Labels**: enhancement, project-management, templates