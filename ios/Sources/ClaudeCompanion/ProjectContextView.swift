import SwiftUI

struct ProjectContextBanner: View {
    let project: ProjectContext
    @State private var isExpanded = false

    let onSuggestionTap: (ProjectSuggestion) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Compact banner
            HStack(spacing: 8) {
                Image(systemName: project.type.icon)
                    .foregroundColor(project.type.color)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(project.type.rawValue)
                        .font(.headline)
                        .fontWeight(.medium)

                    HStack(spacing: 4) {
                        if let language = project.language {
                            Text(language)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if let framework = project.framework {
                            Text("• \(framework)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                // Quick suggestions count
                if !project.suggestions.isEmpty {
                    HStack(spacing: 4) {
                        Text("\(project.suggestions.count)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(project.type.color)

                        Image(systemName: "lightbulb")
                            .font(.caption)
                            .foregroundColor(project.type.color)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(project.type.color.opacity(0.1))
                    .cornerRadius(8)
                }

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(project.type.color.opacity(0.05))
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isExpanded.toggle()
                }
            }

            // Expanded content
            if isExpanded {
                VStack(spacing: 12) {
                    Divider()

                    // Project details
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Project Details")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Spacer()
                        }

                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 8) {
                            if let buildSystem = project.buildSystem {
                                ProjectDetailItem(label: "Build System", value: buildSystem, icon: "hammer")
                            }

                            if let packageManager = project.packageManager {
                                ProjectDetailItem(label: "Package Manager", value: packageManager, icon: "shippingbox")
                            }

                            if !project.configFiles.isEmpty {
                                ProjectDetailItem(label: "Config Files", value: "\(project.configFiles.count) found", icon: "gearshape")
                            }

                            ProjectDetailItem(label: "Directory", value: (project.workingDirectory as NSString).lastPathComponent, icon: "folder")
                        }
                    }
                    .padding(.horizontal, 16)

                    // High priority suggestions
                    let highPrioritySuggestions = project.suggestions.filter { $0.priority == .high || $0.priority == .critical }
                    if !highPrioritySuggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Quick Actions")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                            }
                            .padding(.horizontal, 16)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(highPrioritySuggestions.prefix(4), id: \.id) { suggestion in
                                        SuggestionCard(suggestion: suggestion) {
                                            onSuggestionTap(suggestion)
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }

                    // All suggestions by category
                    let groupedSuggestions = Dictionary(grouping: project.suggestions) { $0.category }
                    if !groupedSuggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("All Suggestions")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                            }
                            .padding(.horizontal, 16)

                            ForEach(SuggestionCategory.allCases, id: \.self) { category in
                                if let suggestions = groupedSuggestions[category], !suggestions.isEmpty {
                                    SuggestionCategorySection(
                                        category: category,
                                        suggestions: suggestions,
                                        onSuggestionTap: onSuggestionTap
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 16)
                .background(project.type.color.opacity(0.02))
            }
        }
        .background(project.type.color.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(project.type.color.opacity(0.2), lineWidth: 1)
        )
    }
}

struct ProjectDetailItem: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text(value)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(8)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(6)
    }
}

struct SuggestionCard: View {
    let suggestion: ProjectSuggestion
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: suggestion.icon)
                        .font(.title3)
                        .foregroundColor(priorityColor)

                    Spacer()

                    priorityBadge
                }

                Text(suggestion.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)

                Text(suggestion.description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
            }
            .padding(12)
            .frame(width: 140, height: 100)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(priorityColor.opacity(0.3), lineWidth: 1)
            )
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

    private var priorityBadge: some View {
        Circle()
            .fill(priorityColor)
            .frame(width: 6, height: 6)
    }
}

struct SuggestionCategorySection: View {
    let category: SuggestionCategory
    let suggestions: [ProjectSuggestion]
    let onSuggestionTap: (ProjectSuggestion) -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Text(category.rawValue)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    Text("(\(suggestions.count))")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())

            if isExpanded {
                VStack(spacing: 4) {
                    ForEach(suggestions, id: \.id) { suggestion in
                        SuggestionRow(suggestion: suggestion) {
                            onSuggestionTap(suggestion)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

struct SuggestionRow: View {
    let suggestion: ProjectSuggestion
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: suggestion.icon)
                    .font(.body)
                    .foregroundColor(priorityColor)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .multilineTextAlignment(.leading)

                    Text(suggestion.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)

                    if let command = suggestion.command {
                        Text(command)
                            .font(.caption2)
                            .fontFamily(.monospaced)
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)
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

struct ProjectContextSheet: View {
    let project: ProjectContext
    @Environment(\.dismiss) private var dismiss

    let onSuggestionTap: (ProjectSuggestion) -> Void

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Project header
                    VStack(spacing: 12) {
                        Image(systemName: project.type.icon)
                            .font(.largeTitle)
                            .foregroundColor(project.type.color)

                        Text(project.type.rawValue)
                            .font(.title)
                            .fontWeight(.bold)

                        if let language = project.language {
                            Text(language)
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }

                        Text(project.workingDirectory)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .background(project.type.color.opacity(0.1))
                    .cornerRadius(12)

                    // Project details
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Project Information")
                            .font(.headline)
                            .padding(.horizontal)

                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            if let framework = project.framework {
                                ProjectDetailItem(label: "Framework", value: framework, icon: "cpu")
                            }

                            if let buildSystem = project.buildSystem {
                                ProjectDetailItem(label: "Build System", value: buildSystem, icon: "hammer")
                            }

                            if let packageManager = project.packageManager {
                                ProjectDetailItem(label: "Package Manager", value: packageManager, icon: "shippingbox")
                            }

                            ProjectDetailItem(label: "Config Files", value: "\(project.configFiles.count)", icon: "gearshape")
                        }
                        .padding(.horizontal)
                    }

                    // Suggestions by category
                    let groupedSuggestions = Dictionary(grouping: project.suggestions) { $0.category }
                    ForEach(SuggestionCategory.allCases, id: \.self) { category in
                        if let suggestions = groupedSuggestions[category], !suggestions.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(category.rawValue)
                                    .font(.headline)
                                    .padding(.horizontal)

                                ForEach(suggestions, id: \.id) { suggestion in
                                    SuggestionRow(suggestion: suggestion) {
                                        onSuggestionTap(suggestion)
                                        dismiss()
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Project Context")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    let sampleProject = ProjectContext(
        type: .swift,
        language: "Swift",
        framework: "SwiftUI",
        buildSystem: "Swift Package Manager",
        packageManager: "SPM",
        configFiles: ["Package.swift", "Info.plist"],
        suggestions: [
            ProjectSuggestion(
                title: "Build Project",
                description: "Build the Swift project",
                command: "swift build",
                category: .build,
                priority: .high,
                icon: "hammer"
            )
        ],
        workingDirectory: "/Users/developer/MyProject",
        detectedFiles: ["Package.swift", "Sources/"]
    )

    ProjectContextBanner(project: sampleProject) { _ in }
}
