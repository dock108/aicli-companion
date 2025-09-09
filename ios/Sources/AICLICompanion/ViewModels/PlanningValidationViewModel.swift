//
//  PlanningValidationViewModel.swift
//  AICLICompanion
//
//  Created on 2025-09-04.
//

import Foundation
import SwiftUI
import Combine

// MARK: - Models

struct PlanningDomainScore: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let score: Int
    let confidence: Int
    let keywordMatches: Int
    let foundRequirements: [String]
    let missingRequirements: [String]
}

struct Blocker: Identifiable {
    let id = UUID()
    let severity: BlockerSeverity
    let domain: String
    let message: String
    let resolution: String
}

enum BlockerSeverity {
    case critical
    case high
    case medium
    case low
}

struct Suggestion: Identifiable {
    let id = UUID()
    let priority: SuggestionPriority
    let icon: String
    let message: String
    let action: String
}

enum SuggestionPriority {
    case high
    case medium
    case low
}

struct ActionItem: Identifiable {
    let id = UUID()
    let priority: Int
    let category: String
    let icon: String
    let action: String
    let impact: String
    let effort: String
}

// MARK: - View Model

@MainActor
class PlanningValidationViewModel: ObservableObject {
    // Scores and analysis
    @Published var overallScore: Int = 0
    @Published var readinessLevel: ReadinessLevel = .notReady
    @Published var domainScores: [PlanningDomainScore] = []
    @Published var blockers: [Blocker] = []
    @Published var suggestions: [Suggestion] = []
    @Published var actionItems: [ActionItem] = []
    @Published var analysisConfidence: Int = 0
    
    // State
    @Published var isAnalyzing = false
    @Published var lastAnalysisDate: Date?
    @Published var currentConversation: String = ""
    
    private let aicliService = AICLIService.shared
    private var cancellables = Set<AnyCancellable>()
    
    var scoreColor: Color {
        switch overallScore {
        case 90...100: return .green
        case 75...89: return Color.green.opacity(0.8)
        case 60...74: return .yellow
        case 40...59: return .orange
        default: return .red
        }
    }
    
    var hasActionItems: Bool {
        !actionItems.isEmpty
    }
    
    init() {
        setupMockData() // For development/preview
    }
    
    func analyzeCurrentConversation() async {
        isAnalyzing = true
        
        await MainActor.run {
            // Clear previous results during analysis
            self.domainScores = []
            self.blockers = []
            self.suggestions = []
            self.actionItems = []
        }
        
        // Get project info from current context
        let projectPath = ProjectStateManager.shared.currentProject?.path
        let projectType = getProjectType(from: ProjectStateManager.shared.currentProject)
        
        // Analyze the current conversation content
        await withCheckedContinuation { continuation in
            aicliService.validatePlanningDocument(
                content: currentConversation,
                projectType: projectType,
                projectPath: projectPath
            ) { [weak self] result in
                Task { @MainActor in
                    guard let self = self else {
                        continuation.resume()
                        return
                    }
                    
                    switch result {
                    case .success(let response):
                        self.processValidationResponse(response)
                        self.lastAnalysisDate = Date()
                    case .failure(let error):
                        print("Analysis error: \(error)")
                        // Fall back to mock data on error
                        await self.analyzeMockConversation()
                    }
                    
                    self.isAnalyzing = false
                    continuation.resume()
                }
            }
        }
    }
    
    private func getProjectType(from project: Project?) -> String {
        // Determine project type based on project metadata or default
        if let type = project?.type {
            switch type.lowercased() {
            case "web", "webapp": return "web-app"
            case "api", "service": return "api-service"
            case "mobile", "ios", "android": return "mobile-app"
            case "cli", "tool": return "cli-tool"
            default: return "general"
            }
        }
        return "general"
    }
    
    private func processValidationResponse(_ response: PlanningValidationResponse) {
        let validation = response.validation
        
        // Update scores
        overallScore = validation.overallScore
        analysisConfidence = validation.confidence
        
        // Convert readiness level
        readinessLevel = mapReadinessLevel(validation.readinessLevel)
        
        // Convert domain scores
        domainScores = validation.domains.map { domain in
            PlanningDomainScore(
                name: domain.name,
                icon: domain.icon,
                score: domain.score,
                confidence: validation.confidence,
                keywordMatches: domain.keywordMatches,
                foundRequirements: domain.foundRequirements,
                missingRequirements: domain.missingRequirements
            )
        }
        
        // Convert blockers
        blockers = validation.blockers.map { blocker in
            Blocker(
                severity: mapBlockerSeverity(blocker.severity),
                domain: blocker.domain,
                message: blocker.message,
                resolution: blocker.resolution ?? ""
            )
        }
        
        // Convert suggestions
        suggestions = validation.suggestions.map { suggestion in
            Suggestion(
                priority: mapSuggestionPriority(suggestion.priority),
                icon: "💡",
                message: suggestion.message,
                action: suggestion.action ?? ""
            )
        }
        
        // Convert action items
        actionItems = validation.actionItems.map { item in
            ActionItem(
                priority: item.priority,
                category: item.category,
                icon: item.icon,
                action: item.action,
                impact: item.impact ?? "Medium",
                effort: item.effort ?? "Moderate"
            )
        }
    }
    
    private func mapReadinessLevel(_ level: ReadinessLevelResponse) -> ReadinessLevel {
        switch level.level {
        case "production-ready": return .ready
        case "development-ready": return .almostReady
        case "planning-needed": return .needsWork
        default: return .notReady
        }
    }
    
    private func mapBlockerSeverity(_ severity: String) -> BlockerSeverity {
        switch severity.lowercased() {
        case "critical": return .critical
        case "high": return .high
        case "medium": return .medium
        case "low": return .low
        default: return .medium
        }
    }
    
    private func mapSuggestionPriority(_ priority: String) -> SuggestionPriority {
        switch priority.lowercased() {
        case "high": return .high
        case "medium": return .medium
        case "low": return .low
        default: return .medium
        }
    }
    
    func analyzeMockConversation() async {
        // Simulate API delay
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Set mock analysis results
        overallScore = 73
        analysisConfidence = 68
        
        readinessLevel = ReadinessLevel.prototypeReady
        
        domainScores = [
            PlanningDomainScore(
                name: "Database Design",
                icon: "🗄️",
                score: 85,
                confidence: 90,
                keywordMatches: 12,
                foundRequirements: [
                    "Table Definitions",
                    "Relationships",
                    "Constraints"
                ],
                missingRequirements: [
                    "Indexes",
                    "Migration Strategy"
                ]
            ),
            PlanningDomainScore(
                name: "API Design",
                icon: "🔌",
                score: 70,
                confidence: 75,
                keywordMatches: 8,
                foundRequirements: [
                    "Endpoints",
                    "Authentication"
                ],
                missingRequirements: [
                    "Rate Limiting",
                    "Error Handling"
                ]
            ),
            PlanningDomainScore(
                name: "UI/UX Design",
                icon: "🎨",
                score: 45,
                confidence: 50,
                keywordMatches: 3,
                foundRequirements: [
                    "User Flows"
                ],
                missingRequirements: [
                    "Wireframes",
                    "Component Specs",
                    "Responsive Design"
                ]
            ),
            PlanningDomainScore(
                name: "Security",
                icon: "🔒",
                score: 90,
                confidence: 85,
                keywordMatches: 10,
                foundRequirements: [
                    "Authentication Method",
                    "Data Encryption",
                    "Input Validation"
                ],
                missingRequirements: [
                    "Security Headers"
                ]
            ),
            PlanningDomainScore(
                name: "Performance",
                icon: "⚡",
                score: 60,
                confidence: 55,
                keywordMatches: 4,
                foundRequirements: [
                    "Response Time Targets"
                ],
                missingRequirements: [
                    "Caching Strategy",
                    "Monitoring Metrics"
                ]
            ),
            PlanningDomainScore(
                name: "Deployment",
                icon: "🚀",
                score: 80,
                confidence: 80,
                keywordMatches: 7,
                foundRequirements: [
                    "Deployment Target",
                    "CI/CD Pipeline"
                ],
                missingRequirements: [
                    "Rollback Strategy"
                ]
            ),
            PlanningDomainScore(
                name: "Testing",
                icon: "🧪",
                score: 95,
                confidence: 95,
                keywordMatches: 15,
                foundRequirements: [
                    "Unit Test Coverage",
                    "Integration Tests",
                    "E2E Scenarios"
                ],
                missingRequirements: []
            ),
            PlanningDomainScore(
                name: "Business Logic",
                icon: "💼",
                score: 75,
                confidence: 70,
                keywordMatches: 9,
                foundRequirements: [
                    "Core Features",
                    "User Stories"
                ],
                missingRequirements: [
                    "Business Rules",
                    "Validation Logic"
                ]
            )
        ]
        
        // Generate blockers
        blockers = domainScores.compactMap { domain in
            if domain.score < 50 {
                return Blocker(
                    severity: domain.score < 30 ? .critical : .high,
                    domain: domain.name,
                    message: "\(domain.name) is severely lacking",
                    resolution: "Define \(domain.missingRequirements.prefix(2).joined(separator: ", "))"
                )
            }
            return nil
        }
        
        // Generate suggestions
        suggestions = [
            Suggestion(
                priority: .high,
                icon: "🎨",
                message: "UI/UX Design needs more detail - only 45% complete",
                action: "Create wireframes for main screens and define component specifications"
            ),
            Suggestion(
                priority: .medium,
                icon: "⚡",
                message: "Performance optimization not fully specified",
                action: "Define caching strategy and monitoring metrics"
            ),
            Suggestion(
                priority: .low,
                icon: "✅",
                message: "Good progress! Focus on high-priority gaps",
                action: "Review UI/UX requirements and complete missing specifications"
            )
        ]
        
        // Generate action items
        actionItems = [
            ActionItem(
                priority: 1,
                category: "UI/UX",
                icon: "🎨",
                action: "Create wireframes for dashboard",
                impact: "high",
                effort: "medium"
            ),
            ActionItem(
                priority: 2,
                category: "UI/UX",
                icon: "🎨",
                action: "Define component specifications",
                impact: "high",
                effort: "medium"
            ),
            ActionItem(
                priority: 3,
                category: "Performance",
                icon: "⚡",
                action: "Design caching strategy",
                impact: "medium",
                effort: "low"
            ),
            ActionItem(
                priority: 4,
                category: "API",
                icon: "🔌",
                action: "Add rate limiting specifications",
                impact: "medium",
                effort: "low"
            ),
            ActionItem(
                priority: 5,
                category: "Database",
                icon: "🗄️",
                action: "Define index strategy",
                impact: "medium",
                effort: "low"
            )
        ]
    }
    
    private func setupMockData() {
        // Initial mock data for previews
        overallScore = 0
        readinessLevel = .notReady
        domainScores = []
        blockers = []
        suggestions = []
        actionItems = []
        analysisConfidence = 0
    }
    
    func refreshAnalysis() async {
        await analyzeCurrentConversation()
    }
    
    func updateConversationContent(_ content: String) {
        currentConversation = content
    }
    
    func analyzeProjectDirectory(path: String) async {
        isAnalyzing = true
        
        await withCheckedContinuation { continuation in
            aicliService.analyzeDirectory(path: path) { [weak self] result in
                Task { @MainActor in
                    guard let self = self else {
                        continuation.resume()
                        return
                    }
                    
                    switch result {
                    case .success(let response):
                        // Process directory analysis
                        if let validation = response.analysis.validation {
                            // Update scores from existing plan.md
                            self.overallScore = validation.overallScore
                            self.readinessLevel = self.mapReadinessLevel(validation.readinessLevel)
                        }
                        self.lastAnalysisDate = Date()
                        
                    case .failure(let error):
                        print("Directory analysis error: \(error)")
                    }
                    
                    self.isAnalyzing = false
                    continuation.resume()
                }
            }
        }
    }
    
    func saveAndValidatePlan(projectPath: String, content: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            aicliService.saveAndValidatePlan(
                projectPath: projectPath,
                content: content
            ) { result in
                switch result {
                case .success(let response):
                    print("Plan saved successfully: \(response.result.filePath)")
                    continuation.resume(returning: true)
                case .failure(let error):
                    print("Failed to save plan: \(error)")
                    continuation.resume(returning: false)
                }
            }
        }
    }
}
