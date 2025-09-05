//
//  ProjectCreationWizard.swift
//  AICLICompanion
//
//  Created on 2025-09-04.
//

import SwiftUI

struct ProjectCreationWizard: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ProjectCreationViewModel()
    @State private var currentStep = 0
    
    private let steps = ["Project Info", "Configuration", "Templates", "Review"]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Progress indicator
                ProgressBar(currentStep: currentStep, totalSteps: steps.count)
                    .padding()
                
                // Step title
                Text(steps[currentStep])
                    .font(.title2)
                    .bold()
                    .padding(.bottom)
                
                // Content area
                Group {
                    switch currentStep {
                    case 0:
                        ProjectInfoStep(viewModel: viewModel)
                    case 1:
                        ProjectConfigurationStep(viewModel: viewModel)
                    case 2:
                        TemplateSelectionStep(viewModel: viewModel)
                    case 3:
                        ReviewStep(viewModel: viewModel)
                    default:
                        EmptyView()
                    }
                }
                .frame(maxHeight: .infinity)
                
                // Navigation buttons
                HStack {
                    Button("Previous") {
                        withAnimation {
                            currentStep = max(0, currentStep - 1)
                        }
                    }
                    .disabled(currentStep == 0)
                    
                    Spacer()
                    
                    if currentStep < steps.count - 1 {
                        Button("Next") {
                            withAnimation {
                                currentStep = min(steps.count - 1, currentStep + 1)
                            }
                        }
                        .disabled(!viewModel.canProceedToStep(currentStep + 1))
                    } else {
                        Button("Create Project") {
                            Task {
                                await createProject()
                            }
                        }
                        .disabled(!viewModel.isReadyToCreate)
                    }
                }
                .padding()
            }
            .navigationTitle("New Project")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .interactiveDismissDisabled(viewModel.hasUnsavedChanges)
    }
    
    private func createProject() async {
        await viewModel.createProject()
        if viewModel.creationSuccessful {
            dismiss()
        }
    }
}

// MARK: - Step Views

struct ProjectInfoStep: View {
    @ObservedObject var viewModel: ProjectCreationViewModel
    
    var body: some View {
        Form {
            Section("Project Details") {
                TextField("Project Name", text: $viewModel.projectName)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                
                TextField("Description", text: $viewModel.projectDescription, axis: .vertical)
                    .lineLimit(3...6)
                
                TextField("Author", text: $viewModel.author)
            }
            
            Section("Project Type") {
                Picker("Type", selection: $viewModel.projectType) {
                    Text("Web Application").tag(ProjectType.webApp)
                    Text("Mobile Application").tag(ProjectType.mobileApp)
                    Text("API Service").tag(ProjectType.apiService)
                    Text("CLI Tool").tag(ProjectType.cliTool)
                }
                .pickerStyle(.segmented)
                
                Text(viewModel.projectType.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ProjectConfigurationStep: View {
    @ObservedObject var viewModel: ProjectCreationViewModel
    
    var body: some View {
        Form {
            Section("Technology Stack") {
                Picker("Primary Stack", selection: $viewModel.techStack) {
                    ForEach(TechStack.allCases) { stack in
                        Label(stack.rawValue, systemImage: stack.icon)
                            .tag(stack)
                    }
                }
                
                Toggle("Include Docker Setup", isOn: $viewModel.includeDocker)
                Toggle("Include CI/CD Pipeline", isOn: $viewModel.includeCICD)
                Toggle("Initialize Git Repository", isOn: $viewModel.initGit)
            }
            
            Section("Team Configuration") {
                Picker("Team Size", selection: $viewModel.teamSize) {
                    Text("Solo Developer").tag(TeamSize.solo)
                    Text("Small Team (2-5)").tag(TeamSize.small)
                    Text("Medium Team (6-15)").tag(TeamSize.medium)
                    Text("Large Team (16+)").tag(TeamSize.large)
                }
            }
            
            Section("Architecture") {
                Picker("Architecture Pattern", selection: $viewModel.architecture) {
                    Text("Monolithic").tag(Architecture.monolith)
                    Text("Microservices").tag(Architecture.microservices)
                    Text("Serverless").tag(Architecture.serverless)
                }
                .pickerStyle(.segmented)
            }
        }
    }
}

struct TemplateSelectionStep: View {
    @ObservedObject var viewModel: ProjectCreationViewModel
    @State private var selectedTemplates = Set<String>()
    
    var body: some View {
        VStack {
            Text("Select templates to include in your project")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            
            List {
                Section("Core Templates") {
                    TemplateRow(
                        name: "CLAUDE.md",
                        description: "Development guidelines and best practices",
                        isCore: true,
                        isSelected: true
                    )
                    
                    TemplateRow(
                        name: "plan.md",
                        description: "TDD planning document template",
                        isCore: true,
                        isSelected: true
                    )
                    
                    TemplateRow(
                        name: "README.md",
                        description: "Project documentation template",
                        isCore: true,
                        isSelected: true
                    )
                }
                
                Section("Additional Templates") {
                    ForEach(viewModel.availableTemplates, id: \.self) { template in
                        TemplateRow(
                            name: template.name,
                            description: template.description,
                            isCore: false,
                            isSelected: selectedTemplates.contains(template.name)
                        ) {
                            if selectedTemplates.contains(template.name) {
                                selectedTemplates.remove(template.name)
                            } else {
                                selectedTemplates.insert(template.name)
                            }
                        }
                    }
                }
            }
            .onAppear {
                viewModel.loadAvailableTemplates()
            }
        }
    }
}

struct ReviewStep: View {
    @ObservedObject var viewModel: ProjectCreationViewModel
    @State private var showingReadinessDetails = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                // Project summary
                SummaryCard(title: "Project Summary") {
                    SummaryRow(label: "Name", value: viewModel.projectName)
                    SummaryRow(label: "Type", value: viewModel.projectType.rawValue)
                    SummaryRow(label: "Tech Stack", value: viewModel.techStack.rawValue)
                    SummaryRow(label: "Team Size", value: viewModel.teamSize.rawValue)
                    SummaryRow(label: "Architecture", value: viewModel.architecture.rawValue)
                }
                
                // Readiness assessment
                ReadinessCard(
                    score: viewModel.readinessScore,
                    level: viewModel.readinessLevel,
                    showDetails: $showingReadinessDetails
                )
                
                // Templates to be created
                SummaryCard(title: "Templates") {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        ForEach(viewModel.selectedTemplateNames, id: \.self) { template in
                            HStack {
                                Image(systemName: "doc.text")
                                    .foregroundColor(.accentColor)
                                Text(template)
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                    }
                }
                
                // Creation status
                if viewModel.isCreating {
                    HStack {
                        ProgressView()
                        Text("Creating project...")
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
                
                if let error = viewModel.creationError {
                    ErrorView(message: error)
                }
            }
            .padding()
        }
        .sheet(isPresented: $showingReadinessDetails) {
            ReadinessDetailsView(viewModel: viewModel)
        }
    }
}

// MARK: - Supporting Views

struct ProgressBar: View {
    let currentStep: Int
    let totalSteps: Int
    
    var progress: Double {
        Double(currentStep + 1) / Double(totalSteps)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 4)
                
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: geometry.size.width * progress, height: 4)
                    .animation(.easeInOut, value: progress)
            }
        }
        .frame(height: 4)
    }
}

struct TemplateRow: View {
    let name: String
    let description: String
    let isCore: Bool
    let isSelected: Bool
    var onToggle: (() -> Void)?
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(name)
                        .font(.system(.body, design: .monospaced))
                    if isCore {
                        Text("REQUIRED")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.2))
                            .foregroundColor(.accentColor)
                            .cornerRadius(4)
                    }
                }
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if !isCore {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .onTapGesture {
                        onToggle?()
                    }
            }
        }
        .contentShape(Rectangle())
    }
}

struct SummaryCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(title)
                .font(.headline)
            
            VStack(alignment: .leading, spacing: Spacing.sm) {
                content
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
        }
    }
}

struct SummaryRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .bold()
        }
    }
}

struct ReadinessCard: View {
    let score: Int
    let level: ReadinessLevel
    @Binding var showDetails: Bool
    
    var scoreColor: Color {
        switch score {
        case 90...100: return .green
        case 75...89: return .yellow
        case 60...74: return .orange
        default: return .red
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("Project Readiness")
                    .font(.headline)
                Spacer()
                Button("Details") {
                    showDetails = true
                }
                .font(.caption)
            }
            
            HStack {
                // Score circle
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 8)
                    
                    Circle()
                        .trim(from: 0, to: CGFloat(score) / 100)
                        .stroke(scoreColor, lineWidth: 8)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut, value: score)
                }
                .frame(width: 60, height: 60)
                .overlay(
                    Text("\(score)%")
                        .font(.system(.title3, design: .rounded))
                        .bold()
                )
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(level.icon)
                        Text(level.label)
                            .font(.subheadline)
                            .bold()
                    }
                    
                    Text(level.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .padding()
            .background(scoreColor.opacity(0.1))
            .cornerRadius(8)
        }
    }
}

struct ReadinessDetailsView: View {
    @ObservedObject var viewModel: ProjectCreationViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section("Overall Assessment") {
                    HStack {
                        Text("Readiness Score")
                        Spacer()
                        Text("\(viewModel.readinessScore)%")
                            .bold()
                    }
                    
                    HStack {
                        Text("Status")
                        Spacer()
                        HStack {
                            Text(viewModel.readinessLevel.icon)
                            Text(viewModel.readinessLevel.label)
                                .foregroundColor(viewModel.readinessLevel.color)
                        }
                    }
                }
                
                Section("Domain Scores") {
                    ForEach(viewModel.domainScores, id: \.domain) { score in
                        HStack {
                            Text(score.icon)
                            Text(score.domain)
                            Spacer()
                            Text("\(score.score)%")
                                .foregroundColor(score.score >= 60 ? .green : .orange)
                        }
                    }
                }
                
                if !viewModel.missingRequirements.isEmpty {
                    Section("Missing Requirements") {
                        ForEach(viewModel.missingRequirements, id: \.self) { requirement in
                            HStack {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundColor(.orange)
                                Text(requirement)
                                    .font(.caption)
                            }
                        }
                    }
                }
                
                if !viewModel.suggestions.isEmpty {
                    Section("Suggestions") {
                        ForEach(viewModel.suggestions, id: \.self) { suggestion in
                            HStack(alignment: .top) {
                                Image(systemName: "lightbulb")
                                    .foregroundColor(.yellow)
                                Text(suggestion)
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Readiness Details")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

struct ProjectCreationWizard_Previews: PreviewProvider {
    static var previews: some View {
        ProjectCreationWizard()
    }
}
