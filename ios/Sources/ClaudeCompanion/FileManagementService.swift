import Foundation
import SwiftUI

// MARK: - File Models

struct FileItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let path: String
    let type: FileType
    let size: Int64?
    let modifiedDate: Date?
    let isHidden: Bool
    let permissions: FilePermissions?

    var displayName: String {
        isHidden && !name.hasPrefix(".") ? ".\(name)" : name
    }

    var fileExtension: String {
        (name as NSString).pathExtension.lowercased()
    }

    var isTextFile: Bool {
        let textExtensions = ["txt", "md", "swift", "js", "ts", "py", "java", "kt", "go", "rs", "cpp", "c", "h", "css", "html", "xml", "json", "yaml", "yml", "toml", "ini", "conf", "log", "sh", "bat", "ps1"]
        return textExtensions.contains(fileExtension)
    }

    var isCodeFile: Bool {
        let codeExtensions = ["swift", "js", "ts", "jsx", "tsx", "py", "java", "kt", "go", "rs", "cpp", "c", "h", "css", "scss", "sass", "less", "php", "rb", "lua", "dart", "scala", "clj", "hs", "ml", "fs"]
        return codeExtensions.contains(fileExtension)
    }

    var icon: String {
        switch type {
        case .directory:
            return "folder.fill"
        case .file:
            if isCodeFile {
                return "doc.text.fill"
            } else if ["png", "jpg", "jpeg", "gif", "bmp", "svg"].contains(fileExtension) {
                return "photo.fill"
            } else if ["mp4", "mov", "avi", "mkv"].contains(fileExtension) {
                return "video.fill"
            } else if ["mp3", "wav", "aac", "flac"].contains(fileExtension) {
                return "music.note"
            } else if ["pdf"].contains(fileExtension) {
                return "doc.richtext.fill"
            } else if ["zip", "tar", "gz", "rar", "7z"].contains(fileExtension) {
                return "archivebox.fill"
            } else {
                return "doc.fill"
            }
        case .symlink:
            return "link"
        }
    }

    var color: Color {
        switch type {
        case .directory:
            return .blue
        case .file:
            if isCodeFile {
                return .green
            } else {
                return .primary
            }
        case .symlink:
            return .orange
        }
    }
}

enum FileType: String, CaseIterable {
    case file = "file"
    case directory = "directory"
    case symlink = "symlink"
}

struct FilePermissions: Hashable, Equatable {
    let readable: Bool
    let writable: Bool
    let executable: Bool
    let owner: String?
    let group: String?
}

struct FileChange {
    let id = UUID()
    let filePath: String
    let changeType: FileChangeType
    let timestamp: Date
    let content: String?
    let previousContent: String?
}

enum FileChangeType: String, CaseIterable {
    case created = "created"
    case modified = "modified"
    case deleted = "deleted"
    case renamed = "renamed"
}

// MARK: - File Management Service

@available(iOS 13.0, macOS 10.15, *)
class FileManagementService: ObservableObject {
    @Published var currentDirectory: String = ""
    @Published var files: [FileItem] = []
    @Published var recentFiles: [FileItem] = []
    @Published var watchedFiles: Set<String> = []
    @Published var fileChanges: [FileChange] = []
    @Published var isLoading = false
    @Published var error: String?

    private let maxRecentFiles = 20
    private let maxFileChanges = 100

    init() {
        // Initialize with default directory
        let defaultDirectory = "/Users/\(NSUserName())/Desktop"
        currentDirectory = defaultDirectory
        loadDirectoryContents()
    }

    // MARK: - Directory Navigation

    func navigateToDirectory(_ path: String) {
        guard path != currentDirectory else { return }

        currentDirectory = path
        loadDirectoryContents()
    }

    func navigateUp() {
        let parentPath = (currentDirectory as NSString).deletingLastPathComponent
        if parentPath != currentDirectory && !parentPath.isEmpty {
            navigateToDirectory(parentPath)
        }
    }

    func refreshCurrentDirectory() {
        loadDirectoryContents()
    }

    private func loadDirectoryContents() {
        isLoading = true
        error = nil

        // Simulate file system operations (in real app, would use actual file system APIs)
        DispatchQueue.global(qos: .userInitiated).async {
            let mockFiles = self.generateMockFiles(for: self.currentDirectory)

            DispatchQueue.main.async {
                self.files = mockFiles
                self.isLoading = false
            }
        }
    }

    private func generateMockFiles(for directory: String) -> [FileItem] {
        var mockFiles: [FileItem] = []

        // Common directories
        if directory.hasSuffix("Desktop") || directory.contains("project") {
            mockFiles.append(contentsOf: [
                FileItem(name: "src", path: "\(directory)/src", type: .directory, size: nil, modifiedDate: Date().addingTimeInterval(-3600), isHidden: false, permissions: nil),
                FileItem(name: "tests", path: "\(directory)/tests", type: .directory, size: nil, modifiedDate: Date().addingTimeInterval(-7200), isHidden: false, permissions: nil),
                FileItem(name: "docs", path: "\(directory)/docs", type: .directory, size: nil, modifiedDate: Date().addingTimeInterval(-86400), isHidden: false, permissions: nil),
                FileItem(name: ".git", path: "\(directory)/.git", type: .directory, size: nil, modifiedDate: Date().addingTimeInterval(-1800), isHidden: true, permissions: nil)
            ])
        }

        // Project-specific files based on directory name
        if directory.contains("swift") || directory.contains("ios") {
            mockFiles.append(contentsOf: [
                FileItem(name: "Package.swift", path: "\(directory)/Package.swift", type: .file, size: 2048, modifiedDate: Date().addingTimeInterval(-900), isHidden: false, permissions: nil),
                FileItem(name: "README.md", path: "\(directory)/README.md", type: .file, size: 4096, modifiedDate: Date().addingTimeInterval(-1800), isHidden: false, permissions: nil),
                FileItem(name: "ContentView.swift", path: "\(directory)/ContentView.swift", type: .file, size: 8192, modifiedDate: Date().addingTimeInterval(-600), isHidden: false, permissions: nil),
                FileItem(name: "AppDelegate.swift", path: "\(directory)/AppDelegate.swift", type: .file, size: 3072, modifiedDate: Date().addingTimeInterval(-7200), isHidden: false, permissions: nil)
            ])
        } else if directory.contains("node") || directory.contains("react") {
            mockFiles.append(contentsOf: [
                FileItem(name: "package.json", path: "\(directory)/package.json", type: .file, size: 1536, modifiedDate: Date().addingTimeInterval(-1200), isHidden: false, permissions: nil),
                FileItem(name: "index.js", path: "\(directory)/index.js", type: .file, size: 2048, modifiedDate: Date().addingTimeInterval(-300), isHidden: false, permissions: nil),
                FileItem(name: "App.jsx", path: "\(directory)/App.jsx", type: .file, size: 4096, modifiedDate: Date().addingTimeInterval(-600), isHidden: false, permissions: nil),
                FileItem(name: "node_modules", path: "\(directory)/node_modules", type: .directory, size: nil, modifiedDate: Date().addingTimeInterval(-3600), isHidden: false, permissions: nil),
                FileItem(name: ".env", path: "\(directory)/.env", type: .file, size: 512, modifiedDate: Date().addingTimeInterval(-86400), isHidden: true, permissions: nil)
            ])
        } else if directory.contains("python") {
            mockFiles.append(contentsOf: [
                FileItem(name: "requirements.txt", path: "\(directory)/requirements.txt", type: .file, size: 1024, modifiedDate: Date().addingTimeInterval(-1800), isHidden: false, permissions: nil),
                FileItem(name: "main.py", path: "\(directory)/main.py", type: .file, size: 3072, modifiedDate: Date().addingTimeInterval(-900), isHidden: false, permissions: nil),
                FileItem(name: "app.py", path: "\(directory)/app.py", type: .file, size: 5120, modifiedDate: Date().addingTimeInterval(-600), isHidden: false, permissions: nil),
                FileItem(name: "__pycache__", path: "\(directory)/__pycache__", type: .directory, size: nil, modifiedDate: Date().addingTimeInterval(-1200), isHidden: true, permissions: nil)
            ])
        }

        // Common files
        mockFiles.append(contentsOf: [
            FileItem(name: ".gitignore", path: "\(directory)/.gitignore", type: .file, size: 512, modifiedDate: Date().addingTimeInterval(-86400), isHidden: true, permissions: nil),
            FileItem(name: "LICENSE", path: "\(directory)/LICENSE", type: .file, size: 11264, modifiedDate: Date().addingTimeInterval(-604800), isHidden: false, permissions: nil)
        ])

        return mockFiles.sorted { file1, file2 in
            if file1.type == .directory && file2.type != .directory {
                return true
            } else if file1.type != .directory && file2.type == .directory {
                return false
            } else {
                return file1.name.localizedCaseInsensitiveCompare(file2.name) == .orderedAscending
            }
        }
    }

    // MARK: - File Operations

    func openFile(_ file: FileItem) {
        addToRecentFiles(file)

        if file.type == .directory {
            navigateToDirectory(file.path)
        }
    }

    func readFileContent(_ file: FileItem, completion: @escaping (Result<String, Error>) -> Void) {
        guard file.type == .file else {
            completion(.failure(FileManagementError.notAFile))
            return
        }

        // Simulate file reading
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.5) {
            let mockContent = self.generateMockFileContent(for: file)
            DispatchQueue.main.async {
                completion(.success(mockContent))
            }
        }

        addToRecentFiles(file)
    }

    private func generateMockFileContent(for file: FileItem) -> String {
        let fileName = file.name.lowercased()

        if fileName == "package.json" {
            return """
            {
              "name": "my-project",
              "version": "1.0.0",
              "description": "A sample project",
              "main": "index.js",
              "scripts": {
                "start": "node index.js",
                "test": "jest",
                "build": "webpack --mode production"
              },
              "dependencies": {
                "express": "^4.18.0",
                "react": "^18.2.0"
              },
              "devDependencies": {
                "jest": "^29.0.0",
                "webpack": "^5.74.0"
              }
            }
            """
        } else if fileName == "package.swift" {
            return """
            // swift-tools-version: 5.8
            import PackageDescription

            let package = Package(
                name: "MyProject",
                platforms: [
                    .iOS(.v16),
                    .macOS(.v13)
                ],
                products: [
                    .library(
                        name: "MyProject",
                        targets: ["MyProject"]
                    ),
                ],
                dependencies: [
                    .package(url: "https://github.com/apple/swift-algorithms", from: "1.0.0"),
                ],
                targets: [
                    .target(
                        name: "MyProject",
                        dependencies: [
                            .product(name: "Algorithms", package: "swift-algorithms"),
                        ]
                    ),
                    .testTarget(
                        name: "MyProjectTests",
                        dependencies: ["MyProject"]
                    ),
                ]
            )
            """
        } else if fileName.hasSuffix(".swift") {
            return """
            import SwiftUI

            struct ContentView: View {
                @State private var text = "Hello, World!"

                var body: some View {
                    VStack {
                        Text(text)
                            .font(.largeTitle)
                            .padding()

                        Button("Tap me!") {
                            text = "Button tapped!"
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                }
            }

            #Preview {
                ContentView()
            }
            """
        } else if fileName.hasSuffix(".js") || fileName.hasSuffix(".jsx") {
            return """
            import React, { useState } from 'react';

            function App() {
              const [count, setCount] = useState(0);

              return (
                <div className="App">
                  <header className="App-header">
                    <h1>React Counter</h1>
                    <p>Count: {count}</p>
                    <button onClick={() => setCount(count + 1)}>
                      Increment
                    </button>
                    <button onClick={() => setCount(count - 1)}>
                      Decrement
                    </button>
                  </header>
                </div>
              );
            }

            export default App;
            """
        } else if fileName.hasSuffix(".py") {
            return """
            from flask import Flask, jsonify, request

            app = Flask(__name__)

            @app.route('/')
            def hello_world():
                return jsonify({
                    'message': 'Hello, World!',
                    'status': 'success'
                })

            @app.route('/api/users', methods=['GET', 'POST'])
            def handle_users():
                if request.method == 'GET':
                    return jsonify({'users': []})
                elif request.method == 'POST':
                    user_data = request.get_json()
                    return jsonify({'created': user_data}), 201

            if __name__ == '__main__':
                app.run(debug=True, host='0.0.0.0', port=5000)
            """
        } else if fileName == "readme.md" {
            return """
            # My Project

            This is a sample project demonstrating various features and capabilities.

            ## Installation

            ```bash
            git clone https://github.com/user/my-project.git
            cd my-project
            npm install  # or pip install -r requirements.txt
            ```

            ## Usage

            ```bash
            npm start  # or python main.py
            ```

            ## Features

            - Modern architecture
            - Comprehensive testing
            - CI/CD integration
            - Documentation

            ## Contributing

            1. Fork the repository
            2. Create a feature branch
            3. Make your changes
            4. Add tests
            5. Submit a pull request

            ## License

            MIT License - see LICENSE file for details.
            """
        } else {
            return "File content for \(file.name)\n\nThis is a sample file with some content.\nModified: \(file.modifiedDate?.formatted() ?? "Unknown")\nSize: \(file.size ?? 0) bytes"
        }
    }

    func watchFile(_ file: FileItem) {
        watchedFiles.insert(file.path)

        // Simulate file change detection
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.simulateFileChange(file)
        }
    }

    func unwatchFile(_ file: FileItem) {
        watchedFiles.remove(file.path)
    }

    private func simulateFileChange(_ file: FileItem) {
        let change = FileChange(
            filePath: file.path,
            changeType: .modified,
            timestamp: Date(),
            content: "Updated content",
            previousContent: "Previous content"
        )

        addFileChange(change)
    }

    // MARK: - File History & Changes

    private func addToRecentFiles(_ file: FileItem) {
        DispatchQueue.main.async {
            // Remove if already exists
            self.recentFiles.removeAll { $0.path == file.path }

            // Add to front
            self.recentFiles.insert(file, at: 0)

            // Keep only recent files
            if self.recentFiles.count > self.maxRecentFiles {
                self.recentFiles = Array(self.recentFiles.prefix(self.maxRecentFiles))
            }
        }
    }

    private func addFileChange(_ change: FileChange) {
        DispatchQueue.main.async {
            self.fileChanges.insert(change, at: 0)

            // Keep only recent changes
            if self.fileChanges.count > self.maxFileChanges {
                self.fileChanges = Array(self.fileChanges.prefix(self.maxFileChanges))
            }
        }
    }

    // MARK: - Search & Filtering

    func searchFiles(query: String) -> [FileItem] {
        guard !query.isEmpty else { return files }

        return files.filter { file in
            file.name.localizedCaseInsensitiveContains(query) ||
                file.fileExtension.localizedCaseInsensitiveContains(query)
        }
    }

    func getFilesByType(_ type: FileType) -> [FileItem] {
        return files.filter { $0.type == type }
    }

    func getRecentCodeFiles() -> [FileItem] {
        return recentFiles.filter { $0.isCodeFile }
    }

    func getRecentChanges(limit: Int = 10) -> [FileChange] {
        return Array(fileChanges.prefix(limit))
    }

    // MARK: - Quick Actions

    func generateFilePrompts(for file: FileItem) -> [String] {
        var prompts: [String] = []

        if file.isCodeFile {
            prompts.append("Analyze the code in \(file.name)")
            prompts.append("Review \(file.name) for potential improvements")
            prompts.append("Explain what \(file.name) does")
            prompts.append("Add comments to \(file.name)")
            prompts.append("Refactor \(file.name)")
        }

        if file.type == .file {
            prompts.append("Read and summarize \(file.name)")
            prompts.append("Show the contents of \(file.name)")
        }

        if file.type == .directory {
            prompts.append("List files in \(file.name)")
            prompts.append("Analyze the structure of \(file.name)")
        }

        return prompts
    }
}

// MARK: - Error Types

enum FileManagementError: LocalizedError {
    case notAFile
    case fileNotFound
    case permissionDenied
    case ioError(String)

    var errorDescription: String? {
        switch self {
        case .notAFile:
            return "The selected item is not a file"
        case .fileNotFound:
            return "File not found"
        case .permissionDenied:
            return "Permission denied"
        case .ioError(let message):
            return "I/O Error: \(message)"
        }
    }
}
