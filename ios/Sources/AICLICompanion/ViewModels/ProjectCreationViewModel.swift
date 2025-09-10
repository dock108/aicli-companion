//
//  ProjectCreationViewModel.swift
//  AICLICompanion
//
//  Created on 2025-09-04.
//

import Foundation
import SwiftUI
import Combine

// MARK: - Enums

enum ProjectCreationType: String, CaseIterable {
    case webApp = "Web Application"
    case mobileApp = "Mobile Application"
    case apiService = "API Service"
    case cliTool = "CLI Tool"

    var description: String {
        switch self {
        case .webApp:
            return "Full-stack web application with frontend and backend"
        case .mobileApp:
            return "Native or cross-platform mobile application"
        case .apiService:
            return "RESTful or GraphQL API service"
        case .cliTool:
            return "Command-line interface tool"
        }
    }

    var apiValue: String {
        switch self {
        case .webApp: return "web-app"
        case .mobileApp: return "mobile-app"
        case .apiService: return "api-service"
        case .cliTool: return "cli-tool"
        }
    }

    var serverValue: String {
        return apiValue
    }
}

enum TechStack: String, CaseIterable, Identifiable {
    case nodeJS = "Node.js"
    case python = "Python"
    case ruby = "Ruby"
    case go = "Go"
    case rust = "Rust"
    case java = "Java"
    case dotnet = ".NET"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .nodeJS: return "server.rack"
        case .python: return "chevron.left.forwardslash.chevron.right"
        case .ruby: return "diamond"
        case .go: return "bolt.horizontal"
        case .rust: return "gear"
        case .java: return "cup.and.saucer"
        case .dotnet: return "square.grid.3x3"
        }
    }
}

enum TeamSize: String, CaseIterable {
    case solo = "Solo"
    case small = "Small"
    case medium = "Medium"
    case large = "Large"
}

enum Architecture: String, CaseIterable {
    case monolith = "Monolith"
    case microservices = "Microservices"
    case serverless = "Serverless"
}

struct ProjectReadinessLevel {
    let level: String
    let label: String
    let icon: String
    let description: String
    let color: Color
    let canProceed: Bool

    static let notReady = ProjectReadinessLevel(
        level: "not-ready",
        label: "Not Ready",
        icon: "🛑",
        description: "Insufficient planning, comprehensive requirements needed",
        color: .red,
        canProceed: false
    )

    static let planningNeeded = ProjectReadinessLevel(
        level: "planning-needed",
        label: "More Planning Needed",
        icon: "📝",
        description: "Significant gaps in requirements",
        color: .orange,
        canProceed: false
    )

    static let prototypeReady = ProjectReadinessLevel(
        level: "prototype-ready",
        label: "Prototype Ready",
        icon: "🔨",
        description: "Sufficient for prototyping",
        color: .yellow,
        canProceed: true
    )

    static let developmentReady = ProjectReadinessLevel(
        level: "development-ready",
        label: "Development Ready",
        icon: "✅",
        description: "Ready to start development",
        color: Color.green.opacity(0.8),
        canProceed: true
    )

    static let productionReady = ProjectReadinessLevel(
        level: "production-ready",
        label: "Production Ready",
        icon: "🚀",
        description: "Fully specified and ready",
        color: .green,
        canProceed: true
    )

    // Aliases for backward compatibility
    static let ready = productionReady
    static let almostReady = developmentReady
    static let needsWork = planningNeeded
}

struct Template: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let description: String
    let isRequired: Bool
}

struct ProjectDomainScore: Identifiable {
    let id = UUID()
    let domain: String
    let icon: String
    let score: Int
}

// MARK: - View Model

@MainActor
class ProjectCreationViewModel: ObservableObject {
    // Project details
    @Published var projectName = ""
    @Published var projectDescription = ""
    @Published var author = ""
    @Published var projectType = ProjectCreationType.webApp
    @Published var techStack = TechStack.nodeJS
    @Published var teamSize = TeamSize.small
    @Published var architecture = Architecture.monolith

    // Options
    @Published var includeDocker = false
    @Published var includeCICD = false
    @Published var initGit = true

    // Templates
    @Published var availableTemplates: [Template] = []
    @Published var selectedTemplates = Set<String>()

    // Readiness
    @Published var readinessScore = 0
    @Published var readinessLevel = ProjectReadinessLevel.notReady
    @Published var domainScores: [ProjectDomainScore] = []
    @Published var missingRequirements: [String] = []
    @Published var suggestions: [String] = []

    // State
    @Published var isCreating = false
    @Published var creationError: String?
    @Published var creationSuccessful = false
    @Published var hasUnsavedChanges = false

    private let networkService = NetworkService.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupBindings()
        loadDefaultAuthor()
    }

    private func setupBindings() {
        // Monitor changes
        Publishers.CombineLatest4(
            $projectName,
            $projectDescription,
            $projectType,
            $techStack
        )
        .sink { [weak self] _ in
            self?.hasUnsavedChanges = true
            self?.updateReadinessAssessment()
        }
        .store(in: &cancellables)
    }

    private func loadDefaultAuthor() {
        if let savedAuthor = UserDefaults.standard.string(forKey: "projectAuthor") {
            author = savedAuthor
        } else {
            author = NSFullUserName()
        }
    }

    func loadAvailableTemplates() {
        // In a real implementation, this would fetch from the server
        availableTemplates = [
            Template(name: ".gitignore", description: "Git ignore patterns", isRequired: false),
            Template(name: "Dockerfile", description: "Docker container configuration", isRequired: false),
            Template(name: ".env.example", description: "Environment variables template", isRequired: false),
            Template(name: "package.json", description: "Node.js package configuration", isRequired: false),
            Template(name: ".github/workflows/ci.yml", description: "GitHub Actions CI/CD", isRequired: false)
        ]

        // Auto-select recommended templates based on configuration
        if includeDocker {
            selectedTemplates.insert("Dockerfile")
        }
        if includeCICD {
            selectedTemplates.insert(".github/workflows/ci.yml")
        }
        if techStack == .nodeJS {
            selectedTemplates.insert("package.json")
        }
    }

    func canProceedToStep(_ step: Int) -> Bool {
        switch step {
        case 1:
            return !projectName.isEmpty && projectName.count >= 3
        case 2:
            return true // Configuration step always accessible
        case 3:
            return true // Template step always accessible
        case 4:
            return !projectName.isEmpty && !author.isEmpty
        default:
            return false
        }
    }

    var isReadyToCreate: Bool {
        !projectName.isEmpty && !author.isEmpty && readinessLevel.canProceed
    }

    var selectedTemplateNames: [String] {
        // Core templates are always included
        var templates = ["CLAUDE.md", "plan.md", "README.md"]
        templates.append(contentsOf: selectedTemplates.sorted())
        return templates
    }

    private func calculateConfigurationScore() -> Int {
        var score = 0
        var maxScore = 0

        // Tech stack selection (25 points if non-default)
        maxScore += 25
        if techStack != .nodeJS {
            score += 25
        }

        // Team size selection (15 points if specified)
        maxScore += 15
        if teamSize != .small {
            score += 15
        }

        // Architecture selection (15 points if non-default)
        maxScore += 15
        if architecture != .monolith {
            score += 15
        }

        // Docker option (20 points)
        maxScore += 20
        if includeDocker {
            score += 20
        }

        // CI/CD option (20 points)
        maxScore += 20
        if includeCICD {
            score += 20
        }

        // Git initialization (5 points)
        maxScore += 5
        if initGit {
            score += 5
        }

        return maxScore > 0 ? Int((Double(score) / Double(maxScore)) * 100) : 50
    }

    private func updateReadinessAssessment() {
        // Simple readiness calculation based on filled fields
        var score = 0

        if !projectName.isEmpty { score += 20 }
        if !projectDescription.isEmpty { score += 15 }
        if !author.isEmpty { score += 10 }
        if techStack != .nodeJS { score += 10 } // Non-default selection
        if includeDocker { score += 10 }
        if includeCICD { score += 10 }
        if !selectedTemplates.isEmpty {
            let templateRatio = Double(selectedTemplates.count) / Double(max(availableTemplates.count, 1))
            score += Int(15 * templateRatio)
        }
        if initGit { score += 10 }

        readinessScore = min(100, score)

        // Update readiness level
        switch readinessScore {
        case 90...100:
            readinessLevel = .productionReady
        case 75...89:
            readinessLevel = .developmentReady
        case 60...74:
            readinessLevel = .prototypeReady
        case 40...59:
            readinessLevel = .planningNeeded
        default:
            readinessLevel = .notReady
        }

        // Update domain scores (mock data for now)
        domainScores = [
            ProjectDomainScore(domain: "Project Structure", icon: "📁", score: projectName.isEmpty ? 0 : 100),
            ProjectDomainScore(domain: "Configuration", icon: "⚙️", score: calculateConfigurationScore()),
            ProjectDomainScore(domain: "Templates", icon: "📄", score: availableTemplates.isEmpty ? 50 : Int((Double(selectedTemplates.count) / Double(availableTemplates.count)) * 100)),
            ProjectDomainScore(domain: "Documentation", icon: "📚", score: projectDescription.isEmpty ? 0 : 80)
        ]

        // Update missing requirements
        missingRequirements = []
        if projectDescription.isEmpty {
            missingRequirements.append("Project description is missing")
        }
        if selectedTemplates.isEmpty {
            missingRequirements.append("No additional templates selected")
        }

        // Update suggestions
        suggestions = []
        if !includeDocker {
            suggestions.append("Consider adding Docker for containerization")
        }
        if !includeCICD {
            suggestions.append("Add CI/CD pipeline for automated testing")
        }
    }

    func createProject() async {
        isCreating = true
        creationError = nil

        // Save author preference
        UserDefaults.standard.set(author, forKey: "projectAuthor")

        // Prepare project configuration
        let config: [String: Any] = [
            "projectName": projectName,
            "projectDescription": projectDescription,
            "projectType": projectType.apiValue,
            "techStack": techStack.rawValue,
            "teamSize": teamSize.rawValue.lowercased(),
            "author": author,
            "initGit": initGit,
            "includeDocker": includeDocker,
            "includeCICD": includeCICD,
            "selectedTemplates": Array(selectedTemplates)
        ]

        do {
            let endpoint = "/api/projects"
            let response = try await networkService.post(endpoint: endpoint, body: config)

            if let success = response["success"] as? Bool, success {
                creationSuccessful = true
                hasUnsavedChanges = false

                // Post notification for project list refresh
                NotificationCenter.default.post(
                    name: NSNotification.Name("ProjectCreated"),
                    object: nil,
                    userInfo: ["projectName": projectName]
                )
            } else {
                creationError = response["error"] as? String ?? "Failed to create project"
            }
        } catch {
            creationError = error.localizedDescription
        }

        isCreating = false
    }
}

// MARK: - Error View

struct ErrorView: View {
    let message: String

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.red)
            Text(message)
                .foregroundStyle(.red)
                .font(.caption)
            Spacer()
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }
}
