import SwiftUI
import Combine

/// View component that displays the current interactive session status
/// Shows session lifetime, activity, and provides keep-alive functionality
@available(iOS 16.0, macOS 13.0, *)
struct SessionStatusView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var sessionInfo: SessionInfo?
    @State private var timeRemaining: TimeInterval = 0
    @State private var isExtending = false
    @State private var showRecap = false
    @State private var recapText: String = ""
    
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    var body: some View {
        Group {
            if let info = sessionInfo {
                VStack(alignment: .leading, spacing: 8) {
                    // Session header
                    HStack {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .foregroundColor(sessionColor(for: info))
                        
                        Text("Interactive Session")
                            .font(.caption)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        // Time remaining
                        Text(timeRemainingText)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    // Session details
                    HStack(spacing: 16) {
                        // Status indicator
                        HStack(spacing: 4) {
                            Circle()
                                .fill(sessionColor(for: info))
                                .frame(width: 8, height: 8)
                            Text(info.isActive ? "Active" : "Idle")
                                .font(.caption2)
                        }
                        
                        // Message count
                        if info.messageCount > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "message")
                                    .font(.caption2)
                                Text("\(info.messageCount)")
                                    .font(.caption2)
                            }
                            .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        // Keep-alive button
                        Button(action: extendSession) {
                            HStack(spacing: 4) {
                                if isExtending {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                } else {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .font(.caption)
                                }
                                Text("Extend")
                                    .font(.caption2)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .disabled(isExtending)
                    }
                    
                    // Warning if expiring soon
                    if timeRemaining < 3600 { // Less than 1 hour
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundColor(.orange)
                            Text("Session expiring soon - send a message to keep it active")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(6)
                    }
                    
                    // Recap section
                    if showRecap && !recapText.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Session Summary")
                                .font(.caption)
                                .fontWeight(.medium)
                            Text(recapText)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(3)
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(10)
                .onReceive(timer) { _ in
                    updateTimeRemaining()
                }
            }
        }
        .task {
            await fetchSessionInfo()
        }
        .onChange(of: viewModel.currentSessionId) { _ in
            Task {
                await fetchSessionInfo()
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private var timeRemainingText: String {
        let hours = Int(timeRemaining) / 3600
        let minutes = (Int(timeRemaining) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m remaining"
        } else if minutes > 0 {
            return "\(minutes)m remaining"
        } else {
            return "Expiring soon"
        }
    }
    
    private func sessionColor(for info: SessionInfo) -> Color {
        if !info.isActive {
            return .gray
        } else if timeRemaining < 3600 {
            return .orange
        } else {
            return .green
        }
    }
    
    private func updateTimeRemaining() {
        guard let info = sessionInfo else { return }
        let now = Date()
        timeRemaining = max(0, info.expiresAt.timeIntervalSince(now))
        
        // Auto-refresh if expired
        if timeRemaining == 0 {
            Task {
                await fetchSessionInfo()
            }
        }
    }
    
    private func fetchSessionInfo() async {
        guard let sessionId = viewModel.currentSessionId,
              let serverURL = SettingsManager.shared.serverURL else { return }
        
        do {
            let url = URL(string: "\(serverURL)/api/sessions/interactive/\(sessionId)/status")!
            let (data, _) = try await URLSession.shared.data(from: url)
            
            if let response = try? JSONDecoder().decode(StatusResponse.self, from: data),
               response.success {
                await MainActor.run {
                    self.sessionInfo = SessionInfo(
                        sessionId: sessionId,
                        isActive: response.active ?? false,
                        messageCount: response.messageCount ?? 0,
                        expiresAt: Date(timeIntervalSince1970: TimeInterval(response.expiresAt ?? 0) / 1000),
                        createdAt: Date(timeIntervalSince1970: TimeInterval(response.createdAt ?? 0) / 1000)
                    )
                    updateTimeRemaining()
                }
            }
        } catch {
            print("Failed to fetch session status: \(error)")
        }
    }
    
    private func extendSession() {
        guard let sessionId = viewModel.currentSessionId,
              let serverURL = SettingsManager.shared.serverURL else { return }
        
        isExtending = true
        showRecap = false
        
        Task {
            do {
                let url = URL(string: "\(serverURL)/api/sessions/keep-alive")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                
                let body = KeepAliveRequest(
                    sessionId: sessionId,
                    action: "recap"
                )
                request.httpBody = try JSONEncoder().encode(body)
                
                let (data, _) = try await URLSession.shared.data(for: request)
                
                if let response = try? JSONDecoder().decode(KeepAliveResponse.self, from: data),
                   response.success {
                    await MainActor.run {
                        if let recap = response.recap {
                            self.recapText = recap
                            self.showRecap = true
                        }
                        // Refresh session info
                        Task {
                            await fetchSessionInfo()
                        }
                    }
                }
            } catch {
                print("Failed to extend session: \(error)")
            }
            
            await MainActor.run {
                isExtending = false
            }
        }
    }
}

// MARK: - Data Models

private struct SessionInfo {
    let sessionId: String
    let isActive: Bool
    let messageCount: Int
    let expiresAt: Date
    let createdAt: Date
}

private struct StatusResponse: Codable {
    let success: Bool
    let sessionId: String?
    let active: Bool?
    let messageCount: Int?
    let expiresAt: Int64?
    let createdAt: Int64?
}

private struct KeepAliveRequest: Codable {
    let sessionId: String
    let action: String
}

private struct KeepAliveResponse: Codable {
    let success: Bool
    let extended: Bool?
    let recap: String?
}