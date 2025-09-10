//
//  PlanningValidator.swift
//  AICLICompanion
//
//  Planning validation service for requirement analysis
//

import Foundation
import Combine
import SwiftUI

@MainActor
class PlanningValidator: ObservableObject {
    // MARK: - Properties
    
    @Published var sessionId: String?
    @Published var projectType: ProjectType = .webApp
    @Published var readinessScore: Int = 0
    @Published var readinessLevel: InternalReadinessLevel = .insufficient
    @Published var domainScores: [InternalDomainScore] = []
    @Published var gaps: [RequirementGap] = []
    @Published var checklist: [ChecklistItem] = []
    @Published var suggestions: [String] = []
    @Published var isValidating = false
    @Published var validationError: String?
    
    private let networkService = NetworkService.shared
    private var cancellables = Set<AnyCancellable>()
    private var conversationHistory: [Message] = []
    
    // MARK: - Initialization
    
    init() {
        setupSubscriptions()
    }
    
    // MARK: - Public Methods
    
    /// Initialize a new validation session
    func initializeSession(projectType: ProjectType) async {
        sessionId = UUID().uuidString
        self.projectType = projectType
        conversationHistory.removeAll()
        
        do {
            let response = try await networkService.post(
                endpoint: "/api/validation/session",
                body: [
                    "sessionId": sessionId ?? "",
                    "projectType": projectType.rawValue
                ]
            )
            
            if let data = response as? [String: Any],
               let success = data["success"] as? Bool,
               success {
                print("✅ Validation session initialized")
            }
        } catch {
            validationError = "Failed to initialize validation session: \(error.localizedDescription)"
            print("❌ \(validationError ?? "")")
        }
    }
    
    /// Analyze a message for requirements
    func analyzeMessage(_ message: Message) async {
        conversationHistory.append(message)
        
        do {
            let response = try await networkService.post(
                endpoint: "/api/validation/analyze",
                body: [
                    "message": [
                        "id": message.id.uuidString,
                        "content": message.content
                    ]
                ]
            )
            
            if let data = response as? [String: Any],
               let requirements = data["requirements"] as? [[String: Any]] {
                print("📊 Found \(requirements.count) requirements in message")
            }
        } catch {
            print("⚠️ Failed to analyze message: \(error.localizedDescription)")
        }
    }
    
    /// Validate entire conversation
    func validateConversation() async {
        isValidating = true
        validationError = nil
        
        let messages = conversationHistory.map { message in
            ["content": message.content]
        }
        
        do {
            let response = try await networkService.post(
                endpoint: "/api/validation/validate",
                body: [
                    "projectType": projectType.rawValue,
                    "messages": messages
                ]
            )
            
            if let data = response as? [String: Any],
               let validation = data["validation"] as? [String: Any] {
                processValidationResponse(validation)
            }
        } catch {
            validationError = "Validation failed: \(error.localizedDescription)"
            print("❌ \(validationError ?? "")")
        }
        
        isValidating = false
    }
    
    /// Update checklist item completion status
    func updateChecklistItem(_ item: ChecklistItem, completed: Bool) async {
        guard let index = checklist.firstIndex(where: { $0.id == item.id }) else { return }
        
        checklist[index].completed = completed
        
        do {
            let response = try await networkService.post(
                endpoint: "/api/validation/checklist/\(item.id)/complete",
                body: [
                    "sessionId": sessionId ?? "",
                    "completed": completed
                ]
            )
            
            if let data = response as? [String: Any],
               let success = data["success"] as? Bool,
               success {
                print("✅ Checklist item updated")
            }
        } catch {
            print("⚠️ Failed to update checklist item: \(error.localizedDescription)")
            // Revert the change
            checklist[index].completed = !completed
        }
    }
    
    /// Get comprehensive validation report
    func getReport() async -> ValidationReport? {
        do {
            let response = try await networkService.get(
                endpoint: "/api/validation/report?sessionId=\(sessionId ?? "")"
            )
            
            if let data = response as? [String: Any],
               let report = data["report"] as? [String: Any] {
                return parseValidationReport(report)
            }
        } catch {
            print("❌ Failed to get validation report: \(error.localizedDescription)")
        }
        
        return nil
    }
    
    // MARK: - Private Methods
    
    private func setupSubscriptions() {
        // Subscribe to readiness score changes
        $readinessScore
            .sink { [weak self] score in
                self?.updateReadinessLevel(score: score)
            }
            .store(in: &cancellables)
    }
    
    private func updateReadinessLevel(score: Int) {
        switch score {
        case 90...100:
            readinessLevel = .ready
        case 70...89:
            readinessLevel = .partial
        case 50...69:
            readinessLevel = .incomplete
        default:
            readinessLevel = .insufficient
        }
    }
    
    private func processValidationResponse(_ validation: [String: Any]) {
        // Update readiness score
        if let score = validation["readinessScore"] as? Int {
            readinessScore = score
        }
        
        // Update domain scores
        if let domains = validation["domainScores"] as? [[String: Any]] {
            domainScores = domains.compactMap { domain in
                guard let name = domain["domain"] as? String,
                      let score = domain["score"] as? Int else { return nil }
                
                return InternalDomainScore(
                    domain: name,
                    score: score,
                    icon: domainIcon(for: name)
                )
            }
        }
        
        // Update gaps
        if let gapList = validation["gaps"] as? [[String: Any]] {
            gaps = gapList.compactMap { gap in
                guard let domain = gap["domain"] as? String,
                      let item = gap["item"] as? String,
                      let priority = gap["priority"] as? String,
                      let description = gap["description"] as? String else { return nil }
                
                return RequirementGap(
                    domain: domain,
                    item: item,
                    priority: priority,
                    description: description
                )
            }
        }
        
        // Update checklist
        if let checklistData = validation["checklist"] as? [[String: Any]] {
            checklist = checklistData.compactMap { item in
                guard let id = item["id"] as? String,
                      let domain = item["domain"] as? String,
                      let itemText = item["item"] as? String,
                      let priority = item["priority"] as? String,
                      let description = item["description"] as? String else { return nil }
                
                return ChecklistItem(
                    id: id,
                    domain: domain,
                    item: itemText,
                    priority: priority,
                    description: description,
                    completed: item["completed"] as? Bool ?? false,
                    notes: item["notes"] as? String ?? ""
                )
            }
        }
        
        // Update suggestions
        if let suggestionList = validation["suggestions"] as? [String] {
            suggestions = suggestionList
        }
    }
    
    private func parseValidationReport(_ report: [String: Any]) -> ValidationReport {
        ValidationReport(
            sessionId: sessionId ?? "",
            projectType: projectType.rawValue,
            readinessScore: report["readinessScore"] as? Int ?? 0,
            readinessLevel: readinessLevel.rawValue,
            domainScores: Dictionary(
                uniqueKeysWithValues: domainScores.map { ($0.domain, $0.score) }
            ),
            totalRequirements: report["totalRequirements"] as? Int ?? 0,
            completedRequirements: report["completedRequirements"] as? Int ?? 0,
            gaps: gaps.map { $0.description },
            suggestions: suggestions,
            timestamp: Date()
        )
    }
    
    private func domainIcon(for domain: String) -> String {
        switch domain.lowercased() {
        case "database": return "🗄️"
        case "api": return "🔌"
        case "ui_ux": return "🎨"
        case "auth": return "🔐"
        case "performance": return "⚡"
        case "deployment": return "🚀"
        default: return "📋"
        }
    }
}

// MARK: - Supporting Types

enum InternalReadinessLevel: String {
    case ready
    case partial
    case incomplete
    case insufficient
    
    var label: String {
        switch self {
        case .ready: return "Ready to Build"
        case .partial: return "Mostly Ready"
        case .incomplete: return "Needs More Planning"
        case .insufficient: return "Insufficient Planning"
        }
    }
    
    var icon: String {
        switch self {
        case .ready: return "✅"
        case .partial: return "🟡"
        case .incomplete: return "🟠"
        case .insufficient: return "🔴"
        }
    }
    
    var color: Color {
        switch self {
        case .ready: return .green
        case .partial: return .yellow
        case .incomplete: return .orange
        case .insufficient: return .red
        }
    }
    
    var description: String {
        switch self {
        case .ready: return "Requirements are comprehensive"
        case .partial: return "Most requirements captured"
        case .incomplete: return "Major gaps in requirements"
        case .insufficient: return "Need more planning"
        }
    }
}

struct InternalDomainScore: Identifiable {
    let id = UUID()
    let domain: String
    let score: Int
    let icon: String
    
    var displayName: String {
        domain.replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
    
    var scoreColor: Color {
        switch score {
        case 80...100: return .green
        case 60...79: return .yellow
        case 40...59: return .orange
        default: return .red
        }
    }
}

struct RequirementGap: Identifiable {
    let id = UUID()
    let domain: String
    let item: String
    let priority: String
    let description: String
    
    var priorityColor: Color {
        switch priority {
        case "critical": return .red
        case "high": return .orange
        case "medium": return .yellow
        default: return .gray
        }
    }
}

struct ChecklistItem: Identifiable {
    let id: String
    let domain: String
    let item: String
    let priority: String
    let description: String
    var completed: Bool
    var notes: String
}

struct ValidationReport {
    let sessionId: String
    let projectType: String
    let readinessScore: Int
    let readinessLevel: String
    let domainScores: [String: Int]
    let totalRequirements: Int
    let completedRequirements: Int
    let gaps: [String]
    let suggestions: [String]
    let timestamp: Date
}

// MARK: - Project Type

enum ProjectType: String, CaseIterable {
    case webApp = "web_app"
    case mobileApp = "mobile_app"
    case api = "api"
    case library = "library"
    case cli = "cli"
    case other = "other"
    
    var displayName: String {
        switch self {
        case .webApp: return "Web Application"
        case .mobileApp: return "Mobile App"
        case .api: return "API Service"
        case .library: return "Library/Package"
        case .cli: return "CLI Tool"
        case .other: return "Other"
        }
    }
}
