//
//  PlanningValidationDashboard.swift
//  AICLICompanion
//
//  Created on 2025-09-04.
//

import SwiftUI
import Charts
#if os(iOS)
import UIKit
#endif

struct PlanningValidationDashboard: View {
    @StateObject private var viewModel = PlanningValidationViewModel()
    @State private var selectedDomain: String?
    @State private var showingActionItems = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                // Overall readiness
                OverallReadinessCard(viewModel: viewModel)
                    .padding(.horizontal)
                    
                // Domain breakdown
                DomainScoresSection(
                    viewModel: viewModel,
                    selectedDomain: $selectedDomain
                )
                .padding(.horizontal)
                    
                // Blockers section
                if !viewModel.blockers.isEmpty {
                    BlockersSection(blockers: viewModel.blockers)
                        .padding(.horizontal)
                }
                    
                // Suggestions
                if !viewModel.suggestions.isEmpty {
                    SuggestionsSection(suggestions: viewModel.suggestions)
                        .padding(.horizontal)
                }
                    
                // Action items button
                if viewModel.hasActionItems {
                    Button(action: { showingActionItems = true }) {
                        HStack {
                            Image(systemName: "checklist")
                            Text("View Action Items (\(viewModel.actionItems.count))")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding()
                        .background(Color.accentColor.opacity(0.1))
                        .foregroundColor(.accentColor)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                }
                    
                // Confidence indicator
                ConfidenceIndicator(confidence: viewModel.analysisConfidence)
                    .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle("Planning Validation")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(viewModel.isAnalyzing ? "Analyzing..." : "Analyze") {
                    Task {
                        await viewModel.refreshAnalysis()
                    }
                }
                .disabled(viewModel.isAnalyzing)
            }
        }
        .sheet(isPresented: $showingActionItems) {
            ActionItemsSheet(actionItems: viewModel.actionItems)
        }
        .sheet(item: $selectedDomain) { domain in
            DomainDetailsSheet(domain: domain, viewModel: viewModel)
        }
        .task {
            // Use mock data for now since we're in planning mode
            await viewModel.analyzeMockConversation()
        }
    }
}

// MARK: - Components

struct OverallReadinessCard: View {
    @ObservedObject var viewModel: PlanningValidationViewModel
    
    var body: some View {
        VStack(spacing: Spacing.md) {
            HStack {
                Text("Overall Readiness")
                    .font(.title2)
                    .bold()
                Spacer()
                Text(viewModel.readinessLevel.icon)
                    .font(.title)
            }
            
            // Circular progress
            ZStack {
                // Background circle
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 20)
                    .frame(width: 150, height: 150)
                
                // Progress circle
                Circle()
                    .trim(from: 0, to: CGFloat(viewModel.overallScore) / 100)
                    .stroke(
                        viewModel.scoreColor,
                        style: StrokeStyle(lineWidth: 20, lineCap: .round)
                    )
                    .frame(width: 150, height: 150)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(), value: viewModel.overallScore)
                
                // Score text
                VStack {
                    Text("\(viewModel.overallScore)%")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    Text(viewModel.readinessLevel.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical)
            
            // Status description
            Text(viewModel.readinessLevel.description)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            
            // Can proceed indicator
            HStack {
                Image(systemName: viewModel.readinessLevel.canProceed ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(viewModel.readinessLevel.canProceed ? .green : .red)
                Text(viewModel.readinessLevel.canProceed ? "Ready to proceed" : "More planning needed")
                    .font(.caption)
                    .bold()
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(viewModel.readinessLevel.canProceed ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
            )
        }
        .padding()
        #if os(iOS)
        .background(Color(UIColor.secondarySystemBackground))
        #else
        .background(Color(NSColor.controlBackgroundColor))
        #endif
        .cornerRadius(16)
    }
}

struct DomainScoresSection: View {
    @ObservedObject var viewModel: PlanningValidationViewModel
    @Binding var selectedDomain: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Domain Analysis")
                .font(.headline)
            
            VStack(spacing: Spacing.sm) {
                ForEach(viewModel.domainScores, id: \.name) { domain in
                    DomainScoreRow(domain: domain) {
                        selectedDomain = domain.name
                    }
                }
            }
        }
        .padding()
        #if os(iOS)
        .background(Color(UIColor.secondarySystemBackground))
        #else
        .background(Color(NSColor.controlBackgroundColor))
        #endif
        .cornerRadius(16)
    }
}

struct DomainScoreRow: View {
    let domain: PlanningDomainScore
    let onTap: () -> Void
    
    var scoreColor: Color {
        switch domain.score {
        case 80...100: return .green
        case 60...79: return .yellow
        case 40...59: return .orange
        default: return .red
        }
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(domain.icon)
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(domain.name)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    
                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.2))
                                .frame(height: 6)
                                .cornerRadius(3)
                            
                            Rectangle()
                                .fill(scoreColor)
                                .frame(width: geometry.size.width * CGFloat(domain.score) / 100, height: 6)
                                .cornerRadius(3)
                                .animation(.spring(), value: domain.score)
                        }
                    }
                    .frame(height: 6)
                }
                
                Spacer()
                
                Text("\(domain.score)%")
                    .font(.system(.body, design: .rounded))
                    .bold()
                    .foregroundColor(scoreColor)
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, Spacing.sm)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct BlockersSection: View {
    let blockers: [Blocker]
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text("Blockers")
                    .font(.headline)
            }
            
            VStack(spacing: Spacing.sm) {
                ForEach(blockers) { blocker in
                    BlockerRow(blocker: blocker)
                }
            }
        }
        .padding()
        .background(Color.red.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.red.opacity(0.2), lineWidth: 1)
        )
        .cornerRadius(16)
    }
}

struct BlockerRow: View {
    let blocker: Blocker
    
    var severityColor: Color {
        switch blocker.severity {
        case .critical: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .blue
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Circle()
                    .fill(severityColor)
                    .frame(width: 8, height: 8)
                
                Text(blocker.message)
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }
            
            Text(blocker.resolution)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 12)
        }
    }
}

struct SuggestionsSection: View {
    let suggestions: [Suggestion]
    @State private var expandedSuggestions = Set<UUID>()
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                Text("Suggestions")
                    .font(.headline)
            }
            
            VStack(spacing: Spacing.sm) {
                ForEach(suggestions) { suggestion in
                    SuggestionRow(
                        suggestion: suggestion,
                        isExpanded: expandedSuggestions.contains(suggestion.id)
                    ) {
                        if expandedSuggestions.contains(suggestion.id) {
                            expandedSuggestions.remove(suggestion.id)
                        } else {
                            expandedSuggestions.insert(suggestion.id)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.yellow.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(16)
    }
}

struct SuggestionRow: View {
    let suggestion: Suggestion
    let isExpanded: Bool
    let onTap: () -> Void
    
    var priorityIcon: String {
        switch suggestion.priority {
        case .high: return "exclamationmark.2"
        case .medium: return "exclamationmark"
        case .low: return "info.circle"
        }
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    Image(systemName: priorityIcon)
                        .font(.caption)
                        .foregroundColor(.orange)
                    
                    Text(suggestion.message)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineLimit(isExpanded ? nil : 1)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if isExpanded {
                    Text(suggestion.action)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 20)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isExpanded)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ConfidenceIndicator: View {
    let confidence: Int
    
    var confidenceColor: Color {
        switch confidence {
        case 80...100: return .green
        case 60...79: return .yellow
        case 40...59: return .orange
        default: return .red
        }
    }
    
    var confidenceDescription: String {
        switch confidence {
        case 80...100: return "High confidence in analysis"
        case 60...79: return "Good confidence in analysis"
        case 40...59: return "Moderate confidence in analysis"
        default: return "Low confidence - more detail needed"
        }
    }
    
    var body: some View {
        HStack {
            Image(systemName: "chart.bar.fill")
                .foregroundColor(confidenceColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Analysis Confidence: \(confidence)%")
                    .font(.caption)
                    .bold()
                
                Text(confidenceDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding()
        #if os(iOS)
        .background(Color(UIColor.tertiarySystemBackground))
        #else
        .background(Color(NSColor.windowBackgroundColor))
        #endif
        .cornerRadius(8)
    }
}

// MARK: - Sheets

struct ActionItemsSheet: View {
    let actionItems: [ActionItem]
    @Environment(\.dismiss) private var dismiss
    @State private var completedItems = Set<UUID>()
    
    var body: some View {
        NavigationView {
            List {
                ForEach(actionItems) { item in
                    ActionItemRow(
                        item: item,
                        isCompleted: completedItems.contains(item.id)
                    ) {
                        if completedItems.contains(item.id) {
                            completedItems.remove(item.id)
                        } else {
                            completedItems.insert(item.id)
                        }
                    }
                }
            }
            .navigationTitle("Action Items")
            #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct ActionItemRow: View {
    let item: ActionItem
    let isCompleted: Bool
    let onToggle: () -> Void
    
    var body: some View {
        HStack {
            Button(action: onToggle) {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isCompleted ? .green : .secondary)
            }
            .buttonStyle(PlainButtonStyle())
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.icon)
                    Text(item.action)
                        .strikethrough(isCompleted)
                        .foregroundColor(isCompleted ? .secondary : .primary)
                }
                
                HStack {
                    Label(item.impact.capitalized, systemImage: "arrow.up.arrow.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    Label(item.effort.capitalized, systemImage: "timer")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

extension String: Identifiable {
    public var id: String { self }
}

struct DomainDetailsSheet: View {
    let domain: String
    @ObservedObject var viewModel: PlanningValidationViewModel
    @Environment(\.dismiss) private var dismiss
    
    var domainScore: PlanningDomainScore? {
        viewModel.domainScores.first { $0.name == domain }
    }
    
    var body: some View {
        NavigationView {
            if let score = domainScore {
                List {
                    Section("Overview") {
                        HStack {
                            Text("Score")
                            Spacer()
                            Text("\(score.score)%")
                                .bold()
                        }
                        
                        HStack {
                            Text("Confidence")
                            Spacer()
                            Text("\(score.confidence)%")
                                .foregroundStyle(.secondary)
                        }
                        
                        HStack {
                            Text("Keyword Matches")
                            Spacer()
                            Text("\(score.keywordMatches)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    if !score.foundRequirements.isEmpty {
                        Section("Found Requirements") {
                            ForEach(score.foundRequirements, id: \.self) { req in
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text(req)
                                }
                            }
                        }
                    }
                    
                    if !score.missingRequirements.isEmpty {
                        Section("Missing Requirements") {
                            ForEach(score.missingRequirements, id: \.self) { req in
                                HStack {
                                    Image(systemName: "xmark.circle")
                                        .foregroundColor(.red)
                                    Text(req)
                                }
                            }
                        }
                    }
                }
                .navigationTitle("\(score.icon) \(score.name)")
                #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            } else {
                Text("Domain details not available")
                    .navigationTitle(domain)
                    #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { dismiss() }
                        }
                    }
            }
        }
    }
}

// MARK: - Preview

struct PlanningValidationDashboard_Previews: PreviewProvider {
    static var previews: some View {
        PlanningValidationDashboard()
    }
}
