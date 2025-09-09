//
//  ChatViewModel+Validation.swift
//  AICLICompanion
//
//  Extension for planning validation integration
//

import Foundation
import Combine

extension ChatViewModel {
    // MARK: - Planning Validation
    
    // NOTE: This extension requires the following properties to be added to ChatViewModel:
    // @Published var isPlanningMode = false
    // @Published var showValidationDashboard = false
    // @Published var shouldShowValidation = false
    // @Published var showReadinessWarning = false
    // @Published var readinessWarningMessage = ""
    // @Published var userOverrideValidation = false
    // @Published var currentProjectType: ProjectType?
    // let planningValidator = PlanningValidator()
    // let requirementsTracker = RequirementsTracker()
    
    // All methods are temporarily disabled until the properties are added to ChatViewModel
    
    /*
    /// Initialize planning validation for the current session
    func initializePlanningValidation() async {
        guard let projectType = currentProjectType else { return }
        
        await planningValidator.initializeSession(projectType: projectType)
        isPlanningMode = true
    }
    
    /// Analyze message for requirements during planning
    func analyzeForRequirements(_ message: Message) async {
        guard isPlanningMode else { return }
        
        // Send to validator for analysis
        await planningValidator.analyzeMessage(message)
        
        // Update UI if validation dashboard is visible
        if shouldShowValidation {
            await planningValidator.validateConversation()
        }
    }
    
    /// Check if we should show validation hints
    func shouldShowValidationHint() -> Bool {
        guard isPlanningMode else { return false }
        
        // Show hint if score is low or critical gaps exist
        return planningValidator.readinessScore < 60 ||
               planningValidator.gaps.contains(where: { $0.priority == "critical" })
    }
    
    /// Get inline validation hint for current state
    func getValidationHint() -> String? {
        guard isPlanningMode else { return nil }
        
        let score = planningValidator.readinessScore
        let gaps = planningValidator.gaps
        
        if score < 30 {
            return "💡 Need more planning: Consider defining database schema, API endpoints, and UI screens"
        } else if score < 60 {
            let criticalGaps = gaps.filter { $0.priority == "critical" }
            if !criticalGaps.isEmpty {
                return "⚠️ Missing critical requirements: \(criticalGaps.first?.item ?? "Check validation dashboard")"
            }
        } else if score < 80 {
            return "📝 Good progress! A few more requirements needed for complete specification"
        }
        
        return nil
    }
    
    /// Transition from planning to implementation
    func transitionToImplementation() async -> Bool {
        guard isPlanningMode else { return true }
        
        // Validate current conversation
        await planningValidator.validateConversation()
        
        let score = planningValidator.readinessScore
        let level = planningValidator.readinessLevel
        
        // Check if ready to proceed
        if score >= 70 || userOverrideValidation {
            isPlanningMode = false
            showValidationDashboard = false
            
            // Save requirements for reference
            await saveRequirementsSnapshot()
            
            return true
        } else {
            // Show warning
            showReadinessWarning = true
            readinessWarningMessage = """
                Project readiness: \(level.label) (\(score)%)
                
                \(level.description)
                
                Missing \(planningValidator.gaps.count) critical requirements.
                
                Continue anyway?
                """
            return false
        }
    }
    
    /// Save current requirements for reference
    private func saveRequirementsSnapshot() async {
        guard let report = await planningValidator.getReport() else { return }
        
        // Save to project metadata or local storage
        let snapshot = RequirementsSnapshot(
            timestamp: Date(),
            score: report.readinessScore,
            level: report.readinessLevel,
            domainScores: report.domainScores,
            totalRequirements: report.totalRequirements,
            suggestions: report.suggestions
        )
        
        // Store in UserDefaults or project file
        if let encoded = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(encoded, forKey: "requirements_\(currentSessionId ?? "")")
        }
    }
    
    /// Toggle validation dashboard visibility
    func toggleValidationDashboard() {
        showValidationDashboard.toggle()
        
        if showValidationDashboard {
            Task {
                await planningValidator.validateConversation()
            }
        }
    }
    
    /// Export requirements as markdown
    func exportRequirements() -> String {
        let tracker = requirementsTracker
        var markdown = tracker.exportAsMarkdown()
        
        // Add validation report
        markdown += "\n\n## Validation Report\n\n"
        markdown += "**Readiness Score**: \(planningValidator.readinessScore)%\n"
        markdown += "**Readiness Level**: \(planningValidator.readinessLevel.label)\n\n"
        
        // Add gaps
        if !planningValidator.gaps.isEmpty {
            markdown += "### Gaps Identified\n\n"
            for gap in planningValidator.gaps {
                markdown += "- **\(gap.domain)**: \(gap.item) (\(gap.priority))\n"
                markdown += "  - \(gap.description)\n"
            }
        }
        
        // Add suggestions
        if !planningValidator.suggestions.isEmpty {
            markdown += "\n### Suggestions\n\n"
            for suggestion in planningValidator.suggestions {
                markdown += "- \(suggestion)\n"
            }
        }
        
        return markdown
    }
    */
}

// MARK: - Supporting Types

struct RequirementsSnapshot: Codable {
    let timestamp: Date
    let score: Int
    let level: String
    let domainScores: [String: Int]
    let totalRequirements: Int
    let suggestions: [String]
}

// MARK: - ChatViewModel Properties Extension

extension ChatViewModel {
    /// Add these properties to your main ChatViewModel class:
    ///
    /// @Published var isPlanningMode = false
    /// @Published var showValidationDashboard = false
    /// @Published var shouldShowValidation = false
    /// @Published var showReadinessWarning = false
    /// @Published var readinessWarningMessage = ""
    /// @Published var userOverrideValidation = false
    /// @Published var currentProjectType: ProjectType?
    ///
    /// let planningValidator = PlanningValidator()
    /// let requirementsTracker = RequirementsTracker()
}
