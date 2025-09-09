//
//  RequirementsTracker.swift
//  AICLICompanion
//
//  Tracks and manages project requirements during planning
//

import Foundation
import SwiftUI

class RequirementsTracker: ObservableObject {
    // MARK: - Properties
    
    @Published var requirements: [String: [Requirement]] = [:]
    @Published var totalCount: Int = 0
    @Published var completedCount: Int = 0
    @Published var criticalGaps: [Requirement] = []
    
    private let domains = [
        "database",
        "api",
        "ui_ux",
        "auth",
        "performance",
        "deployment",
        "testing"
    ]
    
    // MARK: - Public Methods
    
    /// Add a requirement
    func addRequirement(_ requirement: Requirement) {
        if requirements[requirement.domain] == nil {
            requirements[requirement.domain] = []
        }
        
        // Check if requirement already exists
        if !requirements[requirement.domain]!.contains(where: { $0.id == requirement.id }) {
            requirements[requirement.domain]!.append(requirement)
            updateCounts()
        }
    }
    
    /// Remove a requirement
    func removeRequirement(_ requirement: Requirement) {
        guard let domainReqs = requirements[requirement.domain],
              let index = domainReqs.firstIndex(where: { $0.id == requirement.id }) else {
            return
        }
        
        requirements[requirement.domain]?.remove(at: index)
        updateCounts()
    }
    
    /// Toggle requirement completion
    func toggleRequirement(_ requirement: Requirement) {
        guard let domainReqs = requirements[requirement.domain],
              let index = domainReqs.firstIndex(where: { $0.id == requirement.id }) else {
            return
        }
        
        requirements[requirement.domain]?[index].isCompleted.toggle()
        updateCounts()
    }
    
    /// Get requirements for a domain
    func requirementsForDomain(_ domain: String) -> [Requirement] {
        return requirements[domain] ?? []
    }
    
    /// Get completion percentage
    func completionPercentage() -> Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount) * 100
    }
    
    /// Get domain completion
    func domainCompletion(_ domain: String) -> Double {
        let domainReqs = requirementsForDomain(domain)
        guard !domainReqs.isEmpty else { return 0 }
        
        let completed = domainReqs.filter { $0.isCompleted }.count
        return Double(completed) / Double(domainReqs.count) * 100
    }
    
    /// Clear all requirements
    func clearAll() {
        requirements.removeAll()
        totalCount = 0
        completedCount = 0
        criticalGaps.removeAll()
    }
    
    /// Import requirements from validation
    func importFromValidation(gaps: [RequirementGap], checklist: [ChecklistItem]) {
        // Clear existing
        clearAll()
        
        // Import gaps as requirements
        for gap in gaps {
            let requirement = Requirement(
                domain: gap.domain,
                name: gap.item,
                description: gap.description,
                priority: RequirementPriority(from: gap.priority),
                isCompleted: false
            )
            addRequirement(requirement)
            
            if gap.priority == "critical" {
                criticalGaps.append(requirement)
            }
        }
        
        // Import checklist items
        for item in checklist {
            let requirement = Requirement(
                domain: item.domain,
                name: item.item,
                description: item.description,
                priority: RequirementPriority(from: item.priority),
                isCompleted: item.completed
            )
            addRequirement(requirement)
        }
    }
    
    /// Export as markdown
    func exportAsMarkdown() -> String {
        var markdown = "# Project Requirements\n\n"
        markdown += "**Total Requirements**: \(totalCount)\n"
        markdown += "**Completed**: \(completedCount) (\(Int(completionPercentage()))%)\n\n"
        
        for domain in domains {
            let domainReqs = requirementsForDomain(domain)
            guard !domainReqs.isEmpty else { continue }
            
            markdown += "## \(domain.replacingOccurrences(of: "_", with: " ").capitalized)\n\n"
            
            // Group by priority
            let critical = domainReqs.filter { $0.priority == .critical }
            let high = domainReqs.filter { $0.priority == .high }
            let medium = domainReqs.filter { $0.priority == .medium }
            let low = domainReqs.filter { $0.priority == .low }
            
            for (priority, reqs) in [
                ("Critical", critical),
                ("High", high),
                ("Medium", medium),
                ("Low", low)
            ] {
                if !reqs.isEmpty {
                    markdown += "### \(priority) Priority\n\n"
                    for req in reqs {
                        let checkbox = req.isCompleted ? "[x]" : "[ ]"
                        markdown += "- \(checkbox) **\(req.name)**: \(req.description)\n"
                    }
                    markdown += "\n"
                }
            }
        }
        
        return markdown
    }
    
    // MARK: - Private Methods
    
    private func updateCounts() {
        totalCount = requirements.values.flatMap { $0 }.count
        completedCount = requirements.values.flatMap { $0 }.filter { $0.isCompleted }.count
    }
}

// MARK: - Supporting Types

struct Requirement: Identifiable, Equatable {
    let id = UUID()
    let domain: String
    let name: String
    let description: String
    let priority: RequirementPriority
    var isCompleted: Bool
    var notes: String = ""
    
    static func == (lhs: Requirement, rhs: Requirement) -> Bool {
        lhs.id == rhs.id
    }
}

enum RequirementPriority: String, CaseIterable {
    case critical = "critical"
    case high = "high"
    case medium = "medium"
    case low = "low"
    
    init(from string: String) {
        self = RequirementPriority(rawValue: string.lowercased()) ?? .medium
    }
    
    var color: Color {
        switch self {
        case .critical: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .gray
        }
    }
    
    var icon: String {
        switch self {
        case .critical: return "exclamationmark.triangle.fill"
        case .high: return "exclamationmark.circle.fill"
        case .medium: return "info.circle.fill"
        case .low: return "circle.fill"
        }
    }
}