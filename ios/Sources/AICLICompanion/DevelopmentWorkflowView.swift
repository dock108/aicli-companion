import SwiftUI

@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
struct DevelopmentWorkflowView: View {
    @ObservedObject var workflowService: DevelopmentWorkflowService
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: WorkflowTab = .overview
    @State private var showingBuildResults = false
    @State private var showingTestDetails = false
    @State private var selectedTestSuite: TestSuite?

    let onCommandSelected: (String) -> Void

    enum WorkflowTab: String, CaseIterable {
        case overview = "Overview"
        case git = "Git"
        case build = "Build"
        case tests = "Tests"

        var icon: String {
            switch self {
            case .overview: return "square.grid.3x3"
            case .git: return "arrow.branch"
            case .build: return "hammer"
            case .tests: return "testtube.2"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack {
                // Tab Selection
                Picker("Workflow Tab", selection: $selectedTab) {
                    ForEach(WorkflowTab.allCases, id: \.self) { tab in
                        Label(tab.rawValue, systemImage: tab.icon)
                            .tag(tab)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)

                // Content based on selected tab
                ScrollView {
                    switch selectedTab {
                    case .overview:
                        OverviewTabView(workflowService: workflowService, onCommandSelected: onCommandSelected)
                    case .git:
                        GitTabView(repository: workflowService.currentRepository, onCommandSelected: onCommandSelected)
                    case .build:
                        BuildTabView(buildSystem: workflowService.buildSystem, onCommandSelected: onCommandSelected)
                    case .tests:
                        TestsTabView(testSuites: workflowService.testSuites, onCommandSelected: onCommandSelected)
                    }
                }
                .refreshable {
                    // Refresh workflow analysis
                    if !workflowService.workingDirectory.isEmpty {
                        workflowService.analyzeWorkflow(in: workflowService.workingDirectory)
                    }
                }
            }
            .navigationTitle("Development Workflow")
            #if os(iOS)

            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif

            #endif
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .automatic) {
                    Menu {
                        Button("Refresh Analysis") {
                            if !workflowService.workingDirectory.isEmpty {
                                workflowService.analyzeWorkflow(in: workflowService.workingDirectory)
                            }
                        }

                        Button("Quick Git Status") {
                            onCommandSelected("git status")
                            dismiss()
                        }

                        Button("Run Build") {
                            if let buildSystem = workflowService.buildSystem,
                               let command = buildSystem.type.primaryCommands.first {
                                onCommandSelected(command)
                                dismiss()
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }
}

// MARK: - Overview Tab

@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
struct OverviewTabView: View {
    @ObservedObject var workflowService: DevelopmentWorkflowService
    let onCommandSelected: (String) -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Project Status Summary
            ProjectStatusCard(workflowService: workflowService)

            // High Priority Suggestions
            if !workflowService.workflowSuggestions.isEmpty {
                WorkflowSuggestionsCard(
                    suggestions: Array(workflowService.workflowSuggestions.prefix(3)),
                    onCommandSelected: onCommandSelected
                )
            }

            // Quick Actions
            QuickActionsCard(workflowService: workflowService, onCommandSelected: onCommandSelected)

            // Recent Activity
            if let buildSystem = workflowService.buildSystem,
               let lastBuild = buildSystem.lastBuildResult {
                RecentBuildCard(buildResult: lastBuild)
            }
        }
        .padding()
    }
}

@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
struct ProjectStatusCard: View {
    @ObservedObject var workflowService: DevelopmentWorkflowService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "folder.badge.gearshape")
                    .font(.title2)
                    .foregroundColor(.blue)

                Text("Project Status")
                    .font(.headline)
                    .fontWeight(.medium)

                Spacer()
            }

            VStack(spacing: 8) {
                if let git = workflowService.currentRepository {
                    StatusRow(
                        label: "Git Repository",
                        value: git.currentBranch,
                        icon: "arrow.branch",
                        color: git.hasUncommittedChanges ? .orange : .green
                    )
                }

                if let build = workflowService.buildSystem {
                    StatusRow(
                        label: "Build System",
                        value: build.type.rawValue,
                        icon: build.type.icon,
                        color: build.lastBuildResult?.success == true ? .green : .orange
                    )
                }

                if !workflowService.testSuites.isEmpty {
                    let totalTests = workflowService.testSuites.compactMap { $0.lastResults?.totalTests }.reduce(0, +)
                    let failedTests = workflowService.testSuites.compactMap { $0.lastResults?.failedTests }.reduce(0, +)

                    StatusRow(
                        label: "Test Status",
                        value: "\(totalTests) tests",
                        icon: "testtube.2",
                        color: failedTests > 0 ? .red : .green
                    )
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}

@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
struct StatusRow: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)

            Text(label)
                .font(.subheadline)

            Spacer()

            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
        }
    }
}

@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
struct WorkflowSuggestionsCard: View {
    let suggestions: [WorkflowSuggestion]
    let onCommandSelected: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "lightbulb")
                    .font(.title2)
                    .foregroundColor(.yellow)

                Text("Workflow Suggestions")
                    .font(.headline)
                    .fontWeight(.medium)

                Spacer()
            }

            VStack(spacing: 8) {
                ForEach(suggestions, id: \.id) { suggestion in
                    WorkflowSuggestionRow(suggestion: suggestion) {
                        onCommandSelected(suggestion.command)
                    }
                }
            }
        }
        .padding()
        .background(Color.yellow.opacity(0.1))
        .cornerRadius(12)
    }
}

@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
struct WorkflowSuggestionRow: View {
    let suggestion: WorkflowSuggestion
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: suggestion.icon)
                    .foregroundColor(priorityColor)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    Text(suggestion.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var priorityColor: Color {
        switch suggestion.priority {
        case .critical: return .red
        case .high: return .orange
        case .medium: return .blue
        case .low: return .gray
        }
    }
}

@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
struct QuickActionsCard: View {
    @ObservedObject var workflowService: DevelopmentWorkflowService
    let onCommandSelected: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bolt")
                    .font(.title2)
                    .foregroundColor(.purple)

                Text("Quick Actions")
                    .font(.headline)
                    .fontWeight(.medium)

                Spacer()
            }

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                QuickActionButton(
                    title: "Git Status",
                    icon: "info.circle",
                    color: .blue
                ) {
                    onCommandSelected("git status")
                }

                QuickActionButton(
                    title: "Build",
                    icon: "hammer",
                    color: .green
                ) {
                    if let command = workflowService.buildSystem?.type.primaryCommands.first {
                        onCommandSelected(command)
                    }
                }

                QuickActionButton(
                    title: "Test",
                    icon: "testtube.2",
                    color: .orange
                ) {
                    if let command = workflowService.buildSystem?.type.primaryCommands.dropFirst().first {
                        onCommandSelected(command)
                    }
                }

                QuickActionButton(
                    title: "Commit",
                    icon: "checkmark.circle",
                    color: .purple
                ) {
                    onCommandSelected("git add . && git commit")
                }

                QuickActionButton(
                    title: "Push",
                    icon: "arrow.up.circle",
                    color: .indigo
                ) {
                    if let branch = workflowService.currentRepository?.currentBranch {
                        onCommandSelected("git push origin \(branch)")
                    } else {
                        onCommandSelected("git push")
                    }
                }

                QuickActionButton(
                    title: "Pull",
                    icon: "arrow.down.circle",
                    color: .teal
                ) {
                    onCommandSelected("git pull")
                }
            }
        }
        .padding()
        .background(Color.purple.opacity(0.1))
        .cornerRadius(12)
    }
}

@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)

                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
struct RecentBuildCard: View {
    let buildResult: BuildResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: buildResult.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(buildResult.success ? .green : .red)

                Text("Last Build")
                    .font(.headline)
                    .fontWeight(.medium)

                Spacer()

                Text(buildResult.timestamp, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Duration:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(String(format: "%.1fs", buildResult.duration))
                        .font(.caption)
                        .fontWeight(.medium)

                    Spacer()

                    if !buildResult.errors.isEmpty {
                        Text("\(buildResult.errors.count) errors")
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    if !buildResult.warnings.isEmpty {
                        Text("\(buildResult.warnings.count) warnings")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }

                if !buildResult.output.isEmpty {
                    Text(buildResult.output.prefix(100))
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }
            }
        }
        .padding()
        .background(buildResult.success ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Git Tab

@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
struct GitTabView: View {
    let repository: GitRepository?
    let onCommandSelected: (String) -> Void

    var body: some View {
        VStack(spacing: 16) {
            if let git = repository {
                // Repository Info
                GitRepositoryCard(repository: git)

                // Changed Files
                if !git.changedFiles.isEmpty {
                    GitChangesCard(changes: git.changedFiles, onCommandSelected: onCommandSelected)
                }

                // Recent Commits
                GitCommitsCard(commits: git.recentCommits)

                // Git Actions
                GitActionsCard(repository: git, onCommandSelected: onCommandSelected)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)

                    Text("No Git Repository")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Text("This directory is not a Git repository")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
    }
}

@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
struct GitRepositoryCard: View {
    let repository: GitRepository

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.branch")
                    .font(.title2)
                    .foregroundColor(.orange)

                Text("Repository Status")
                    .font(.headline)
                    .fontWeight(.medium)

                Spacer()
            }

            VStack(spacing: 8) {
                StatusRow(
                    label: "Current Branch",
                    value: repository.currentBranch,
                    icon: "arrow.branch",
                    color: .blue
                )

                if let remoteUrl = repository.remoteUrl {
                    StatusRow(
                        label: "Remote",
                        value: (remoteUrl as NSString).lastPathComponent,
                        icon: "globe",
                        color: .green
                    )
                }

                StatusRow(
                    label: "Changed Files",
                    value: "\(repository.changedFiles.count)",
                    icon: "doc.text",
                    color: repository.hasUncommittedChanges ? .orange : .green
                )

                if repository.status.ahead > 0 {
                    StatusRow(
                        label: "Ahead",
                        value: "\(repository.status.ahead) commits",
                        icon: "arrow.up.circle",
                        color: .blue
                    )
                }

                if repository.status.behind > 0 {
                    StatusRow(
                        label: "Behind",
                        value: "\(repository.status.behind) commits",
                        icon: "arrow.down.circle",
                        color: .orange
                    )
                }
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }
}

@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
struct GitChangesCard: View {
    let changes: [GitFileChange]
    let onCommandSelected: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "doc.text")
                    .font(.title2)
                    .foregroundColor(.blue)

                Text("Changed Files")
                    .font(.headline)
                    .fontWeight(.medium)

                Spacer()

                Button("View Diff") {
                    onCommandSelected("git diff")
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }

            VStack(spacing: 4) {
                ForEach(changes, id: \.id) { change in
                    HStack {
                        Image(systemName: change.status.icon)
                            .foregroundColor(change.status.color)
                            .frame(width: 20)

                        Text(change.path)
                            .font(.caption)
                            .fontDesign(.monospaced)

                        Spacer()

                        Text(change.status.rawValue)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(change.status.color)
                    }
                }
            }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }
}

@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
struct GitCommitsCard: View {
    let commits: [GitCommit]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock")
                    .font(.title2)
                    .foregroundColor(.green)

                Text("Recent Commits")
                    .font(.headline)
                    .fontWeight(.medium)

                Spacer()
            }

            VStack(spacing: 8) {
                ForEach(commits, id: \.id) { commit in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(commit.shortHash)
                                .font(.caption)
                                .fontDesign(.monospaced)
                                .foregroundColor(.secondary)

                            Spacer()

                            Text(commit.date, style: .relative)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Text(commit.message)
                            .font(.subheadline)
                            .lineLimit(2)

                        HStack {
                            Text(commit.author)
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Spacer()

                            Text("\(commit.filesChanged) files")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)

                    if commit.id != commits.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
    }
}

@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
struct GitActionsCard: View {
    let repository: GitRepository
    let onCommandSelected: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bolt")
                    .font(.title2)
                    .foregroundColor(.purple)

                Text("Git Actions")
                    .font(.headline)
                    .fontWeight(.medium)

                Spacer()
            }

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(getGitActions(), id: \.title) { action in
                    Button(action: {
                        onCommandSelected(action.command)
                    }) {
                        HStack {
                            Image(systemName: action.icon)
                                .foregroundColor(.blue)

                            Text(action.title)
                                .font(.subheadline)
                                .foregroundColor(.primary)

                            Spacer()
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding()
        .background(Color.purple.opacity(0.1))
        .cornerRadius(12)
    }

    private func getGitActions() -> [(title: String, command: String, icon: String)] {
        return [
            ("Add All", "git add .", "plus.circle"),
            ("Commit", "git commit", "checkmark.circle"),
            ("Push", "git push origin \(repository.currentBranch)", "arrow.up.circle"),
            ("Pull", "git pull", "arrow.down.circle"),
            ("Stash", "git stash", "archivebox"),
            ("Log", "git log --oneline -10", "list.bullet")
        ]
    }
}

// MARK: - Build Tab

@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
struct BuildTabView: View {
    let buildSystem: BuildSystem?
    let onCommandSelected: (String) -> Void

    var body: some View {
        VStack(spacing: 16) {
            if let build = buildSystem {
                // Build System Info
                BuildSystemCard(buildSystem: build)

                // Build Scripts
                BuildScriptsCard(scripts: build.buildScripts, onCommandSelected: onCommandSelected)

                // Last Build Results
                if let result = build.lastBuildResult {
                    BuildResultsCard(result: result)
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "hammer.badge.gearshape")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)

                    Text("No Build System Detected")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Text("No recognized build configuration found")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
    }
}

@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
struct BuildSystemCard: View {
    let buildSystem: BuildSystem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: buildSystem.type.icon)
                    .font(.title2)
                    .foregroundColor(.blue)

                Text("Build System")
                    .font(.headline)
                    .fontWeight(.medium)

                Spacer()
            }

            VStack(spacing: 8) {
                StatusRow(
                    label: "Type",
                    value: buildSystem.type.rawValue,
                    icon: buildSystem.type.icon,
                    color: .blue
                )

                StatusRow(
                    label: "Targets",
                    value: "\(buildSystem.availableTargets.count)",
                    icon: "target",
                    color: .green
                )

                StatusRow(
                    label: "Config Files",
                    value: "\(buildSystem.configFiles.count)",
                    icon: "gearshape",
                    color: .orange
                )

                if let lastBuild = buildSystem.lastBuildResult {
                    StatusRow(
                        label: "Last Build",
                        value: lastBuild.success ? "Success" : "Failed",
                        icon: lastBuild.success ? "checkmark.circle" : "xmark.circle",
                        color: lastBuild.success ? .green : .red
                    )
                }
            }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }
}

@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
struct BuildScriptsCard: View {
    let scripts: [BuildScript]
    let onCommandSelected: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "list.bullet")
                    .font(.title2)
                    .foregroundColor(.green)

                Text("Build Scripts")
                    .font(.headline)
                    .fontWeight(.medium)

                Spacer()
            }

            VStack(spacing: 8) {
                ForEach(scripts, id: \.name) { script in
                    Button(action: {
                        onCommandSelected(script.command)
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(script.name)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)

                                Text(script.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Text(script.command)
                                    .font(.caption2)
                                    .fontDesign(.monospaced)
                                    .foregroundColor(.blue)
                            }

                            Spacer()

                            Image(systemName: "play.circle")
                                .foregroundColor(.green)
                        }
                        .padding()
                        .background(Color.gray.opacity(0.05))
                        .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
    }
}

@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
struct BuildResultsCard: View {
    let result: BuildResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(result.success ? .green : .red)

                Text("Build Results")
                    .font(.headline)
                    .fontWeight(.medium)

                Spacer()

                Text(result.timestamp, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Duration:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(String(format: "%.1fs", result.duration))
                        .font(.caption)
                        .fontWeight(.medium)

                    Spacer()

                    if !result.errors.isEmpty {
                        Text("\(result.errors.count) errors")
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    if !result.warnings.isEmpty {
                        Text("\(result.warnings.count) warnings")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }

                if !result.output.isEmpty {
                    Text("Output:")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    Text(result.output)
                        .font(.caption2)
                        .fontDesign(.monospaced)
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(6)
                }

                if !result.errors.isEmpty {
                    Text("Errors:")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.red)

                    ForEach(result.errors.prefix(3), id: \.message) { error in
                        Text(error.message)
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .padding()
        .background(result.success ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Tests Tab

@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
struct TestsTabView: View {
    let testSuites: [TestSuite]
    let onCommandSelected: (String) -> Void

    var body: some View {
        VStack(spacing: 16) {
            if !testSuites.isEmpty {
                ForEach(testSuites, id: \.name) { testSuite in
                    TestSuiteCard(testSuite: testSuite, onCommandSelected: onCommandSelected)
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "testtube.2")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)

                    Text("No Tests Found")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Text("No test suites detected in this project")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
    }
}

@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
struct TestSuiteCard: View {
    let testSuite: TestSuite
    let onCommandSelected: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: testSuite.type.icon)
                    .font(.title2)
                    .foregroundColor(.green)

                Text(testSuite.name)
                    .font(.headline)
                    .fontWeight(.medium)

                Spacer()

                Button("Run Tests") {
                    onCommandSelected("Run \(testSuite.name)")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if let results = testSuite.lastResults {
                TestResultsView(results: results)
            }

            if let coverage = testSuite.coverage {
                TestCoverageView(coverage: coverage)
            }
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
    }
}

@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
struct TestResultsView: View {
    let results: TestResults

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Last Run:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(results.timestamp, style: .relative)
                    .font(.caption)
                    .fontWeight(.medium)

                Spacer()

                Text(String(format: "%.1fs", results.duration))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                TestMetric(label: "Total", value: results.totalTests, color: .blue)
                TestMetric(label: "Passed", value: results.passedTests, color: .green)
                TestMetric(label: "Failed", value: results.failedTests, color: .red)
                if results.skippedTests > 0 {
                    TestMetric(label: "Skipped", value: results.skippedTests, color: .orange)
                }
            }

            if !results.failedTestCases.isEmpty {
                Text("Failed Tests:")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.red)

                ForEach(results.failedTestCases.prefix(3), id: \.name) { failedTest in
                    Text("• \(failedTest.name)")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }
        }
    }
}

@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
struct TestMetric: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(color)

            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
struct TestCoverageView: View {
    let coverage: TestCoverage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Code Coverage")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)

                Spacer()

                Text(String(format: "%.1f%%", coverage.percentage))
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(coverageColor)
            }

            ProgressView(value: coverage.percentage, total: 100)
                .progressViewStyle(LinearProgressViewStyle(tint: coverageColor))

            HStack {
                Text("\(coverage.linesCovered) / \(coverage.totalLines) lines")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()
            }
        }
    }

    private var coverageColor: Color {
        if coverage.percentage >= 80 {
            return .green
        } else if coverage.percentage >= 60 {
            return .orange
        } else {
            return .red
        }
    }
}

@available(iOS 17.0, iPadOS 17.0, macOS 14.0, *)
#Preview {
    DevelopmentWorkflowView(
        workflowService: DevelopmentWorkflowService(workingDirectory: "/Users/test/project"),
        onCommandSelected: { _ in }
    )
}
