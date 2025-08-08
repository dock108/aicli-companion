import Foundation
import SwiftUI

// MARK: - Tool Activity Models

@available(iOS 16.0, macOS 13.0, *)
struct ToolActivity: Identifiable, Equatable {
    let id: String
    let toolName: String
    let sessionId: String
    let startTime: Date
    var endTime: Date?
    var status: ToolActivityStatus
    var input: [String: Any]?
    var output: String?
    var error: String?

    var duration: TimeInterval? {
        guard let endTime = endTime else { return nil }
        return endTime.timeIntervalSince(startTime)
    }

    var isActive: Bool {
        return status == .running
    }

    static func == (lhs: ToolActivity, rhs: ToolActivity) -> Bool {
        return lhs.id == rhs.id
    }
}

@available(iOS 16.0, macOS 13.0, *)
enum ToolActivityStatus: String, CaseIterable {
    case running
    case completed
    case failed
    case cancelled

    var color: Color {
        switch self {
        case .running:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        case .cancelled:
            return .orange
        }
    }

    var icon: String {
        switch self {
        case .running:
            return "gear"
        case .completed:
            return "checkmark.circle"
        case .failed:
            return "xmark.circle"
        case .cancelled:
            return "stop.circle"
        }
    }
}

// MARK: - Tool Activity Manager

@available(iOS 16.0, macOS 13.0, *)
@available(iOS 16.0, macOS 13.0, *)
class ToolActivityManager: ObservableObject {
    @Published var activeTools: [ToolActivity] = []
    @Published var recentTools: [ToolActivity] = []

    private let maxRecentTools = 10

    func startTool(id: String, name: String, sessionId: String, input: [String: Any]? = nil) {
        let activity = ToolActivity(
            id: id,
            toolName: name,
            sessionId: sessionId,
            startTime: Date(),
            status: .running,
            input: input
        )

        DispatchQueue.main.async {
            self.activeTools.append(activity)
        }
    }

    func completeTool(id: String, output: String? = nil) {
        updateTool(id: id, status: .completed, output: output)
    }

    func failTool(id: String, error: String) {
        updateTool(id: id, status: .failed, error: error)
    }

    func cancelTool(id: String) {
        updateTool(id: id, status: .cancelled)
    }

    private func updateTool(id: String, status: ToolActivityStatus, output: String? = nil, error: String? = nil) {
        DispatchQueue.main.async {
            if let index = self.activeTools.firstIndex(where: { $0.id == id }) {
                var activity = self.activeTools[index]
                activity.status = status
                activity.endTime = Date()
                activity.output = output
                activity.error = error

                // Remove from active tools
                self.activeTools.remove(at: index)

                // Add to recent tools
                self.recentTools.insert(activity, at: 0)

                // Keep only recent tools
                if self.recentTools.count > self.maxRecentTools {
                    self.recentTools = Array(self.recentTools.prefix(self.maxRecentTools))
                }
            }
        }
    }

    func clearRecentTools() {
        DispatchQueue.main.async {
            self.recentTools.removeAll()
        }
    }

    func hasActiveTools(for sessionId: String) -> Bool {
        return activeTools.contains { $0.sessionId == sessionId }
    }

    func getActiveTools(for sessionId: String) -> [ToolActivity] {
        return activeTools.filter { $0.sessionId == sessionId }
    }
}

// MARK: - Tool Activity Views

@available(iOS 16.0, macOS 13.0, *)
@available(iOS 16.0, macOS 13.0, *)
struct ToolActivityIndicator: View {
    let activity: ToolActivity
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 8) {
            // Tool icon with animation
            Image(systemName: activity.status.icon)
                .foregroundColor(activity.status.color)
                .scaleEffect(isAnimating && activity.isActive ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isAnimating)

            VStack(alignment: .leading, spacing: 2) {
                Text(activity.toolName)
                    .font(.caption)
                    .fontWeight(.medium)

                if activity.isActive {
                    Text("Running...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else if let duration = activity.duration {
                    Text("\(Int(duration * 1000))ms")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if activity.isActive {
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(activity.status.color.opacity(0.1))
        .cornerRadius(8)
        .onAppear {
            if activity.isActive {
                isAnimating = true
            }
        }
        .onDisappear {
            isAnimating = false
        }
    }
}

@available(iOS 16.0, macOS 13.0, *)
@available(iOS 16.0, macOS 13.0, *)
struct ToolActivityList: View {
    @ObservedObject var activityManager: ToolActivityManager
    let sessionId: String?

    var filteredActiveTools: [ToolActivity] {
        if let sessionId = sessionId {
            return activityManager.activeTools.filter { $0.sessionId == sessionId }
        }
        return activityManager.activeTools
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !filteredActiveTools.isEmpty {
                ForEach(filteredActiveTools) { activity in
                    ToolActivityIndicator(activity: activity)
                }
            }
        }
    }
}

@available(iOS 16.0, macOS 13.0, *)
@available(iOS 16.0, macOS 13.0, *)
struct ToolActivityOverlay: View {
    @ObservedObject var activityManager: ToolActivityManager
    let sessionId: String?

    var filteredActiveTools: [ToolActivity] {
        if let sessionId = sessionId {
            return activityManager.activeTools.filter { $0.sessionId == sessionId }
        }
        return activityManager.activeTools
    }

    var body: some View {
        if !filteredActiveTools.isEmpty {
            VStack {
                Spacer()

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Tool Activity")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)

                        Spacer()

                        Text("\(filteredActiveTools.count) active")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    ForEach(filteredActiveTools.prefix(3)) { activity in
                        ToolActivityIndicator(activity: activity)
                    }

                    if filteredActiveTools.count > 3 {
                        Text("... and \(filteredActiveTools.count - 3) more")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                    }
                }
                .padding(12)
                .background(.regularMaterial)
                .cornerRadius(12)
                .shadow(radius: 4)
                .padding(.horizontal)
                .padding(.bottom, 80) // Account for input area
            }
        }
    }
}

// MARK: - Tool Activity Sheet

@available(iOS 16.0, macOS 13.0, *)
@available(iOS 16.0, macOS 13.0, *)
struct ToolActivitySheet: View {
    @ObservedObject var activityManager: ToolActivityManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if !activityManager.activeTools.isEmpty {
                    Section("Active Tools") {
                        ForEach(activityManager.activeTools) { activity in
                            ToolActivityDetailRow(activity: activity)
                        }
                    }
                }

                if !activityManager.recentTools.isEmpty {
                    Section("Recent Activity") {
                        ForEach(activityManager.recentTools) { activity in
                            ToolActivityDetailRow(activity: activity)
                        }
                    }
                }

                if activityManager.activeTools.isEmpty && activityManager.recentTools.isEmpty {
                    Section {
                        Text("No tool activity yet")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .navigationTitle("Tool Activity")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .automatic) {
                    Button("Clear") {
                        activityManager.clearRecentTools()
                    }
                    .disabled(activityManager.recentTools.isEmpty)
                }
            }
        }
    }
}

@available(iOS 16.0, macOS 13.0, *)
@available(iOS 16.0, macOS 13.0, *)
struct ToolActivityDetailRow: View {
    let activity: ToolActivity
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: activity.status.icon)
                    .foregroundColor(activity.status.color)

                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.toolName)
                        .font(.headline)

                    Text(activity.startTime, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(activity.status.rawValue.capitalized)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(activity.status.color)

                    if let duration = activity.duration {
                        Text("\(Int(duration * 1000))ms")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else if activity.isActive {
                        Text("Running...")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Button(action: {
                    isExpanded.toggle()
                }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    if let output = activity.output, !output.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Output:")
                                .font(.caption)
                                .fontWeight(.medium)

                            Text(output)
                                .font(.system(.caption, design: .monospaced))
                                .padding(8)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }

                    if let error = activity.error {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Error:")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.red)

                            Text(error)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(Color.red)
                                .padding(8)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            isExpanded.toggle()
        }
    }
}
