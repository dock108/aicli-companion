import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum ConversationFilter: String, CaseIterable {
    case all = "All"
    case active = "Active"
    case favorites = "Favorites"
    case archived = "Archived"
    case withTools = "With Tools"

    var icon: String {
        switch self {
        case .all: return "list.bullet"
        case .active: return "circle.fill"
        case .favorites: return "heart.fill"
        case .archived: return "archivebox.fill"
        case .withTools: return "gear"
        }
    }
}

@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
struct ConversationHistoryView: View {
    @ObservedObject var persistenceService: ConversationPersistenceService
    @Environment(\.presentationMode) var presentationMode

    @State private var searchText = ""
    @State private var showingExportOptions = false
    @State private var selectedConversation: Conversation?
    @State private var showingDeleteAlert = false
    @State private var conversationToDelete: Conversation?
    @State private var showingStatistics = false
    @State private var showingBulkActions = false
    @State private var selectedConversations: Set<UUID> = []
    @State private var isSelectMode = false
    @State private var filterMode: ConversationFilter = .all

    let onConversationSelected: (Conversation) -> Void

    var filteredConversations: [Conversation] {
        var conversations: [Conversation]

        // Apply filter mode
        switch filterMode {
        case .all:
            conversations = persistenceService.conversations
        case .favorites:
            conversations = persistenceService.getFavoriteConversations()
        case .archived:
            conversations = persistenceService.getArchivedConversations()
        case .active:
            conversations = persistenceService.getActiveConversations()
        case .withTools:
            conversations = persistenceService.getConversationsWithToolUsage()
        }

        // Apply search filter
        if !searchText.isEmpty {
            conversations = conversations.filter { conversation in
                conversation.title.localizedCaseInsensitiveContains(searchText) ||
                    conversation.messages.contains { message in
                        message.content.localizedCaseInsensitiveContains(searchText)
                    }
            }
        }

        return conversations
    }

    var body: some View {
        NavigationStack {
            VStack {
                // Filter tabs
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ConversationFilter.allCases, id: \.self) { filter in
                            Button(action: {
                                filterMode = filter
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: filter.icon)
                                        .font(.caption)
                                    Text(filter.rawValue)
                                        .font(.caption)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(filterMode == filter ? Color.blue : Color.gray.opacity(0.2))
                                .foregroundColor(filterMode == filter ? .white : .primary)
                                .cornerRadius(16)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)

                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)

                    TextField("Search conversations...", text: $searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                    if isSelectMode {
                        Button(isSelectMode ? "Cancel" : "Select") {
                            isSelectMode.toggle()
                            if !isSelectMode {
                                selectedConversations.removeAll()
                            }
                        }
                        .font(.caption)
                    }
                }
                .padding(.horizontal)

                // Conversations list
                if filteredConversations.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)

                        Text(searchText.isEmpty ? "No conversations yet" : "No conversations found")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        if searchText.isEmpty {
                            Text("Start a new conversation to see it here")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(filteredConversations) { conversation in
                            ConversationRow(
                                conversation: conversation,
                                isSelected: conversation.id == persistenceService.currentConversation?.id,
                                isSelectMode: isSelectMode,
                                isChecked: selectedConversations.contains(conversation.id),
                                onTap: {
                                    if isSelectMode {
                                        if selectedConversations.contains(conversation.id) {
                                            selectedConversations.remove(conversation.id)
                                        } else {
                                            selectedConversations.insert(conversation.id)
                                        }
                                    } else {
                                        onConversationSelected(conversation)
                                        presentationMode.wrappedValue.dismiss()
                                    }
                                },
                                onDelete: {
                                    conversationToDelete = conversation
                                    showingDeleteAlert = true
                                },
                                onExport: {
                                    selectedConversation = conversation
                                    showingExportOptions = true
                                },
                                onDuplicate: {
                                    _ = persistenceService.duplicateConversation(conversation)
                                },
                                onFavorite: {
                                    if conversation.metadata.isFavorite {
                                        persistenceService.unfavoriteConversation(conversation)
                                    } else {
                                        persistenceService.favoriteConversation(conversation)
                                    }
                                },
                                onArchive: {
                                    if conversation.metadata.isArchived {
                                        persistenceService.unarchiveConversation(conversation)
                                    } else {
                                        persistenceService.archiveConversation(conversation)
                                    }
                                }
                            )
                        }
                        .onDelete(perform: deleteConversations)
                    }
                }
            }
            .navigationTitle(isSelectMode ? "\(selectedConversations.count) Selected" : "Conversations")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if isSelectMode {
                        Button("Cancel") {
                            isSelectMode = false
                            selectedConversations.removeAll()
                        }
                    } else {
                        Button("Done") {
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                }

                ToolbarItem(placement: .automatic) {
                    if isSelectMode {
                        Menu {
                            Button("Export Selected") {
                                showingBulkActions = true
                            }
                            .disabled(selectedConversations.isEmpty)

                            Button("Archive Selected") {
                                persistenceService.bulkArchiveConversations(Array(selectedConversations))
                                selectedConversations.removeAll()
                                isSelectMode = false
                            }
                            .disabled(selectedConversations.isEmpty)

                            Divider()

                            Button("Delete Selected", role: .destructive) {
                                persistenceService.bulkDeleteConversations(Array(selectedConversations))
                                selectedConversations.removeAll()
                                isSelectMode = false
                            }
                            .disabled(selectedConversations.isEmpty)
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    } else {
                        Menu {
                            Button("Select") {
                                isSelectMode = true
                            }

                            Button("Statistics") {
                                showingStatistics = true
                            }

                            Button("New Conversation") {
                                let newConversation = persistenceService.createNewConversation()
                                onConversationSelected(newConversation)
                                presentationMode.wrappedValue.dismiss()
                            }

                            if !persistenceService.conversations.isEmpty {
                                Divider()

                                Button("Export All") {
                                    selectedConversations = Set(persistenceService.conversations.map { $0.id })
                                    showingBulkActions = true
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search conversations")
        .alert("Delete Conversation", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let conversation = conversationToDelete {
                    persistenceService.deleteConversation(conversation)
                }
            }
        } message: {
            Text("Are you sure you want to delete this conversation? This action cannot be undone.")
        }
        .sheet(isPresented: $showingExportOptions) {
            if let conversation = selectedConversation {
                ConversationExportSheet(
                    conversation: conversation,
                    persistenceService: persistenceService
                )
            }
        }
        .sheet(isPresented: $showingStatistics) {
            ConversationStatisticsView(persistenceService: persistenceService)
        }
        .sheet(isPresented: $showingBulkActions) {
            BulkExportSheet(
                conversationIds: Array(selectedConversations),
                persistenceService: persistenceService,
                onComplete: {
                    selectedConversations.removeAll()
                    isSelectMode = false
                    showingBulkActions = false
                }
            )
        }
    }

    private func deleteConversations(offsets: IndexSet) {
        for index in offsets {
            persistenceService.deleteConversation(filteredConversations[index])
        }
    }
}

@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
struct ConversationRow: View {
    let conversation: Conversation
    let isSelected: Bool
    let isSelectMode: Bool
    let isChecked: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    let onExport: () -> Void
    let onDuplicate: () -> Void
    let onFavorite: () -> Void
    let onArchive: () -> Void

    var body: some View {
        HStack {
            // Selection checkbox in select mode
            if isSelectMode {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isChecked ? .blue : .gray)
                    .font(.title3)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    // Favorite indicator
                    if conversation.metadata.isFavorite {
                        Image(systemName: "heart.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                    }

                    // Archive indicator
                    if conversation.metadata.isArchived {
                        Image(systemName: "archivebox.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                    }

                    Text(conversation.title)
                        .font(.headline)
                        .lineLimit(1)
                        .opacity(conversation.metadata.isArchived ? 0.6 : 1.0)

                    if isSelected && !isSelectMode {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.blue)
                            .font(.caption)
                    }

                    Spacer()

                    Text(conversation.updatedAt, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("\(conversation.metadata.messageCount) messages")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if conversation.metadata.hasToolUsage {
                        if #available(macOS 11.0, *) {
                            Image(systemName: "gear")
                                .font(.caption)
                                .foregroundColor(.blue)
                        } else {
                            Text("⚙️")
                                .font(.caption)
                        }
                    }

                    if conversation.metadata.hasRichContent {
                        if #available(macOS 11.0, *) {
                            Image(systemName: "doc.richtext")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else {
                            Text("📄")
                                .font(.caption)
                        }
                    }

                    if conversation.workingDirectory != nil {
                        if #available(macOS 11.0, *) {
                            Image(systemName: "folder")
                                .font(.caption)
                                .foregroundColor(.orange)
                        } else {
                            Text("📁")
                                .font(.caption)
                        }
                    }

                    Spacer()
                }

                if let lastMessage = conversation.messages.last {
                    Text(lastMessage.content.prefix(100))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .contextMenu {
            if !isSelectMode {
                Button(action: onTap) {
                    if #available(macOS 11.0, *) {
                        Label("Open", systemImage: "arrow.right.circle")
                    } else {
                        HStack {
                            Image(systemName: "arrow.right.circle")
                            Text("Open")
                        }
                    }
                }

                Divider()

                Button(action: onFavorite) {
                    if #available(macOS 11.0, *) {
                        Label(
                            conversation.metadata.isFavorite ? "Unfavorite" : "Favorite",
                            systemImage: conversation.metadata.isFavorite ? "heart.slash" : "heart"
                        )
                    } else {
                        HStack {
                            Image(systemName: conversation.metadata.isFavorite ? "heart.slash" : "heart")
                            Text(conversation.metadata.isFavorite ? "Unfavorite" : "Favorite")
                        }
                    }
                }

                Button(action: onArchive) {
                    if #available(macOS 11.0, *) {
                        Label(
                            conversation.metadata.isArchived ? "Unarchive" : "Archive",
                            systemImage: conversation.metadata.isArchived ? "tray.and.arrow.up" : "archivebox"
                        )
                    } else {
                        HStack {
                            Image(systemName: conversation.metadata.isArchived ? "tray.and.arrow.up" : "archivebox")
                            Text(conversation.metadata.isArchived ? "Unarchive" : "Archive")
                        }
                    }
                }

                Button(action: onDuplicate) {
                    if #available(macOS 11.0, *) {
                        Label("Duplicate", systemImage: "doc.on.doc")
                    } else {
                        HStack {
                            Image(systemName: "doc.on.doc")
                            Text("Duplicate")
                        }
                    }
                }

                Button(action: onExport) {
                    if #available(macOS 11.0, *) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    } else {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Export")
                        }
                    }
                }

                Divider()

                if #available(macOS 12.0, *) {
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                } else {
                    Button(action: onDelete) {
                        if #available(macOS 11.0, *) {
                            Label("Delete", systemImage: "trash")
                                .foregroundColor(.red)
                        } else {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete")
                            }
                            .foregroundColor(.red)
                        }
                    }
                }
            }
        }
    }
}

@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
struct ConversationExportSheet: View {
    let conversation: Conversation
    let persistenceService: ConversationPersistenceService
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Export Options")
                        .font(.headline)

                    Text("Choose how you'd like to export this conversation")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(spacing: 12) {
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        Button(action: {
                            exportAs(format)
                        }) {
                            HStack {
                                Image(systemName: format.icon)
                                    .foregroundColor(.blue)

                                VStack(alignment: .leading) {
                                    Text(format.rawValue)
                                        .font(.headline)
                                    Text(formatDescription(format))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Export Conversation")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }

    private func exportAs(_ format: ExportFormat) {
        if let url = persistenceService.exportConversation(conversation, format: format) {
            shareFile(url: url)
        }
        presentationMode.wrappedValue.dismiss()
    }

    private func formatDescription(_ format: ExportFormat) -> String {
        switch format {
        case .json:
            return "Complete conversation data with metadata"
        case .markdown:
            return "Formatted text with rich content support"
        case .text:
            return "Simple text format for sharing"
        case .html:
            return "Web-ready format with styling"
        case .csv:
            return "Spreadsheet format for data analysis"
        }
    }

    private func shareFile(url: URL) {
        #if os(iOS)
        let activityController = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(activityController, animated: true)
        }
        #else
        // On macOS, just open the file location
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
        #endif
    }
}

@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
struct BulkExportSheet: View {
    let conversationIds: [UUID]
    let persistenceService: ConversationPersistenceService
    let onComplete: () -> Void

    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Bulk Export")
                        .font(.headline)

                    Text("Export \(conversationIds.count) selected conversations")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(spacing: 12) {
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        Button(action: {
                            exportAs(format)
                        }) {
                            HStack {
                                Image(systemName: format.icon)
                                    .foregroundColor(.blue)

                                VStack(alignment: .leading) {
                                    Text("\(format.rawValue) Export")
                                        .font(.headline)
                                    Text(bulkFormatDescription(format))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Export Conversations")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }

    private func exportAs(_ format: ExportFormat) {
        if let url = persistenceService.bulkExportConversations(conversationIds, format: format) {
            shareFile(url: url)
        }
        onComplete()
        presentationMode.wrappedValue.dismiss()
    }

    private func bulkFormatDescription(_ format: ExportFormat) -> String {
        switch format {
        case .json:
            return "Single file with all conversation data"
        case .markdown:
            return "Combined document with all conversations"
        case .text:
            return "Plain text compilation of all conversations"
        case .html:
            return "Web document with all conversations"
        case .csv:
            return "Spreadsheet with all messages and metadata"
        }
    }

    private func shareFile(url: URL) {
        #if os(iOS)
        let activityController = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(activityController, animated: true)
        }
        #else
        // On macOS, just open the file location
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
        #endif
    }
}

@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
struct ConversationStatisticsView: View {
    let persistenceService: ConversationPersistenceService
    @Environment(\.presentationMode) var presentationMode

    var statistics: ConversationStatistics {
        persistenceService.getStatistics()
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Overview") {
                    StatisticRow(
                        title: "Total Conversations",
                        value: "\(statistics.totalConversations)",
                        icon: "bubble.left.and.bubble.right"
                    )

                    StatisticRow(
                        title: "Total Messages",
                        value: "\(statistics.totalMessages)",
                        icon: "message"
                    )

                    StatisticRow(
                        title: "Average Messages",
                        value: String(format: "%.1f", statistics.averageMessagesPerConversation),
                        icon: "chart.bar"
                    )
                }

                Section("Features") {
                    StatisticRow(
                        title: "With Tool Usage",
                        value: "\(statistics.conversationsWithTools)",
                        icon: "gear"
                    )

                    StatisticRow(
                        title: "With Rich Content",
                        value: "\(statistics.conversationsWithRichContent)",
                        icon: "doc.richtext"
                    )
                }

                if let totalCost = statistics.totalCost {
                    Section("Usage") {
                        StatisticRow(
                            title: "Total Cost",
                            value: String(format: "$%.4f", totalCost),
                            icon: "dollarsign.circle"
                        )
                    }
                }

                Section("Storage") {
                    let storageInfo = getStorageInfo()
                    StatisticRow(
                        title: "Disk Usage",
                        value: storageInfo.formattedSize,
                        icon: "internaldrive"
                    )

                    StatisticRow(
                        title: "Files",
                        value: "\(storageInfo.fileCount)",
                        icon: "doc.stack"
                    )
                }
            }
            .navigationTitle("Statistics")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }

    private func getStorageInfo() -> (fileCount: Int, totalSize: Int64, formattedSize: String) {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let conversationsDirectory = documentsDirectory.appendingPathComponent("Conversations")

        do {
            let files = try FileManager.default.contentsOfDirectory(at: conversationsDirectory, includingPropertiesForKeys: [.fileSizeKey])
            let totalSize = files.reduce(Int64(0)) { total, url in
                let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey])
                return total + Int64(resourceValues?.fileSize ?? 0)
            }

            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useKB, .useMB, .useGB]
            formatter.countStyle = .file

            return (files.count, totalSize, formatter.string(fromByteCount: totalSize))
        } catch {
            return (0, 0, "0 KB")
        }
    }
}

@available(iOS 16.0, iPadOS 16.0, macOS 13.0, *)
struct StatisticRow: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)

            Text(title)

            Spacer()

            Text(value)
                .fontWeight(.medium)
        }
    }
}

@available(iOS 17.0, iPadOS 17.0, macOS 14.0, *)
#Preview {
    ConversationHistoryView(
        persistenceService: ConversationPersistenceService(),
        onConversationSelected: { _ in }
    )
}
