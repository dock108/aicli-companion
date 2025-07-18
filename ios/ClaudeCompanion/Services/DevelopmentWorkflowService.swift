import Foundation
import SwiftUI

// MARK: - Workflow Models

struct GitRepository {
    let path: String
    let currentBranch: String
    let remoteUrl: String?
    let hasUncommittedChanges: Bool
    let changedFiles: [GitFileChange]
    let recentCommits: [GitCommit]
    let branches: [String]
    let status: GitStatus
}

struct GitFileChange {
    let id = UUID()
    let path: String
    let status: GitFileStatus
    let additions: Int?
    let deletions: Int?
}

enum GitFileStatus: String, CaseIterable {
    case modified = "M"
    case added = "A"
    case deleted = "D"
    case renamed = "R"
    case copied = "C"
    case untracked = "??"
    case ignored = "!!"
    
    var icon: String {
        switch self {
        case .modified: return "pencil"
        case .added: return "plus"
        case .deleted: return "minus"
        case .renamed: return "arrow.right"
        case .copied: return "doc.on.doc"
        case .untracked: return "questionmark"
        case .ignored: return "eye.slash"
        }
    }
    
    var color: Color {
        switch self {
        case .modified: return .orange
        case .added: return .green
        case .deleted: return .red
        case .renamed: return .blue
        case .copied: return .purple
        case .untracked: return .gray
        case .ignored: return .secondary
        }
    }
}

struct GitCommit {
    let id = UUID()
    let hash: String
    let shortHash: String
    let message: String
    let author: String
    let date: Date
    let filesChanged: Int
}

struct GitStatus {
    let ahead: Int
    let behind: Int
    let hasConflicts: Bool
    let isClean: Bool
    let currentOperation: GitOperation?
}

enum GitOperation: String, CaseIterable {
    case merge = "merge"
    case rebase = "rebase"
    case cherryPick = "cherry-pick"
    case revert = "revert"
    case bisect = "bisect"
    
    var displayName: String {
        switch self {
        case .merge: return "Merging"
        case .rebase: return "Rebasing"
        case .cherryPick: return "Cherry-picking"
        case .revert: return "Reverting"
        case .bisect: return "Bisecting"
        }
    }
}

struct BuildSystem {
    let type: BuildSystemType
    let configFiles: [String]
    let availableTargets: [BuildTarget]
    let lastBuildResult: BuildResult?
    let buildScripts: [BuildScript]
}

enum BuildSystemType: String, CaseIterable {
    case xcode = "Xcode"
    case swiftPM = "Swift Package Manager"
    case npm = "npm"
    case yarn = "Yarn"
    case gradle = "Gradle"
    case maven = "Maven"
    case cargo = "Cargo"
    case cmake = "CMake"
    case make = "Make"
    case unknown = "Unknown"
    
    var icon: String {
        switch self {
        case .xcode: return "hammer.fill"
        case .swiftPM: return "swift"
        case .npm, .yarn: return "cube.box"
        case .gradle, .maven: return "building.2"
        case .cargo: return "crate"
        case .cmake, .make: return "gear.2"
        case .unknown: return "questionmark.square"
        }
    }
    
    var primaryCommands: [String] {
        switch self {
        case .xcode: return ["xcodebuild", "xcodebuild test"]
        case .swiftPM: return ["swift build", "swift test", "swift run"]
        case .npm: return ["npm install", "npm run build", "npm test", "npm start"]
        case .yarn: return ["yarn install", "yarn build", "yarn test", "yarn start"]
        case .gradle: return ["./gradlew build", "./gradlew test", "./gradlew run"]
        case .maven: return ["mvn compile", "mvn test", "mvn package"]
        case .cargo: return ["cargo build", "cargo test", "cargo run"]
        case .cmake: return ["cmake --build .", "ctest"]
        case .make: return ["make", "make test", "make install"]
        case .unknown: return []
        }
    }
}

struct BuildTarget {
    let name: String
    let type: BuildTargetType
    let platform: String?
    let configuration: String
}

enum BuildTargetType: String, CaseIterable {
    case executable = "executable"
    case library = "library"
    case framework = "framework"
    case test = "test"
    case app = "app"
}

struct BuildResult {
    let success: Bool
    let duration: TimeInterval
    let timestamp: Date
    let output: String
    let errors: [BuildError]
    let warnings: [BuildWarning]
}

struct BuildError {
    let file: String?
    let line: Int?
    let column: Int?
    let message: String
    let severity: ErrorSeverity
}

struct BuildWarning {
    let file: String?
    let line: Int?
    let message: String
}

enum ErrorSeverity: String, CaseIterable {
    case error = "error"
    case warning = "warning"
    case note = "note"
    
    var color: Color {
        switch self {
        case .error: return .red
        case .warning: return .orange
        case .note: return .blue
        }
    }
}

struct BuildScript {
    let name: String
    let command: String
    let description: String
    let category: BuildScriptCategory
}

enum BuildScriptCategory: String, CaseIterable {
    case build = "Build"
    case test = "Test"
    case deploy = "Deploy"
    case clean = "Clean"
    case format = "Format"
    case lint = "Lint"
    case documentation = "Documentation"
}

struct TestSuite {
    let name: String
    let type: TestType
    let testFiles: [String]
    let lastResults: TestResults?
    let coverage: TestCoverage?
}

enum TestType: String, CaseIterable {
    case unit = "Unit Tests"
    case integration = "Integration Tests"
    case ui = "UI Tests"
    case performance = "Performance Tests"
    case snapshot = "Snapshot Tests"
    
    var icon: String {
        switch self {
        case .unit: return "testtube.2"
        case .integration: return "link"
        case .ui: return "iphone"
        case .performance: return "speedometer"
        case .snapshot: return "camera"
        }
    }
}

struct TestResults {
    let totalTests: Int
    let passedTests: Int
    let failedTests: Int
    let skippedTests: Int
    let duration: TimeInterval
    let timestamp: Date
    let failedTestCases: [FailedTest]
}

struct FailedTest {
    let name: String
    let file: String?
    let line: Int?
    let message: String
    let duration: TimeInterval
}

struct TestCoverage {
    let linesCovered: Int
    let totalLines: Int
    let percentage: Double
    let fileCoverage: [FileCoverage]
}

struct FileCoverage {
    let file: String
    let linesCovered: Int
    let totalLines: Int
    let percentage: Double
}

// MARK: - Development Workflow Service

class DevelopmentWorkflowService: ObservableObject {
    @Published var currentRepository: GitRepository?
    @Published var buildSystem: BuildSystem?
    @Published var testSuites: [TestSuite] = []
    @Published var isAnalyzing = false
    @Published var workflowSuggestions: [WorkflowSuggestion] = []
    
    private var workingDirectory: String = ""
    
    init(workingDirectory: String = "") {
        self.workingDirectory = workingDirectory
        if !workingDirectory.isEmpty {
            analyzeWorkflow(in: workingDirectory)
        }
    }
    
    func updateWorkingDirectory(_ directory: String) {
        workingDirectory = directory
        analyzeWorkflow(in: directory)
    }
    
    func analyzeWorkflow(in directory: String) {
        isAnalyzing = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let gitRepo = self.analyzeGitRepository(in: directory)
            let buildSys = self.analyzeBuildSystem(in: directory)
            let tests = self.analyzeTestSuites(in: directory)
            let suggestions = self.generateWorkflowSuggestions(git: gitRepo, build: buildSys, tests: tests)
            
            DispatchQueue.main.async {
                self.currentRepository = gitRepo
                self.buildSystem = buildSys
                self.testSuites = tests
                self.workflowSuggestions = suggestions
                self.isAnalyzing = false
            }
        }
    }
    
    // MARK: - Git Analysis
    
    private func analyzeGitRepository(in directory: String) -> GitRepository? {
        // Simulate Git repository analysis
        guard directory.contains("git") || directory.contains("project") else { return nil }
        
        let mockChangedFiles = [
            GitFileChange(path: "src/main.swift", status: .modified),
            GitFileChange(path: "tests/MainTests.swift", status: .modified),
            GitFileChange(path: "README.md", status: .added),
            GitFileChange(path: "unused.swift", status: .deleted)
        ]
        
        let mockCommits = [
            GitCommit(hash: "a1b2c3d4", shortHash: "a1b2c3d", message: "Add new feature implementation", author: "Developer", date: Date().addingTimeInterval(-3600), filesChanged: 3),
            GitCommit(hash: "e5f6g7h8", shortHash: "e5f6g7h", message: "Fix critical bug in authentication", author: "Developer", date: Date().addingTimeInterval(-7200), filesChanged: 2),
            GitCommit(hash: "i9j0k1l2", shortHash: "i9j0k1l", message: "Update dependencies and documentation", author: "Developer", date: Date().addingTimeInterval(-86400), filesChanged: 5)
        ]
        
        let status = GitStatus(
            ahead: 2,
            behind: 0,
            hasConflicts: false,
            isClean: false,
            currentOperation: nil
        )
        
        return GitRepository(
            path: directory,
            currentBranch: "feature/mobile-companion",
            remoteUrl: "https://github.com/user/project.git",
            hasUncommittedChanges: true,
            changedFiles: mockChangedFiles,
            recentCommits: mockCommits,
            branches: ["main", "develop", "feature/mobile-companion", "hotfix/auth-fix"],
            status: status
        )
    }
    
    // MARK: - Build System Analysis
    
    private func analyzeBuildSystem(in directory: String) -> BuildSystem? {
        let directoryName = (directory as NSString).lastPathComponent.lowercased()
        
        var buildType: BuildSystemType = .unknown
        var configFiles: [String] = []
        
        // Determine build system based on directory patterns
        if directoryName.contains("ios") || directoryName.contains("swift") {
            buildType = .swiftPM
            configFiles = ["Package.swift", "Package.resolved"]
        } else if directoryName.contains("react") || directoryName.contains("node") {
            buildType = .npm
            configFiles = ["package.json", "package-lock.json"]
        } else if directoryName.contains("java") || directoryName.contains("android") {
            buildType = .gradle
            configFiles = ["build.gradle", "settings.gradle"]
        } else if directoryName.contains("rust") {
            buildType = .cargo
            configFiles = ["Cargo.toml", "Cargo.lock"]
        }
        
        let mockTargets = [
            BuildTarget(name: "App", type: .app, platform: "iOS", configuration: "Debug"),
            BuildTarget(name: "AppTests", type: .test, platform: "iOS", configuration: "Debug"),
            BuildTarget(name: "AppLibrary", type: .library, platform: "iOS", configuration: "Release")
        ]
        
        let mockScripts = generateBuildScripts(for: buildType)
        
        let lastBuildResult = BuildResult(
            success: true,
            duration: 45.2,
            timestamp: Date().addingTimeInterval(-1800),
            output: "Build completed successfully\n3 targets built\n0 errors, 2 warnings",
            errors: [],
            warnings: [
                BuildWarning(file: "src/main.swift", line: 42, message: "Variable 'unused' is never used"),
                BuildWarning(file: "src/utils.swift", line: 15, message: "Function parameter can be simplified")
            ]
        )
        
        return BuildSystem(
            type: buildType,
            configFiles: configFiles,
            availableTargets: mockTargets,
            lastBuildResult: lastBuildResult,
            buildScripts: mockScripts
        )
    }
    
    private func generateBuildScripts(for buildType: BuildSystemType) -> [BuildScript] {
        switch buildType {
        case .swiftPM:
            return [
                BuildScript(name: "Build", command: "swift build", description: "Build the Swift package", category: .build),
                BuildScript(name: "Test", command: "swift test", description: "Run all tests", category: .test),
                BuildScript(name: "Clean", command: "swift package clean", description: "Clean build artifacts", category: .clean),
                BuildScript(name: "Format", command: "swift-format --in-place --recursive Sources/", description: "Format source code", category: .format)
            ]
        case .npm:
            return [
                BuildScript(name: "Install", command: "npm install", description: "Install dependencies", category: .build),
                BuildScript(name: "Build", command: "npm run build", description: "Build for production", category: .build),
                BuildScript(name: "Test", command: "npm test", description: "Run test suite", category: .test),
                BuildScript(name: "Lint", command: "npm run lint", description: "Lint source code", category: .lint),
                BuildScript(name: "Dev", command: "npm run dev", description: "Start development server", category: .build)
            ]
        case .gradle:
            return [
                BuildScript(name: "Build", command: "./gradlew build", description: "Build the project", category: .build),
                BuildScript(name: "Test", command: "./gradlew test", description: "Run unit tests", category: .test),
                BuildScript(name: "Clean", command: "./gradlew clean", description: "Clean build directory", category: .clean),
                BuildScript(name: "Assemble", command: "./gradlew assemble", description: "Assemble the app", category: .build)
            ]
        case .cargo:
            return [
                BuildScript(name: "Build", command: "cargo build", description: "Build the Rust project", category: .build),
                BuildScript(name: "Test", command: "cargo test", description: "Run tests", category: .test),
                BuildScript(name: "Clean", command: "cargo clean", description: "Clean target directory", category: .clean),
                BuildScript(name: "Format", command: "cargo fmt", description: "Format code", category: .format),
                BuildScript(name: "Clippy", command: "cargo clippy", description: "Lint with Clippy", category: .lint)
            ]
        default:
            return []
        }
    }
    
    // MARK: - Test Analysis
    
    private func analyzeTestSuites(in directory: String) -> [TestSuite] {
        var testSuites: [TestSuite] = []
        
        // Mock test suites based on directory type
        if directory.contains("swift") || directory.contains("ios") {
            testSuites.append(TestSuite(
                name: "Unit Tests",
                type: .unit,
                testFiles: ["Tests/UnitTests/", "Tests/ModelTests/"],
                lastResults: TestResults(
                    totalTests: 45,
                    passedTests: 43,
                    failedTests: 2,
                    skippedTests: 0,
                    duration: 12.5,
                    timestamp: Date().addingTimeInterval(-3600),
                    failedTestCases: [
                        FailedTest(name: "testUserAuthentication", file: "AuthTests.swift", line: 25, message: "Expected true but got false", duration: 0.5),
                        FailedTest(name: "testDataPersistence", file: "DataTests.swift", line: 42, message: "Database connection failed", duration: 1.2)
                    ]
                ),
                coverage: TestCoverage(
                    linesCovered: 823,
                    totalLines: 1024,
                    percentage: 80.4,
                    fileCoverage: []
                )
            ))
            
            testSuites.append(TestSuite(
                name: "UI Tests",
                type: .ui,
                testFiles: ["UITests/"],
                lastResults: TestResults(
                    totalTests: 15,
                    passedTests: 15,
                    failedTests: 0,
                    skippedTests: 0,
                    duration: 45.2,
                    timestamp: Date().addingTimeInterval(-7200),
                    failedTestCases: []
                ),
                coverage: nil
            ))
        }
        
        return testSuites
    }
    
    // MARK: - Workflow Suggestions
    
    private func generateWorkflowSuggestions(git: GitRepository?, build: BuildSystem?, tests: [TestSuite]) -> [WorkflowSuggestion] {
        var suggestions: [WorkflowSuggestion] = []
        
        // Git-based suggestions
        if let git = git {
            if git.hasUncommittedChanges {
                suggestions.append(WorkflowSuggestion(
                    title: "Commit Changes",
                    description: "You have \(git.changedFiles.count) uncommitted files",
                    command: "git add . && git commit -m \"Update: describe your changes\"",
                    category: .git,
                    priority: .high,
                    icon: "checkmark.circle"
                ))
            }
            
            if git.status.ahead > 0 {
                suggestions.append(WorkflowSuggestion(
                    title: "Push Changes",
                    description: "\(git.status.ahead) commits ahead of remote",
                    command: "git push origin \(git.currentBranch)",
                    category: .git,
                    priority: .medium,
                    icon: "arrow.up.circle"
                ))
            }
            
            if git.status.behind > 0 {
                suggestions.append(WorkflowSuggestion(
                    title: "Pull Changes",
                    description: "\(git.status.behind) commits behind remote",
                    command: "git pull origin \(git.currentBranch)",
                    category: .git,
                    priority: .medium,
                    icon: "arrow.down.circle"
                ))
            }
        }
        
        // Build system suggestions
        if let build = build {
            if let lastBuild = build.lastBuildResult, !lastBuild.success {
                suggestions.append(WorkflowSuggestion(
                    title: "Fix Build",
                    description: "Last build failed with \(lastBuild.errors.count) errors",
                    command: build.type.primaryCommands.first ?? "build",
                    category: .build,
                    priority: .critical,
                    icon: "exclamationmark.triangle"
                ))
            } else {
                suggestions.append(WorkflowSuggestion(
                    title: "Run Build",
                    description: "Build your project",
                    command: build.type.primaryCommands.first ?? "build",
                    category: .build,
                    priority: .medium,
                    icon: "hammer"
                ))
            }
            
            if build.type.primaryCommands.count > 1 {
                suggestions.append(WorkflowSuggestion(
                    title: "Run Tests",
                    description: "Execute test suite",
                    command: build.type.primaryCommands[1],
                    category: .test,
                    priority: .medium,
                    icon: "testtube.2"
                ))
            }
        }
        
        // Test-based suggestions
        for testSuite in tests {
            if let results = testSuite.lastResults, results.failedTests > 0 {
                suggestions.append(WorkflowSuggestion(
                    title: "Fix Failed Tests",
                    description: "\(results.failedTests) tests failing in \(testSuite.name)",
                    command: "Run \(testSuite.name.lowercased())",
                    category: .test,
                    priority: .high,
                    icon: "exclamationmark.circle"
                ))
            }
        }
        
        return suggestions.sorted { $0.priority.rawValue > $1.priority.rawValue }
    }
    
    // MARK: - Quick Actions
    
    func getQuickGitActions() -> [WorkflowSuggestion] {
        guard let git = currentRepository else { return [] }
        
        return [
            WorkflowSuggestion(title: "Git Status", description: "Check repository status", command: "git status", category: .git, icon: "info.circle"),
            WorkflowSuggestion(title: "Git Log", description: "View commit history", command: "git log --oneline -10", category: .git, icon: "clock"),
            WorkflowSuggestion(title: "Git Diff", description: "Show changes", command: "git diff", category: .git, icon: "doc.text"),
            WorkflowSuggestion(title: "Switch Branch", description: "Checkout different branch", command: "git checkout main", category: .git, icon: "arrow.branch"),
            WorkflowSuggestion(title: "Create Branch", description: "Create new feature branch", command: "git checkout -b feature/new-feature", category: .git, icon: "plus.circle")
        ]
    }
    
    func getBuildActions() -> [WorkflowSuggestion] {
        guard let build = buildSystem else { return [] }
        
        return build.buildScripts.map { script in
            WorkflowSuggestion(
                title: script.name,
                description: script.description,
                command: script.command,
                category: .build,
                icon: script.category == .test ? "testtube.2" : "hammer"
            )
        }
    }
    
    func getTestActions() -> [WorkflowSuggestion] {
        return testSuites.map { suite in
            WorkflowSuggestion(
                title: "Run \(suite.name)",
                description: "Execute \(suite.name.lowercased())",
                command: "Run \(suite.name)",
                category: .test,
                icon: suite.type.icon
            )
        }
    }
}

// MARK: - Workflow Suggestion

struct WorkflowSuggestion {
    let id = UUID()
    let title: String
    let description: String
    let command: String
    let category: WorkflowCategory
    let priority: SuggestionPriority
    let icon: String
    
    init(title: String, description: String, command: String, category: WorkflowCategory, priority: SuggestionPriority = .medium, icon: String) {
        self.title = title
        self.description = description
        self.command = command
        self.category = category
        self.priority = priority
        self.icon = icon
    }
}

enum WorkflowCategory: String, CaseIterable {
    case git = "Git"
    case build = "Build"
    case test = "Test"
    case deploy = "Deploy"
    case debug = "Debug"
    case maintenance = "Maintenance"
    
    var color: Color {
        switch self {
        case .git: return .orange
        case .build: return .blue
        case .test: return .green
        case .deploy: return .purple
        case .debug: return .red
        case .maintenance: return .gray
        }
    }
}