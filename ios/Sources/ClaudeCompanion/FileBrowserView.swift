import SwiftUI

struct FileBrowserView: View {
    @ObservedObject var fileManagementService: FileManagementService
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var showingFileDetails = false
    @State private var selectedFile: FileItem?
    @State private var showingQuickActions = false
    @State private var showingRecentFiles = false

    let workingDirectory: String
    let onFileSelected: (FileItem) -> Void
    let onDirectoryChanged: (String) -> Void

    init(fileManagementService: FileManagementService, workingDirectory: String, onFileSelected: @escaping (FileItem) -> Void, onDirectoryChanged: @escaping (String) -> Void) {
        self.fileManagementService = fileManagementService
        self.workingDirectory = workingDirectory
        self.onFileSelected = onFileSelected
        self.onDirectoryChanged = onDirectoryChanged
    }

    var filteredFiles: [FileItem] {
        let files = searchText.isEmpty ? fileManagementService.files : fileManagementService.searchFiles(query: searchText)
        return files.sorted { file1, file2 in
            if file1.type == .directory && file2.type != .directory {
                return true
            } else if file1.type != .directory && file2.type == .directory {
                return false
            } else {
                return file1.name.localizedCaseInsensitiveCompare(file2.name) == .orderedAscending
            }
        }
    }

    var body: some View {
        NavigationView {
            VStack {
                // Current path header
                if !fileManagementService.currentDirectory.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            Text("📁")
                            Text(fileManagementService.currentDirectory)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical, 8)
                    .background(Color.gray.opacity(0.1))
                }

                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)

                    TextField("Search files...", text: $searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                .padding(.horizontal)

                // Navigation buttons
                HStack {
                    Button(action: {
                        fileManagementService.navigateUp()
                        onDirectoryChanged(fileManagementService.currentDirectory)
                    }) {
                        HStack {
                            Image(systemName: "chevron.up")
                            Text("Up")
                        }
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .disabled(fileManagementService.currentDirectory == "/" || fileManagementService.currentDirectory.isEmpty)

                    Button(action: {
                        fileManagementService.refreshCurrentDirectory()
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Refresh")
                        }
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                    }

                    Spacer()

                    Button(action: {
                        showingRecentFiles = true
                    }) {
                        HStack {
                            Image(systemName: "clock")
                            Text("Recent")
                        }
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .padding(.horizontal)

                // Files list
                if fileManagementService.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Loading files...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredFiles.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "folder")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)

                        Text(searchText.isEmpty ? "No files in this directory" : "No files found")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(filteredFiles) { file in
                            FileRow(
                                file: file,
                                onTap: {
                                    if file.type == .directory {
                                        fileManagementService.navigateToDirectory(file.path)
                                        onDirectoryChanged(file.path)
                                    } else {
                                        selectedFile = file
                                        showingQuickActions = true
                                    }
                                },
                                onFileAction: { action in
                                    handleFileAction(action, for: file)
                                }
                            )
                        }
                    }
                }
            }
            .navigationTitle("File Browser")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Change Directory") {
                            // TODO: Show directory picker
                        }

                        Button("File Details") {
                            showingFileDetails = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .onAppear {
                if !workingDirectory.isEmpty && workingDirectory != fileManagementService.currentDirectory {
                    fileManagementService.navigateToDirectory(workingDirectory)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search files")
        .actionSheet(isPresented: $showingQuickActions) {
            if let file = selectedFile {
                return ActionSheet(
                    title: Text(file.name),
                    message: Text("Choose an action for this file"),
                    buttons: generateActionButtons(for: file)
                )
            } else {
                return ActionSheet(title: Text("File Actions"))
            }
        }
        .sheet(isPresented: $showingRecentFiles) {
            RecentFilesView(
                fileManagementService: fileManagementService,
                onFileSelected: { file in
                    onFileSelected(file)
                    dismiss()
                }
            )
        }
        .sheet(isPresented: $showingFileDetails) {
            if let file = selectedFile {
                FileDetailsView(file: file, fileManagementService: fileManagementService)
            }
        }
    }

    private func handleFileAction(_ action: FileAction, for file: FileItem) {
        switch action {
        case .select:
            onFileSelected(file)
            dismiss()
        case .analyze:
            onFileSelected(file)
            dismiss()
        case .watch:
            fileManagementService.watchFile(file)
        case .unwatch:
            fileManagementService.unwatchFile(file)
        case .details:
            selectedFile = file
            showingFileDetails = true
        }
    }

    private func generateActionButtons(for file: FileItem) -> [ActionSheet.Button] {
        let prompts = fileManagementService.generateFilePrompts(for: file)
        var buttons: [ActionSheet.Button] = []

        // Add quick action buttons based on file type
        for prompt in prompts.prefix(3) {
            buttons.append(.default(Text(prompt)) {
                onFileSelected(file)
                dismiss()
            })
        }

        // Add watch/unwatch toggle
        if fileManagementService.watchedFiles.contains(file.path) {
            buttons.append(.default(Text("Unwatch File")) {
                fileManagementService.unwatchFile(file)
            })
        } else {
            buttons.append(.default(Text("Watch File")) {
                fileManagementService.watchFile(file)
            })
        }

        // Add file details
        buttons.append(.default(Text("File Details")) {
            selectedFile = file
            showingFileDetails = true
        })

        // Add cancel button
        buttons.append(.cancel())

        return buttons
    }
}

struct FileRow: View {
    let file: FileItem
    let onTap: () -> Void
    let onFileAction: (FileAction) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: file.icon)
                .font(.title3)
                .foregroundColor(file.color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let size = file.size {
                        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    if let modifiedDate = file.modifiedDate {
                        Text(modifiedDate, style: .relative)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    if file.isHidden {
                        Image(systemName: "eye.slash")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            if file.type == .directory {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 4) {
                    if file.isCodeFile {
                        Image(systemName: "code")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }

                    if file.isTextFile {
                        Image(systemName: "text.alignleft")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .contextMenu {
            if file.type == .file {
                Button(action: {
                    onFileAction(.select)
                }) {
                    Label("Use in Chat", systemImage: "message")
                }

                Button(action: {
                    onFileAction(.analyze)
                }) {
                    Label("Analyze File", systemImage: "magnifyingglass")
                }

                Button(action: {
                    onFileAction(.watch)
                }) {
                    Label("Watch Changes", systemImage: "eye")
                }

                Button(action: {
                    onFileAction(.details)
                }) {
                    Label("File Details", systemImage: "info.circle")
                }
            } else {
                Button(action: {
                    onTap()
                }) {
                    Label("Open Directory", systemImage: "folder.fill")
                }
            }
        }
    }
}

struct RecentFilesView: View {
    @ObservedObject var fileManagementService: FileManagementService
    @Environment(\.dismiss) private var dismiss

    let onFileSelected: (FileItem) -> Void

    var body: some View {
        NavigationView {
            VStack {
                if fileManagementService.recentFiles.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "clock")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)

                        Text("No recent files")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Text("Files you interact with will appear here")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(fileManagementService.recentFiles) { file in
                            FileRow(
                                file: file,
                                onTap: {
                                    onFileSelected(file)
                                },
                                onFileAction: { action in
                                    if action == .select {
                                        onFileSelected(file)
                                    }
                                }
                            )
                        }
                    }
                }
            }
            .navigationTitle("Recent Files")
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

struct FileDetailsView: View {
    let file: FileItem
    @ObservedObject var fileManagementService: FileManagementService
    @Environment(\.dismiss) private var dismiss

    @State private var fileContent: String?
    @State private var isLoadingContent = false
    @State private var contentError: String?

    var body: some View {
        NavigationView {
            List {
                Section("File Information") {
                    DetailRow(label: "Name", value: file.name, icon: "tag")
                    DetailRow(label: "Type", value: file.type.rawValue.capitalized, icon: "doc")
                    DetailRow(label: "Path", value: file.path, icon: "folder")

                    if let size = file.size {
                        DetailRow(label: "Size", value: ByteCountFormatter.string(fromByteCount: size, countStyle: .file), icon: "externaldrive")
                    }

                    if let modifiedDate = file.modifiedDate {
                        DetailRow(label: "Modified", value: modifiedDate.formatted(), icon: "calendar")
                    }

                    if file.isHidden {
                        DetailRow(label: "Hidden", value: "Yes", icon: "eye.slash")
                    }

                    if !file.fileExtension.isEmpty {
                        DetailRow(label: "Extension", value: file.fileExtension, icon: "textformat")
                    }
                }

                Section("File Properties") {
                    if file.isCodeFile {
                        DetailRow(label: "Code File", value: "Yes", icon: "code")
                    }

                    if file.isTextFile {
                        DetailRow(label: "Text File", value: "Yes", icon: "text.alignleft")
                    }

                    if fileManagementService.watchedFiles.contains(file.path) {
                        DetailRow(label: "Watching", value: "Yes", icon: "eye")
                    }
                }

                if file.type == .file && file.isTextFile {
                    Section("Preview") {
                        if isLoadingContent {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Loading content...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } else if let error = contentError {
                            Text("Error: \(error)")
                                .font(.caption)
                                .foregroundColor(.red)
                        } else if let content = fileContent {
                            Text(content.prefix(500))
                                .font(.caption)
                                .fontFamily(.monospaced)
                                .foregroundColor(.secondary)
                                .lineLimit(20)
                        } else {
                            Button("Load Preview") {
                                loadFileContent()
                            }
                            .font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("File Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            if file.type == .file && file.isTextFile && file.size ?? 0 < 10000 {
                loadFileContent()
            }
        }
    }

    private func loadFileContent() {
        isLoadingContent = true
        contentError = nil

        fileManagementService.readFileContent(file) { result in
            DispatchQueue.main.async {
                isLoadingContent = false

                switch result {
                case .success(let content):
                    fileContent = content
                case .failure(let error):
                    contentError = error.localizedDescription
                }
            }
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 20)

            Text(label)
                .fontWeight(.medium)

            Spacer()

            Text(value)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

enum FileAction {
    case select
    case analyze
    case watch
    case unwatch
    case details
}

#Preview {
    FileBrowserView(
        fileManagementService: FileManagementService(),
        workingDirectory: "/Users/test",
        onFileSelected: { _ in },
        onDirectoryChanged: { _ in }
    )
}
