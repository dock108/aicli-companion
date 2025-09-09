//
//  PlanningDashboard.swift
//  AICLICompanion
//
//  Dashboard for planning validation and requirement tracking
//

import SwiftUI

struct PlanningDashboard: View {
    @StateObject private var validator = PlanningValidator()
    @StateObject private var tracker = RequirementsTracker()
    @State private var selectedTab = "overview"
    @State private var showingGapDetails = false
    @State private var showingChecklist = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Tab selector
                Picker("View", selection: $selectedTab) {
                    Text("Overview").tag("overview")
                    Text("Requirements").tag("requirements")
                    Text("Gaps").tag("gaps")
                    Text("Checklist").tag("checklist")
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
                // Content
                ScrollView {
                    switch selectedTab {
                    case "overview":
                        OverviewTab(validator: validator)
                    case "requirements":
                        RequirementsTab(tracker: tracker)
                    case "gaps":
                        GapsTab(validator: validator)
                    case "checklist":
                        ChecklistTab(validator: validator)
                    default:
                        EmptyView()
                    }
                }
            }
            .navigationTitle("Planning Validation")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Validate") {
                        Task {
                            await validator.validateConversation()
                        }
                    }
                    .disabled(validator.isValidating)
                }
            }
        }
        .task {
            // Initialize validation session when view appears
            await validator.initializeSession(projectType: .webApp)
        }
    }
}

// MARK: - Overview Tab

struct OverviewTab: View {
    @ObservedObject var validator: PlanningValidator
    
    var body: some View {
        VStack(spacing: Spacing.lg) {
            // Readiness Score Card
            DashboardReadinessScoreCard(
                score: validator.readinessScore,
                level: validator.readinessLevel
            )
            
            // Domain Scores
            DomainScoresCard(scores: validator.domainScores)
            
            // Quick Stats
            QuickStatsCard(validator: validator)
            
            // Suggestions
            if !validator.suggestions.isEmpty {
                SuggestionsCard(suggestions: validator.suggestions)
            }
        }
        .padding()
    }
}

// MARK: - Requirements Tab

struct RequirementsTab: View {
    @ObservedObject var tracker: RequirementsTracker
    @State private var expandedDomains: Set<String> = []
    
    var body: some View {
        VStack(spacing: Spacing.md) {
            // Progress Overview
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Overall Progress")
                    .font(.headline)
                
                ProgressView(value: tracker.completionPercentage(), total: 100)
                    .progressViewStyle(LinearProgressViewStyle())
                
                HStack {
                    Text("\(tracker.completedCount) of \(tracker.totalCount) completed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(tracker.completionPercentage()))%")
                        .font(.caption)
                        .bold()
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(12)
            
            // Requirements by Domain
            ForEach(Array(tracker.requirements.keys.sorted()), id: \.self) { domain in
                DomainRequirementsSection(
                    domain: domain,
                    requirements: tracker.requirementsForDomain(domain),
                    completion: tracker.domainCompletion(domain),
                    isExpanded: expandedDomains.contains(domain),
                    onToggle: {
                        if expandedDomains.contains(domain) {
                            expandedDomains.remove(domain)
                        } else {
                            expandedDomains.insert(domain)
                        }
                    },
                    onToggleRequirement: { requirement in
                        tracker.toggleRequirement(requirement)
                    }
                )
            }
        }
        .padding()
    }
}

// MARK: - Gaps Tab

struct GapsTab: View {
    @ObservedObject var validator: PlanningValidator
    
    var body: some View {
        VStack(spacing: Spacing.md) {
            if validator.gaps.isEmpty {
                NoGapsView()
            } else {
                ForEach(validator.gaps) { gap in
                    GapCard(gap: gap)
                }
            }
        }
        .padding()
    }
}

// MARK: - Checklist Tab

struct ChecklistTab: View {
    @ObservedObject var validator: PlanningValidator
    
    var body: some View {
        VStack(spacing: Spacing.md) {
            if validator.checklist.isEmpty {
                EmptyChecklistView()
            } else {
                ForEach(validator.checklist) { item in
                    ChecklistItemView(
                        item: item,
                        onToggle: { completed in
                            Task {
                                await validator.updateChecklistItem(item, completed: completed)
                            }
                        }
                    )
                }
            }
        }
        .padding()
    }
}

// MARK: - Component Views

struct DashboardReadinessScoreCard: View {
    let score: Int
    let level: InternalReadinessLevel
    
    var body: some View {
        VStack(spacing: Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Readiness Score")
                        .font(.headline)
                    
                    HStack {
                        Text(level.icon)
                            .font(.title)
                        Text(level.label)
                            .font(.title2)
                            .bold()
                    }
                    
                    Text(level.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Circular progress
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 10)
                    
                    Circle()
                        .trim(from: 0, to: CGFloat(score) / 100)
                        .stroke(level.color, lineWidth: 10)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 1), value: score)
                }
                .frame(width: 80, height: 80)
                .overlay(
                    Text("\(score)%")
                        .font(.title2)
                        .bold()
                )
            }
        }
        .padding()
        .background(level.color.opacity(0.1))
        .cornerRadius(12)
    }
}

struct DomainScoresCard: View {
    let scores: [InternalDomainScore]
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Domain Scores")
                .font(.headline)
            
            ForEach(scores) { score in
                HStack {
                    Text(score.icon)
                    Text(score.displayName)
                        .font(.subheadline)
                    
                    Spacer()
                    
                    ProgressView(value: Double(score.score), total: 100)
                        .progressViewStyle(LinearProgressViewStyle(tint: score.scoreColor))
                        .frame(width: 100)
                    
                    Text("\(score.score)%")
                        .font(.caption)
                        .foregroundColor(score.scoreColor)
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }
}

struct QuickStatsCard: View {
    @ObservedObject var validator: PlanningValidator
    
    var body: some View {
        HStack(spacing: Spacing.lg) {
            DashboardStatItem(
                title: "Gaps",
                value: "\(validator.gaps.count)",
                icon: "exclamationmark.triangle",
                color: .orange
            )
            
            DashboardStatItem(
                title: "Checklist",
                value: "\(validator.checklist.filter { !$0.completed }.count)",
                icon: "checklist",
                color: .blue
            )
            
            DashboardStatItem(
                title: "Suggestions",
                value: "\(validator.suggestions.count)",
                icon: "lightbulb",
                color: .yellow
            )
        }
    }
}

struct DashboardStatItem: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title)
                .bold()
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

struct SuggestionsCard: View {
    let suggestions: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                Text("Suggestions")
                    .font(.headline)
            }
            
            ForEach(suggestions, id: \.self) { suggestion in
                HStack(alignment: .top) {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundColor(.accentColor)
                        .font(.caption)
                    Text(suggestion)
                        .font(.subheadline)
                }
            }
        }
        .padding()
        .background(Color.yellow.opacity(0.1))
        .cornerRadius(12)
    }
}

struct DomainRequirementsSection: View {
    let domain: String
    let requirements: [Requirement]
    let completion: Double
    let isExpanded: Bool
    let onToggle: () -> Void
    let onToggleRequirement: (Requirement) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button(action: onToggle) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                    
                    Text(domain.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.headline)
                    
                    Spacer()
                    
                    Text("\(Int(completion))%")
                        .font(.caption)
                        .foregroundColor(completion > 75 ? .green : .orange)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            if isExpanded {
                ForEach(requirements) { requirement in
                    RequirementRow(
                        requirement: requirement,
                        onToggle: { onToggleRequirement(requirement) }
                    )
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }
}

struct RequirementRow: View {
    let requirement: Requirement
    let onToggle: () -> Void
    
    var body: some View {
        HStack(alignment: .top) {
            Button(action: onToggle) {
                Image(systemName: requirement.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(requirement.isCompleted ? .green : .secondary)
            }
            .buttonStyle(PlainButtonStyle())
            
            VStack(alignment: .leading, spacing: 2) {
                Text(requirement.name)
                    .font(.subheadline)
                    .strikethrough(requirement.isCompleted)
                
                Text(requirement.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Image(systemName: requirement.priority.icon)
                .font(.caption)
                .foregroundColor(requirement.priority.color)
        }
        .padding(.vertical, 4)
    }
}

struct GapCard: View {
    let gap: RequirementGap
    
    var body: some View {
        HStack(alignment: .top) {
            Circle()
                .fill(gap.priorityColor)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Text(gap.domain.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("•")
                        .foregroundStyle(.secondary)
                    
                    Text(gap.priority.uppercased())
                        .font(.caption)
                        .bold()
                        .foregroundColor(gap.priorityColor)
                }
                
                Text(gap.item)
                    .font(.headline)
                
                Text(gap.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }
}

struct ChecklistItemView: View {
    let item: ChecklistItem
    let onToggle: (Bool) -> Void
    @State private var isCompleted: Bool
    @State private var notes: String
    
    init(item: ChecklistItem, onToggle: @escaping (Bool) -> Void) {
        self.item = item
        self.onToggle = onToggle
        self._isCompleted = State(initialValue: item.completed)
        self._notes = State(initialValue: item.notes)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top) {
                Button(action: {
                    isCompleted.toggle()
                    onToggle(isCompleted)
                }) {
                    Image(systemName: isCompleted ? "checkmark.square.fill" : "square")
                        .foregroundColor(isCompleted ? .green : .secondary)
                        .font(.title3)
                }
                .buttonStyle(PlainButtonStyle())
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.description)
                        .font(.subheadline)
                        .strikethrough(isCompleted)
                    
                    HStack {
                        Text(item.domain.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text("•")
                            .foregroundStyle(.secondary)
                        
                        Text(item.priority.uppercased())
                            .font(.caption)
                            .bold()
                            .foregroundColor(priorityColor(item.priority))
                    }
                }
                
                Spacer()
            }
            
            if !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 28)
            }
        }
        .padding()
        .background(isCompleted ? Color.green.opacity(0.05) : Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }
    
    func priorityColor(_ priority: String) -> Color {
        switch priority {
        case "critical": return .red
        case "high": return .orange
        case "medium": return .yellow
        default: return .gray
        }
    }
}

struct NoGapsView: View {
    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            
            Text("No Gaps Detected")
                .font(.title2)
                .bold()
            
            Text("All requirements appear to be covered")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding()
    }
}

struct EmptyChecklistView: View {
    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "checklist")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("No Checklist Items")
                .font(.title2)
                .bold()
            
            Text("Run validation to generate checklist")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding()
    }
}