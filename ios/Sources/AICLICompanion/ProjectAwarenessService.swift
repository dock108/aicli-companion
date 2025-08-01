import Foundation
import SwiftUI

// MARK: - Project Models

struct ProjectContext {
    let type: ProjectType
    let language: String?
    let framework: String?
    let buildSystem: String?
    let packageManager: String?
    let configFiles: [String]
    let suggestions: [ProjectSuggestion]
    let workingDirectory: String
    let detectedFiles: [String]
}

enum ProjectType: String, CaseIterable {
    case swift = "Swift"
    case javascript = "JavaScript"
    case typescript = "TypeScript"
    case python = "Python"
    case react = "React"
    case reactNative = "React Native"
    case vue = "Vue.js"
    case angular = "Angular"
    case nodejs = "Node.js"
    case ios = "iOS"
    case android = "Android"
    case flutter = "Flutter"
    case web = "Web"
    case rust = "Rust"
    case go = "Go"
    case java = "Java"
    case kotlin = "Kotlin"
    case csharp = "C#"
    case cpp = "C++"
    case php = "PHP"
    case ruby = "Ruby"
    case unknown = "Unknown"

    var icon: String {
        switch self {
        case .swift, .ios: return "swift"
        case .javascript, .nodejs: return "js.square"
        case .typescript: return "ts.square"
        case .python: return "py.square"
        case .react, .reactNative: return "r.square"
        case .vue: return "v.square"
        case .angular: return "a.square"
        case .web: return "globe"
        case .rust: return "r.square.fill"
        case .go: return "g.square"
        case .java: return "j.square"
        case .kotlin: return "k.square"
        case .android: return "android"
        case .flutter: return "f.square"
        case .csharp: return "c.square"
        case .cpp: return "plus.square"
        case .php: return "p.square"
        case .ruby: return "r.square"
        case .unknown: return "questionmark.square"
        }
    }

    var color: Color {
        switch self {
        case .swift, .ios: return .orange
        case .javascript, .nodejs: return .yellow
        case .typescript: return .blue
        case .python: return .green
        case .react, .reactNative: return .cyan
        case .vue: return .green
        case .angular: return .red
        case .web: return .blue
        case .rust: return .orange
        case .go: return .cyan
        case .java: return .red
        case .kotlin: return .purple
        case .android: return .green
        case .flutter: return .blue
        case .csharp: return .purple
        case .cpp: return .blue
        case .php: return .purple
        case .ruby: return .red
        case .unknown: return .gray
        }
    }
}

struct ProjectSuggestion {
    let id: UUID = UUID()
    let title: String
    let description: String
    let command: String?
    let category: SuggestionCategory
    let priority: SuggestionPriority
    let icon: String

    init(title: String, description: String, command: String? = nil, category: SuggestionCategory, priority: SuggestionPriority = .medium, icon: String) {
        self.title = title
        self.description = description
        self.command = command
        self.category = category
        self.priority = priority
        self.icon = icon
    }
}

enum SuggestionCategory: String, CaseIterable {
    case build = "Build"
    case test = "Test"
    case debug = "Debug"
    case deploy = "Deploy"
    case analyze = "Analyze"
    case setup = "Setup"
    case documentation = "Documentation"
    case maintenance = "Maintenance"
}

enum SuggestionPriority: Int, CaseIterable {
    case low = 1
    case medium = 2
    case high = 3
    case critical = 4
}

// MARK: - Project Awareness Service

@available(iOS 16.0, macOS 13.0, *)
class ProjectAwarenessService: ObservableObject {
    @Published var currentProject: ProjectContext?
    @Published var recentProjects: [ProjectContext] = []

    private let maxRecentProjects = 10

    func analyzeProject(at workingDirectory: String) -> ProjectContext? {
        // Simulate file system analysis (in real app, would use actual file detection)
        let projectContext = detectProjectType(in: workingDirectory)

        DispatchQueue.main.async {
            self.currentProject = projectContext
            self.addToRecentProjects(projectContext)
        }

        return projectContext
    }

    private func detectProjectType(in directory: String) -> ProjectContext {
        var detectedFiles: [String] = []
        var configFiles: [String] = []

        // Simulate file detection based on common project patterns
        let projectAnalysis = analyzeDirectoryPatterns(directory)

        let projectType = determineProjectType(from: projectAnalysis)
        let language = determineLanguage(from: projectAnalysis)
        let framework = determineFramework(from: projectAnalysis)
        let buildSystem = determineBuildSystem(from: projectAnalysis)
        let packageManager = determinePackageManager(from: projectAnalysis)

        detectedFiles = projectAnalysis.detectedFiles
        configFiles = projectAnalysis.configFiles

        let suggestions = generateSuggestions(for: projectType, language: language, framework: framework)

        return ProjectContext(
            type: projectType,
            language: language,
            framework: framework,
            buildSystem: buildSystem,
            packageManager: packageManager,
            configFiles: configFiles,
            suggestions: suggestions,
            workingDirectory: directory,
            detectedFiles: detectedFiles
        )
    }

    private func analyzeDirectoryPatterns(_ directory: String) -> ProjectAnalysis {
        // Simulate project analysis based on directory path patterns
        let directoryName = (directory as NSString).lastPathComponent.lowercased()
        let pathComponents = directory.components(separatedBy: "/")

        var detectedFiles: [String] = []
        var configFiles: [String] = []

        // Simulate common file patterns
        if directoryName.contains("ios") || directory.contains(".xcodeproj") {
            detectedFiles.append("Package.swift")
            detectedFiles.append("Podfile")
            configFiles.append("Info.plist")
        }

        if directoryName.contains("react") || directoryName.contains("next") {
            detectedFiles.append("package.json")
            detectedFiles.append("tsconfig.json")
            configFiles.append("next.config.js")
        }

        if directoryName.contains("python") || directoryName.contains("django") {
            detectedFiles.append("requirements.txt")
            detectedFiles.append("setup.py")
            configFiles.append("pyproject.toml")
        }

        if directoryName.contains("node") || directoryName.contains("npm") {
            detectedFiles.append("package.json")
            detectedFiles.append("yarn.lock")
            configFiles.append("webpack.config.js")
        }

        return ProjectAnalysis(
            detectedFiles: detectedFiles,
            configFiles: configFiles,
            directoryName: directoryName,
            pathComponents: pathComponents
        )
    }

    private func determineProjectType(from analysis: ProjectAnalysis) -> ProjectType {
        let files = analysis.detectedFiles
        let dirName = analysis.directoryName

        // iOS/Swift detection
        if files.contains("Package.swift") || files.contains("Podfile") || dirName.contains("ios") {
            return .ios
        }

        // React detection
        if files.contains("package.json") && (dirName.contains("react") || dirName.contains("next")) {
            return .react
        }

        // Node.js detection
        if files.contains("package.json") && !dirName.contains("react") {
            return .nodejs
        }

        // Python detection
        if files.contains("requirements.txt") || files.contains("setup.py") {
            return .python
        }

        // TypeScript detection
        if files.contains("tsconfig.json") {
            return .typescript
        }

        // Default based on directory name patterns
        if dirName.contains("swift") { return .swift }
        if dirName.contains("python") { return .python }
        if dirName.contains("javascript") || dirName.contains("js") { return .javascript }
        if dirName.contains("react") { return .react }
        if dirName.contains("vue") { return .vue }
        if dirName.contains("angular") { return .angular }
        if dirName.contains("flutter") { return .flutter }
        if dirName.contains("android") { return .android }
        if dirName.contains("rust") { return .rust }
        if dirName.contains("go") { return .go }
        if dirName.contains("java") { return .java }

        return .unknown
    }

    private func determineLanguage(from analysis: ProjectAnalysis) -> String? {
        switch determineProjectType(from: analysis) {
        case .swift, .ios: return "Swift"
        case .javascript, .nodejs, .react, .vue, .angular: return "JavaScript"
        case .typescript: return "TypeScript"
        case .python: return "Python"
        case .rust: return "Rust"
        case .go: return "Go"
        case .java, .android: return "Java"
        case .kotlin: return "Kotlin"
        case .csharp: return "C#"
        case .cpp: return "C++"
        case .php: return "PHP"
        case .ruby: return "Ruby"
        default: return nil
        }
    }

    private func determineFramework(from analysis: ProjectAnalysis) -> String? {
        let dirName = analysis.directoryName

        if dirName.contains("react") { return "React" }
        if dirName.contains("vue") { return "Vue.js" }
        if dirName.contains("angular") { return "Angular" }
        if dirName.contains("next") { return "Next.js" }
        if dirName.contains("express") { return "Express.js" }
        if dirName.contains("django") { return "Django" }
        if dirName.contains("flask") { return "Flask" }
        if dirName.contains("fastapi") { return "FastAPI" }
        if dirName.contains("rails") { return "Ruby on Rails" }
        if dirName.contains("spring") { return "Spring" }
        if dirName.contains("flutter") { return "Flutter" }

        return nil
    }

    private func determineBuildSystem(from analysis: ProjectAnalysis) -> String? {
        let files = analysis.detectedFiles

        if files.contains("Package.swift") { return "Swift Package Manager" }
        if files.contains("Podfile") { return "CocoaPods" }
        if files.contains("package.json") { return "npm/yarn" }
        if files.contains("Cargo.toml") { return "Cargo" }
        if files.contains("go.mod") { return "Go Modules" }
        if files.contains("pom.xml") { return "Maven" }
        if files.contains("build.gradle") { return "Gradle" }
        if files.contains("Makefile") { return "Make" }
        if files.contains("CMakeLists.txt") { return "CMake" }

        return nil
    }

    private func determinePackageManager(from analysis: ProjectAnalysis) -> String? {
        let files = analysis.detectedFiles

        if files.contains("yarn.lock") { return "Yarn" }
        if files.contains("package-lock.json") { return "npm" }
        if files.contains("pnpm-lock.yaml") { return "pnpm" }
        if files.contains("Pipfile") { return "Pipenv" }
        if files.contains("poetry.lock") { return "Poetry" }
        if files.contains("requirements.txt") { return "pip" }
        if files.contains("Gemfile") { return "Bundler" }
        if files.contains("composer.json") { return "Composer" }

        return nil
    }

    private func generateSuggestions(for projectType: ProjectType, language: String?, framework: String?) -> [ProjectSuggestion] {
        var suggestions: [ProjectSuggestion] = []

        // Common suggestions for all projects
        suggestions.append(contentsOf: [
            ProjectSuggestion(
                title: "List Files",
                description: "Show all files in the project",
                command: "find . -type f -name '*.swift' -o -name '*.js' -o -name '*.py' | head -20",
                category: .analyze,
                icon: "doc.text"
            ),
            ProjectSuggestion(
                title: "Project Structure",
                description: "Analyze the project directory structure",
                command: "tree -L 3 -I 'node_modules|.git|build|dist'",
                category: .analyze,
                icon: "folder.tree"
            )
        ])

        // Project-specific suggestions
        switch projectType {
        case .swift, .ios:
            suggestions.append(contentsOf: [
                ProjectSuggestion(
                    title: "Build Project",
                    description: "Build the Swift project",
                    command: "swift build",
                    category: .build,
                    priority: .high,
                    icon: "hammer"
                ),
                ProjectSuggestion(
                    title: "Run Tests",
                    description: "Execute unit tests",
                    command: "swift test",
                    category: .test,
                    priority: .high,
                    icon: "testtube.2"
                ),
                ProjectSuggestion(
                    title: "Check Dependencies",
                    description: "List package dependencies",
                    command: "swift package show-dependencies",
                    category: .analyze,
                    icon: "link"
                )
            ])

        case .javascript, .nodejs, .react, .typescript:
            suggestions.append(contentsOf: [
                ProjectSuggestion(
                    title: "Install Dependencies",
                    description: "Install npm packages",
                    command: "npm install",
                    category: .setup,
                    priority: .high,
                    icon: "arrow.down.circle"
                ),
                ProjectSuggestion(
                    title: "Run Development Server",
                    description: "Start the development server",
                    command: "npm run dev",
                    category: .build,
                    priority: .high,
                    icon: "play"
                ),
                ProjectSuggestion(
                    title: "Run Tests",
                    description: "Execute test suite",
                    command: "npm test",
                    category: .test,
                    icon: "testtube.2"
                ),
                ProjectSuggestion(
                    title: "Check for Updates",
                    description: "Check for outdated packages",
                    command: "npm outdated",
                    category: .maintenance,
                    icon: "arrow.up.circle"
                )
            ])

        case .python:
            suggestions.append(contentsOf: [
                ProjectSuggestion(
                    title: "Install Requirements",
                    description: "Install Python dependencies",
                    command: "pip install -r requirements.txt",
                    category: .setup,
                    priority: .high,
                    icon: "arrow.down.circle"
                ),
                ProjectSuggestion(
                    title: "Run Application",
                    description: "Start the Python application",
                    command: "python main.py",
                    category: .build,
                    icon: "play"
                ),
                ProjectSuggestion(
                    title: "Run Tests",
                    description: "Execute pytest suite",
                    command: "pytest",
                    category: .test,
                    icon: "testtube.2"
                ),
                ProjectSuggestion(
                    title: "Check Code Style",
                    description: "Run code formatting check",
                    command: "black --check .",
                    category: .analyze,
                    icon: "textformat"
                )
            ])

        case .rust:
            suggestions.append(contentsOf: [
                ProjectSuggestion(
                    title: "Build Project",
                    description: "Compile Rust project",
                    command: "cargo build",
                    category: .build,
                    priority: .high,
                    icon: "hammer"
                ),
                ProjectSuggestion(
                    title: "Run Project",
                    description: "Build and run the project",
                    command: "cargo run",
                    category: .build,
                    icon: "play"
                ),
                ProjectSuggestion(
                    title: "Run Tests",
                    description: "Execute Rust tests",
                    command: "cargo test",
                    category: .test,
                    icon: "testtube.2"
                )
            ])

        case .go:
            suggestions.append(contentsOf: [
                ProjectSuggestion(
                    title: "Build Project",
                    description: "Build Go application",
                    command: "go build",
                    category: .build,
                    priority: .high,
                    icon: "hammer"
                ),
                ProjectSuggestion(
                    title: "Run Project",
                    description: "Run Go application",
                    command: "go run .",
                    category: .build,
                    icon: "play"
                ),
                ProjectSuggestion(
                    title: "Run Tests",
                    description: "Execute Go tests",
                    command: "go test ./...",
                    category: .test,
                    icon: "testtube.2"
                )
            ])

        default:
            break
        }

        return suggestions.sorted { $0.priority.rawValue > $1.priority.rawValue }
    }

    private func addToRecentProjects(_ project: ProjectContext) {
        // Remove if already exists
        recentProjects.removeAll { $0.workingDirectory == project.workingDirectory }

        // Add to front
        recentProjects.insert(project, at: 0)

        // Keep only recent projects
        if recentProjects.count > maxRecentProjects {
            recentProjects = Array(recentProjects.prefix(maxRecentProjects))
        }
    }

    func getSuggestionsForCategory(_ category: SuggestionCategory) -> [ProjectSuggestion] {
        return currentProject?.suggestions.filter { $0.category == category } ?? []
    }

    func getHighPrioritySuggestions() -> [ProjectSuggestion] {
        return currentProject?.suggestions.filter { $0.priority == .high || $0.priority == .critical } ?? []
    }
}

// MARK: - Supporting Types

private struct ProjectAnalysis {
    let detectedFiles: [String]
    let configFiles: [String]
    let directoryName: String
    let pathComponents: [String]
}
