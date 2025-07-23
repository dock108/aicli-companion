import SwiftUI

struct ChatView: View {
    @EnvironmentObject var claudeService: ClaudeCodeService
    @StateObject private var webSocketService = WebSocketService()
    @StateObject private var toolActivityManager = ToolActivityManager()
    @StateObject private var persistenceService = ConversationPersistenceService()
    @StateObject private var projectAwarenessService = ProjectAwarenessService()
    @StateObject private var fileManagementService = FileManagementService()
    @StateObject private var workflowService = DevelopmentWorkflowService()
    @State private var messageText = ""
    @State private var messages: [Message] = []
    @State private var isLoading = false
    @State private var currentStreamingMessage: Message?
    @State private var activeSessionId: String?
    @State private var showingPermissionAlert = false
    @State private var permissionRequest: PermissionRequestData?
    @State private var showingWorkingDirectorySheet = false
    @State private var workingDirectoryText = ""
    @State private var showingToolActivity = false
    @State private var showingConversationHistory = false
    @State private var showingFileBrowser = false
    @State private var showingWorkflowView = false

    var body: some View {
        VStack {
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                                .slideIn(delay: Double(messages.firstIndex(where: { $0.id == message.id }) ?? 0) * AnimationConstants.quickDelay)
                        }

                        if isLoading || currentStreamingMessage != nil {
                            TypingIndicator()
                        }

                        // Project context banner
                        if let project = projectAwarenessService.currentProject {
                            ProjectContextBanner(project: project) { suggestion in
                                handleSuggestionTap(suggestion)
                            }
                            .padding(.horizontal)
                        }

                        // Workflow suggestions
                        if !workflowService.workflowSuggestions.isEmpty {
                            WorkflowSuggestionsBar(
                                suggestions: Array(workflowService.workflowSuggestions.prefix(2)),
                                onCommandSelected: { command in
                                    HapticManager.shared.workflowSuggestionTap()
                                    withAnimation(AnimationConstants.workflowSuggestionSlide) {
                                        messageText = command
                                    }
                                }
                            )
                            .slideIn(delay: AnimationConstants.mediumDelay, from: .top)
                        }

                        // Tool activity indicators
                        ToolActivityList(activityManager: toolActivityManager, sessionId: activeSessionId)

                        // Recent files context
                        if !fileManagementService.recentFiles.isEmpty {
                            RecentFilesContextBar(
                                recentFiles: Array(fileManagementService.recentFiles.prefix(3)),
                                onFileSelected: { file in
                                    let prompts = fileManagementService.generateFilePrompts(for: file)
                                    if !prompts.isEmpty {
                                        messageText = prompts.first!
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
                .onChange(of: messages.count) { _ in
                    if let lastMessage = messages.last {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }

            // Input area
            VStack {
                Divider()

                HStack {
                    Button(action: {
                        HapticManager.shared.buttonTap()
                        showingFileBrowser = true
                    }) {
                        Image(systemName: "folder")
                            .foregroundColor(.blue)
                    }
                    .scaleButtonStyle()
                    .accessibleButton(
                        label: AccessibilityLabels.openFileBrowser,
                        hint: AccessibilityHints.openFileBrowser,
                        identifier: AccessibilityIdentifiers.fileBrowserButton
                    )

                    TextField("Type a command or question...", text: $messageText, axis: .vertical)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onSubmit {
                            sendMessage()
                        }

                    Button(action: {
                        HapticManager.shared.messageSent()
                        sendMessage()
                    }) {
                        Image(systemName: "paperplane.fill")
                            .foregroundColor(messageText.isEmpty ? .gray : .blue)
                    }
                    .disabled(messageText.isEmpty || isLoading)
                    .scaleButtonStyle()
                    .accessibleButton(
                        label: AccessibilityLabels.sendMessage,
                        hint: AccessibilityHints.sendMessage,
                        identifier: AccessibilityIdentifiers.sendButton
                    )
                }
                .padding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(persistenceService.currentConversation?.title ?? "Claude Code")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    showingConversationHistory = true
                }) {
                    Image(systemName: "clock")
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    Button(action: {
                        showingToolActivity = true
                    }) {
                        ZStack {
                            Image(systemName: "gear")

                            if !toolActivityManager.activeTools.isEmpty {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 8, height: 8)
                                    .offset(x: 8, y: -8)
                            }
                        }
                    }

                    Menu {
                        Button("New Conversation") {
                            startNewConversation()
                        }

                        Divider()

                        Button("Set Working Directory") {
                            showingWorkingDirectorySheet = true
                        }

                        if projectAwarenessService.currentProject != nil {
                            Button("Project Context") {
                                // TODO: Show project context sheet
                            }
                        }

                        Button("File Browser") {
                            showingFileBrowser = true
                        }

                        Button("Development Workflow") {
                            showingWorkflowView = true
                        }
                        Button("Clear Chat") {
                            clearCurrentChat()
                        }
                        Button("CLI Mode") {
                            // TODO: Switch to CLI mode
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .onAppear {
            loadChatHistory()
            setupWebSocketHandlers()

            // Initialize file management service with working directory
            if !workingDirectoryText.isEmpty {
                fileManagementService.navigateToDirectory(workingDirectoryText)
                workflowService.updateWorkingDirectory(workingDirectoryText)
            }
        }
        .alert("Permission Required", isPresented: $showingPermissionAlert) {
            if let request = permissionRequest {
                ForEach(request.options, id: \.self) { option in
                    Button(option.uppercased()) {
                        respondToPermission(option)
                    }
                }
                Button("Cancel", role: .cancel) {
                    respondToPermission("n")
                }
            }
        } message: {
            if let request = permissionRequest {
                Text(request.prompt)
            }
        }
        .sheet(isPresented: $showingWorkingDirectorySheet) {
            WorkingDirectorySheet(
                currentDirectory: workingDirectoryText,
                onSetDirectory: { directory in
                    setWorkingDirectory(directory)
                }
            )
        }
        .sheet(isPresented: $showingToolActivity) {
            ToolActivitySheet(activityManager: toolActivityManager)
        }
        .sheet(isPresented: $showingConversationHistory) {
            ConversationHistoryView(
                persistenceService: persistenceService,
                onConversationSelected: loadConversation
            )
        }
        .sheet(isPresented: $showingFileBrowser) {
            FileBrowserView(
                fileManagementService: fileManagementService,
                workingDirectory: workingDirectoryText.isEmpty ? fileManagementService.currentDirectory : workingDirectoryText,
                onFileSelected: handleFileSelected,
                onDirectoryChanged: handleDirectoryChanged
            )
        }
        .sheet(isPresented: $showingWorkflowView) {
            DevelopmentWorkflowView(
                workflowService: workflowService,
                onCommandSelected: handleWorkflowCommand
            )
        }
        .overlay(
            ToolActivityOverlay(activityManager: toolActivityManager, sessionId: activeSessionId)
        )
    }

    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let userMessage = Message(
            id: UUID(),
            content: messageText,
            sender: .user,
            timestamp: Date(),
            type: .text
        )

        withAnimation(AnimationConstants.messageAppear) {
            messages.append(userMessage)
        }
        let prompt = messageText
        messageText = ""
        isLoading = true

        if let sessionId = activeSessionId {
            // Send to existing streaming session
            webSocketService.sendToStream(sessionId: sessionId, prompt: prompt)
            isLoading = false
        } else {
            // Start new streaming session
            webSocketService.startStream(prompt: prompt, workingDirectory: nil, sessionName: "Chat Session") { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let sessionId):
                        self.activeSessionId = sessionId
                        self.isLoading = false
                    case .failure(let error):
                        self.isLoading = false
                        let errorMessage = Message(
                            id: UUID(),
                            content: "Error: \(error.localizedDescription)",
                            sender: .system,
                            timestamp: Date(),
                            type: .error
                        )
                        self.messages.append(errorMessage)
                        self.persistenceService.addMessageToCurrentConversation(errorMessage)
                    }
                }
            }
        }
    }

    private func loadChatHistory() {
        // Load current conversation or create new one
        if let currentConversation = persistenceService.currentConversation {
            loadConversation(currentConversation)
        } else {
            startNewConversation()
        }
    }

    private func setupWebSocketHandlers() {
        // Handle streaming data
        webSocketService.setMessageHandler(for: .streamData) { message in
            DispatchQueue.main.async {
                self.handleStreamData(message)
            }
        }

        // Handle stream completion
        webSocketService.setMessageHandler(for: .streamComplete) { message in
            DispatchQueue.main.async {
                self.handleStreamComplete(message)
            }
        }

        // Handle permission requests
        webSocketService.setMessageHandler(for: .permissionRequest) { message in
            DispatchQueue.main.async {
                self.handlePermissionRequest(message)
            }
        }

        // Handle tool usage
        webSocketService.setMessageHandler(for: .streamToolUse) { message in
            DispatchQueue.main.async {
                self.handleToolUse(message)
            }
        }

        // Handle errors
        webSocketService.setMessageHandler(for: .error) { message in
            DispatchQueue.main.async {
                self.handleError(message)
            }
        }

        // Handle new rich message types
        webSocketService.setMessageHandler(for: .systemInit) { message in
            DispatchQueue.main.async {
                self.handleSystemInit(message)
            }
        }

        webSocketService.setMessageHandler(for: .assistantMessage) { message in
            DispatchQueue.main.async {
                self.handleAssistantMessage(message)
            }
        }

        webSocketService.setMessageHandler(for: .toolUse) { message in
            DispatchQueue.main.async {
                self.handleToolUse(message)
            }
        }

        webSocketService.setMessageHandler(for: .toolResult) { message in
            DispatchQueue.main.async {
                self.handleToolResult(message)
            }
        }

        webSocketService.setMessageHandler(for: .conversationResult) { message in
            DispatchQueue.main.async {
                self.handleConversationResult(message)
            }
        }
    }

    private func handleStreamData(_ message: WebSocketMessage) {
        guard case .streamData(let streamData) = message.data else { return }

        // Create or update streaming message
        if currentStreamingMessage == nil {
            currentStreamingMessage = Message(
                id: UUID(),
                content: "",
                sender: .claude,
                timestamp: Date(),
                type: .text,
                streamingState: .streaming
            )
        }

        // Append content to current streaming message
        if let text = streamData.content.text {
            if var streamingMessage = currentStreamingMessage {
                streamingMessage.content += text
                currentStreamingMessage = streamingMessage
            }
        }

        // Update the message in the messages array or add it
        if let streamingMessage = currentStreamingMessage {
            if let index = messages.firstIndex(where: { $0.id == streamingMessage.id }) {
                messages[index] = streamingMessage
            } else {
                messages.append(streamingMessage)
            }
        }

        // If stream is complete, finalize the message
        if streamData.isComplete {
            finalizeStreamingMessage()
        }
    }

    private func handleStreamComplete(_ message: WebSocketMessage) {
        guard case .streamComplete(let completeData) = message.data else { return }

        // Update message metadata if we have a streaming message
        if var streamingMessage = currentStreamingMessage {
            streamingMessage.streamingState = .completed
            streamingMessage.metadata = ClaudeMessageMetadata(
                sessionId: completeData.sessionId,
                duration: completeData.duration,
                cost: completeData.cost
            )

            if let index = messages.firstIndex(where: { $0.id == streamingMessage.id }) {
                messages[index] = streamingMessage
            }
        }

        finalizeStreamingMessage()
    }

    private func handlePermissionRequest(_ message: WebSocketMessage) {
        guard case .permissionRequest(let request) = message.data else { return }

        permissionRequest = request
        showingPermissionAlert = true
    }

    private func handleToolUse(_ message: WebSocketMessage) {
        guard case .streamToolUse(let toolUse) = message.data else { return }

        // Add a tool usage message
        let toolMessage = Message(
            id: UUID(),
            content: "🔧 Using tool: \(toolUse.toolName) - \(toolUse.status)",
            sender: .system,
            timestamp: Date(),
            type: .toolUse
        )

        messages.append(toolMessage)
        persistenceService.addMessageToCurrentConversation(toolMessage)
    }

    private func handleError(_ message: WebSocketMessage) {
        guard case .error(let error) = message.data else { return }

        let errorMessage = Message(
            id: UUID(),
            content: "Error: \(error.message)",
            sender: .system,
            timestamp: Date(),
            type: .error
        )

        messages.append(errorMessage)
        finalizeStreamingMessage()
    }

    private func finalizeStreamingMessage() {
        currentStreamingMessage = nil
        isLoading = false
    }

    private func respondToPermission(_ response: String) {
        guard let request = permissionRequest else { return }

        webSocketService.respondToPermission(
            sessionId: request.sessionId,
            response: response,
            remember: false
        )

        permissionRequest = nil
        showingPermissionAlert = false
    }

    // MARK: - Rich Message Handlers

    private func handleSystemInit(_ message: WebSocketMessage) {
        guard case .systemInit(let systemInit) = message.data else { return }

        let systemMessage = Message(
            id: UUID(),
            content: "🔧 System initialized with \(systemInit.availableTools.count) tools available",
            sender: .system,
            timestamp: Date(),
            type: .system
        )

        messages.append(systemMessage)
        persistenceService.addMessageToCurrentConversation(systemMessage)
    }

    private func handleAssistantMessage(_ message: WebSocketMessage) {
        guard case .assistantMessage(let assistantMsg) = message.data else { return }

        // Process content blocks to create rich messages
        for contentBlock in assistantMsg.content {
            let assistantMessage: Message

            switch contentBlock.type {
            case "text":
                let text = contentBlock.text ?? ""

                // Check if text contains code blocks
                if text.contains("```") {
                    // Extract code blocks and create rich content
                    let (plainText, codeBlocks) = extractCodeBlocks(from: text)

                    if !plainText.isEmpty {
                        // Create message for plain text
                        let textMessage = Message(
                            id: UUID(),
                            content: plainText,
                            sender: .claude,
                            timestamp: Date(),
                            type: .markdown,
                            metadata: ClaudeMessageMetadata(
                                sessionId: activeSessionId ?? "",
                                duration: 0,
                                tools: assistantMsg.usage?.serverToolUse != nil ? ["server_tools"] : nil
                            )
                        )
                        messages.append(textMessage)
                    }

                    // Create messages for code blocks
                    for codeBlock in codeBlocks {
                        let richContent = RichContent(
                            contentType: .codeBlock,
                            data: .codeBlock(codeBlock)
                        )

                        let codeMessage = Message(
                            id: UUID(),
                            content: codeBlock.code,
                            sender: .claude,
                            timestamp: Date(),
                            type: .code,
                            richContent: richContent
                        )
                        messages.append(codeMessage)
                    }
                } else {
                    // Simple text message
                    assistantMessage = Message(
                        id: UUID(),
                        content: text,
                        sender: .claude,
                        timestamp: Date(),
                        type: .text,
                        metadata: ClaudeMessageMetadata(
                            sessionId: activeSessionId ?? "",
                            duration: 0,
                            tools: assistantMsg.usage?.serverToolUse != nil ? ["server_tools"] : nil
                        )
                    )
                    messages.append(assistantMessage)
                }

            case "tool_use":
                let toolDescription = "Using tool: \(contentBlock.toolName ?? "unknown")"
                assistantMessage = Message(
                    id: UUID(),
                    content: toolDescription,
                    sender: .claude,
                    timestamp: Date(),
                    type: .toolUse
                )
                messages.append(assistantMessage)

            default:
                assistantMessage = Message(
                    id: UUID(),
                    content: "Received assistant content: \(contentBlock.type)",
                    sender: .claude,
                    timestamp: Date(),
                    type: .text
                )
                messages.append(assistantMessage)
            }
        }
    }

    private func handleToolResult(_ message: WebSocketMessage) {
        guard case .toolResult(let toolResult) = message.data else { return }

        // Update tool activity tracking
        if toolResult.success {
            toolActivityManager.completeTool(id: toolResult.toolId, output: toolResult.result)
        } else {
            toolActivityManager.failTool(id: toolResult.toolId, error: toolResult.error ?? "Unknown error")
        }

        // Create rich content for tool results
        let toolResultData = ToolResultData(
            toolName: toolResult.toolName,
            input: nil, // TODO: Capture tool input from toolUse message
            output: toolResult.result ?? "",
            success: toolResult.success,
            error: toolResult.error,
            duration: nil // TODO: Calculate duration from toolUse to toolResult
        )

        let richContent = RichContent(
            contentType: .toolResult,
            data: .toolResult(toolResultData)
        )

        let resultIcon = toolResult.success ? "✅" : "❌"
        let content = toolResult.success
            ? "\(resultIcon) \(toolResult.toolName) completed"
            : "\(resultIcon) \(toolResult.toolName) failed: \(toolResult.error ?? "Unknown error")"

        let resultMessage = Message(
            id: UUID(),
            content: content,
            sender: .system,
            timestamp: Date(),
            type: .toolResult,
            richContent: richContent
        )

        messages.append(resultMessage)
        persistenceService.addMessageToCurrentConversation(resultMessage)
    }

    private func handleConversationResult(_ message: WebSocketMessage) {
        guard case .conversationResult(let result) = message.data else { return }

        if let finalResult = result.result, !finalResult.isEmpty {
            let conversationMessage = Message(
                id: UUID(),
                content: finalResult,
                sender: .claude,
                timestamp: Date(),
                type: .text,
                metadata: ClaudeMessageMetadata(
                    sessionId: result.sessionId ?? "",
                    duration: result.duration ?? 0,
                    cost: result.cost,
                    tools: result.usage?.serverToolUse != nil ? ["server_tools"] : nil
                )
            )

            messages.append(conversationMessage)
            persistenceService.addMessageToCurrentConversation(conversationMessage)
        }

        // Update streaming state
        finalizeStreamingMessage()
    }

    private func setWorkingDirectory(_ directory: String) {
        webSocketService.setWorkingDirectory(directory) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let success):
                    if success {
                        self.workingDirectoryText = directory

                        // Analyze project context
                        _ = self.projectAwarenessService.analyzeProject(at: directory)

                        // Update conversation working directory
                        self.persistenceService.updateCurrentConversationWorkingDirectory(directory)

                        let successMessage = Message(
                            id: UUID(),
                            content: "📁 Working directory set to: \(directory)",
                            sender: .system,
                            timestamp: Date(),
                            type: .system
                        )
                        self.messages.append(successMessage)
                        self.persistenceService.addMessageToCurrentConversation(successMessage)
                    } else {
                        let errorMessage = Message(
                            id: UUID(),
                            content: "❌ Failed to set working directory",
                            sender: .system,
                            timestamp: Date(),
                            type: .error
                        )
                        self.messages.append(errorMessage)
                        self.persistenceService.addMessageToCurrentConversation(errorMessage)
                    }
                case .failure(let error):
                    let errorMessage = Message(
                        id: UUID(),
                        content: "❌ Error setting working directory: \(error.localizedDescription)",
                        sender: .system,
                        timestamp: Date(),
                        type: .error
                    )
                    self.messages.append(errorMessage)
                    self.persistenceService.addMessageToCurrentConversation(errorMessage)
                }
            }
        }
    }

    // MARK: - Utility Functions

    private func extractCodeBlocks(from text: String) -> (plainText: String, codeBlocks: [CodeBlockData]) {
        var codeBlocks: [CodeBlockData] = []
        var plainText = text

        // Simple regex pattern for code blocks
        let pattern = #"```(\w+)?\n(.*?)\n```"#

        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
            let range = NSRange(location: 0, length: text.utf16.count)
            let matches = regex.matches(in: text, options: [], range: range)

            // Process matches in reverse order to maintain indices
            for match in matches.reversed() {
                let _ = String(text[Range(match.range, in: text)!])

                // Extract language if present
                var language: String?
                if match.numberOfRanges > 1 && match.range(at: 1).location != NSNotFound {
                    language = String(text[Range(match.range(at: 1), in: text)!])
                }

                // Extract code content
                var code = ""
                if match.numberOfRanges > 2 && match.range(at: 2).location != NSNotFound {
                    code = String(text[Range(match.range(at: 2), in: text)!])
                }

                let codeBlock = CodeBlockData(
                    code: code,
                    language: language,
                    filename: nil,
                    startLine: nil,
                    endLine: nil
                )

                codeBlocks.insert(codeBlock, at: 0)

                // Remove the code block from plain text
                let replacementRange = Range(match.range, in: text)!
                plainText = plainText.replacingCharacters(in: replacementRange, with: "")
            }
        } catch {
            print("Regex error: \(error)")
        }

        return (plainText.trimmingCharacters(in: .whitespacesAndNewlines), codeBlocks)
    }

    // MARK: - Conversation Management

    private func loadConversation(_ conversation: Conversation) {
        persistenceService.switchToConversation(conversation)
        messages = conversation.messages
        activeSessionId = conversation.sessionId
        workingDirectoryText = conversation.workingDirectory ?? ""

        // Update working directory if set
        if let workingDir = conversation.workingDirectory {
            setWorkingDirectory(workingDir)
            // Analyze project context for the working directory
            _ = projectAwarenessService.analyzeProject(at: workingDir)
        }
    }

    private func startNewConversation() {
        _ = persistenceService.createNewConversation(
            sessionId: activeSessionId,
            workingDirectory: workingDirectoryText.isEmpty ? nil : workingDirectoryText
        )
        messages = []

        // Clear any streaming state
        currentStreamingMessage = nil
        isLoading = false
    }

    private func clearCurrentChat() {
        messages.removeAll()
        if let currentConversation = persistenceService.currentConversation {
            persistenceService.deleteConversation(currentConversation)
        }
        startNewConversation()
    }

    private func handleSuggestionTap(_ suggestion: ProjectSuggestion) {
        // If suggestion has a command, execute it or add it to chat
        if let command = suggestion.command {
            // Add the suggestion as a user message
            let suggestionMessage = Message(
                id: UUID(),
                content: "\(suggestion.title): \(command)",
                sender: .user,
                timestamp: Date(),
                type: .text
            )

            messages.append(suggestionMessage)
            persistenceService.addMessageToCurrentConversation(suggestionMessage)

            // Send the command to Claude
            messageText = command
            sendMessage()
        } else {
            // Add the suggestion as a prompt
            messageText = suggestion.description
        }
    }

    // MARK: - File Management Handlers

    private func handleFileSelected(_ file: FileItem) {
        // Generate quick action prompts for the selected file
        let prompts = fileManagementService.generateFilePrompts(for: file)

        if !prompts.isEmpty {
            // Use the first prompt as the default action
            messageText = prompts.first!
        } else {
            // Fallback to basic file reading
            messageText = "Read and analyze the file \(file.name)"
        }

        // Close the file browser
        showingFileBrowser = false
    }

    private func handleDirectoryChanged(_ directory: String) {
        // Update working directory if it's different
        if directory != workingDirectoryText {
            setWorkingDirectory(directory)
        }

        // Update file management service
        fileManagementService.navigateToDirectory(directory)

        // Update workflow service
        workflowService.updateWorkingDirectory(directory)
    }

    private func handleWorkflowCommand(_ command: String) {
        // Add the workflow command as a user message and send it
        messageText = command
        showingWorkflowView = false
        sendMessage()
    }
}

struct MessageBubble: View {
    let message: Message
    @State private var showActions = false

    var body: some View {
        HStack {
            if message.sender == .user {
                Spacer()
            }

            VStack(alignment: message.sender == .user ? .trailing : .leading, spacing: 4) {
                // Rich content or simple text
                if let richContent = message.richContent {
                    RichContentView(content: richContent)
                        .padding(8)
                        .background(backgroundColor)
                        .cornerRadius(16)
                } else {
                    Text(message.content)
                        .padding(12)
                        .background(backgroundColor)
                        .foregroundColor(textColor)
                        .cornerRadius(16)
                        .textSelection(.enabled)
                }

                HStack {
                    if message.sender == .claude, let metadata = message.metadata {
                        Text("Session: \(metadata.sessionId.prefix(8))...")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: message.sender == .user ? .trailing : .leading)
            }

            if message.sender != .user {
                Spacer()
            }
        }
        .onTapGesture {
            if message.sender == .claude {
                HapticManager.shared.selectionChanged()
                withAnimation(AnimationConstants.springSnappy) {
                    showActions.toggle()
                }
            }
        }
        .accessibleMessage(
            sender: message.sender.rawValue.capitalized,
            content: message.content,
            timestamp: message.timestamp,
            hasRichContent: message.richContent != nil
        )
    }

    private func shareMessage() {
        let content = "From Claude:\\n\\n\(message.content)"
        let activityController = UIActivityViewController(
            activityItems: [content],
            applicationActivities: nil
        )

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(activityController, animated: true)
        }
    }

    private var backgroundColor: Color {
        switch message.sender {
        case .user:
            return .blue
        case .claude:
            return Color.gray.opacity(0.2)
        case .system:
            return Color.red.opacity(0.2)
        }
    }

    private var textColor: Color {
        switch message.sender {
        case .user:
            return .white
        case .claude, .system:
            return .primary
        }
    }
}

struct TypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.gray)
                        .frame(width: 8, height: 8)
                        .scaleEffect(animating ? 1.0 : 0.5)
                        .animation(
                            AnimationConstants.messageTyping.delay(Double(index) * 0.2),
                            value: animating
                        )
                }
            }
            .padding(12)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(16)

            Spacer()
        }
        .slideIn(delay: 0, from: .leading)
        .onAppear {
            animating = true
            HapticManager.shared.messageReceived()
        }
        .accessibilityLabel("Claude is typing")
        .accessibilityHint("Claude is composing a response")
    }
}

struct WorkingDirectorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var directoryPath: String
    let onSetDirectory: (String) -> Void

    init(currentDirectory: String, onSetDirectory: @escaping (String) -> Void) {
        self._directoryPath = State(initialValue: currentDirectory.isEmpty ? "/Users/\(NSUserName())" : currentDirectory)
        self.onSetDirectory = onSetDirectory
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Working Directory")
                        .font(.headline)

                    Text("Set the working directory for Claude Code operations. This determines where commands will be executed and files will be read/written.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Directory Path")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    TextField("Enter directory path...", text: $directoryPath)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Working Directory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Set") {
                        onSetDirectory(directoryPath)
                        dismiss()
                    }
                    .disabled(directoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct RecentFilesContextBar: View {
    let recentFiles: [FileItem]
    let onFileSelected: (FileItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "clock")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Recent Files")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(recentFiles) { file in
                        Button(action: {
                            onFileSelected(file)
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: file.icon)
                                    .font(.caption)
                                    .foregroundColor(file.color)

                                Text(file.name)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .foregroundColor(.primary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(6)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.blue.opacity(0.05))
        .cornerRadius(8)
        .padding(.horizontal)
    }
}

struct WorkflowSuggestionsBar: View {
    let suggestions: [WorkflowSuggestion]
    let onCommandSelected: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "bolt")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Workflow Suggestions")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions, id: \.id) { suggestion in
                        Button(action: {
                            onCommandSelected(suggestion.command)
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: suggestion.icon)
                                    .font(.caption)
                                    .foregroundColor(priorityColor(suggestion.priority))

                                Text(suggestion.title)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .foregroundColor(.primary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(priorityColor(suggestion.priority).opacity(0.1))
                            .cornerRadius(6)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.purple.opacity(0.05))
        .cornerRadius(8)
        .padding(.horizontal)
    }

    private func priorityColor(_ priority: SuggestionPriority) -> Color {
        switch priority {
        case .critical: return .red
        case .high: return .orange
        case .medium: return .blue
        case .low: return .gray
        }
    }
}

#Preview {
    NavigationView {
        ChatView()
            .environmentObject(ClaudeCodeService())
    }
}
