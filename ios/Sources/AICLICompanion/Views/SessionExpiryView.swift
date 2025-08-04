import SwiftUI

/// View that displays session expiry information and active sessions
@available(iOS 16.0, macOS 13.0, *)
struct SessionExpiryView: View {
    @StateObject private var sessionStatePersistence = SessionStatePersistenceService.shared
    @State private var showingExpiredAlert = false
    @State private var expiredSessionId: String?
    
    var body: some View {
        NavigationView {
            List {
                if sessionStatePersistence.activeSessions.isEmpty {
                    ContentUnavailableView(
                        "No Active Sessions",
                        systemImage: "clock.fill",
                        description: Text("Start a project conversation to see active sessions here")
                    )
                } else {
                    Section {
                        ForEach(sessionStatePersistence.activeSessions) { session in
                            SessionExpiryRow(session: session)
                        }
                    } header: {
                        Text("Active Sessions")
                    } footer: {
                        Text("Sessions expire after 7 days of inactivity")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Session Status")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Clean Up") {
                        performCleanup()
                    }
                }
            }
        }
        .alert("Session Expired", isPresented: $showingExpiredAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This session has expired and will be removed.")
        }
    }
    
    private func performCleanup() {
        sessionStatePersistence.cleanupExpiredSessions()
    }
}

/// Row view for displaying individual session expiry information
@available(iOS 16.0, macOS 13.0, *)
struct SessionExpiryRow: View {
    let session: SessionStatePersistenceService.SessionStateInfo
    @State private var timeRemaining: String = ""
    
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.projectName)
                    .font(.headline)
                Spacer()
                if session.isExpired {
                    Label("Expired", systemImage: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                } else {
                    Label(timeRemaining, systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Text(session.projectPath)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            
            HStack {
                Label("Created", systemImage: "calendar")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(session.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Label("Messages", systemImage: "message")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("\(session.messageCount)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            updateTimeRemaining()
        }
        .onReceive(timer) { _ in
            updateTimeRemaining()
        }
    }
    
    private func updateTimeRemaining() {
        if session.isExpired {
            timeRemaining = "Expired"
        } else {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            timeRemaining = formatter.localizedString(for: session.expiresAt, relativeTo: Date())
        }
    }
}

// MARK: - Preview
#if DEBUG
@available(iOS 16.0, macOS 13.0, *)
struct SessionExpiryView_Previews: PreviewProvider {
    static var previews: some View {
        SessionExpiryView()
    }
}
#endif