import SwiftUI

/// View that displays connection quality status
@available(iOS 16.0, macOS 13.0, *)
struct ConnectionQualityIndicator: View {
    @StateObject private var reliabilityManager = ConnectionReliabilityManager.shared
    @State private var showingDetails = false
    
    var body: some View {
        Button(action: {
            showingDetails.toggle()
        }) {
            if reliabilityManager.isReconnecting {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(0.5)
                    .frame(width: 10, height: 10)
                    .foregroundColor(.gray)
            } else {
                Image(systemName: reliabilityManager.connectionQuality.icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(qualityColor)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingDetails) {
            ConnectionDetailsView()
        }
    }
    
    private var qualityColor: Color {
        switch reliabilityManager.connectionQuality {
        case .excellent:
            return .green
        case .good:
            return .blue
        case .fair:
            return .yellow
        case .poor:
            return .orange
        case .offline:
            return .red
        case .unknown:
            return .gray
        }
    }
}

/// Detailed connection information view
@available(iOS 16.0, macOS 13.0, *)
struct ConnectionDetailsView: View {
    @StateObject private var reliabilityManager = ConnectionReliabilityManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        NavigationView {
            ZStack {
                Colors.bgBase(for: colorScheme)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        // Current Status
                        ConnectionStatusCard()
                        
                        // Reconnection Status
                        if reliabilityManager.isReconnecting {
                            ReconnectionCard()
                        }
                        
                        // Connection History
                        ConnectionHistoryCard()
                    }
                    .padding(Spacing.md)
                }
            }
            .navigationTitle("Connection Status")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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

/// Card showing current connection status
@available(iOS 16.0, macOS 13.0, *)
struct ConnectionStatusCard: View {
    @StateObject private var reliabilityManager = ConnectionReliabilityManager.shared
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: Spacing.md) {
            HStack {
                Image(systemName: reliabilityManager.connectionQuality.icon)
                    .font(.system(size: 40))
                    .foregroundColor(qualityColor)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(reliabilityManager.connectionQuality.rawValue)
                        .font(Typography.font(.heading3))
                        .foregroundColor(Colors.textPrimary(for: colorScheme))
                    
                    Text(statusDescription)
                        .font(Typography.font(.caption))
                        .foregroundColor(Colors.textSecondary(for: colorScheme))
                }
                
                Spacer()
            }
        }
        .padding(Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(Colors.bgCard(for: colorScheme))
        )
    }
    
    private var qualityColor: Color {
        switch reliabilityManager.connectionQuality {
        case .excellent:
            return .green
        case .good:
            return .blue
        case .fair:
            return .yellow
        case .poor:
            return .orange
        case .offline:
            return .red
        case .unknown:
            return .gray
        }
    }
    
    private var statusDescription: String {
        switch reliabilityManager.connectionQuality {
        case .excellent:
            return "Stable connection with no recent issues"
        case .good:
            return "Mostly stable with occasional hiccups"
        case .fair:
            return "Some connection issues detected"
        case .poor:
            return "Frequent disconnections or slowdowns"
        case .offline:
            return "No connection to server"
        case .unknown:
            return "Determining connection quality..."
        }
    }
}

/// Card showing reconnection progress
@available(iOS 16.0, macOS 13.0, *)
struct ReconnectionCard: View {
    @StateObject private var reliabilityManager = ConnectionReliabilityManager.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var timeRemaining: String = ""
    
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: Spacing.md) {
            HStack {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .tint(Colors.accentWarning)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reconnecting...")
                        .font(Typography.font(.headline))
                        .foregroundColor(Colors.textPrimary(for: colorScheme))
                    
                    Text("Attempt \(reliabilityManager.reconnectAttempt) • \(timeRemaining)")
                        .font(Typography.font(.caption))
                        .foregroundColor(Colors.textSecondary(for: colorScheme))
                }
                
                Spacer()
                
                Button("Cancel") {
                    reliabilityManager.cancelReconnection()
                }
                .font(Typography.font(.caption))
                .foregroundColor(Colors.accentDanger)
            }
        }
        .padding(Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(Colors.accentWarning.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .stroke(Colors.accentWarning.opacity(0.3), lineWidth: 1)
        )
        .onAppear {
            updateTimeRemaining()
        }
        .onReceive(timer) { _ in
            updateTimeRemaining()
        }
    }
    
    private func updateTimeRemaining() {
        if let nextReconnect = reliabilityManager.nextReconnectTime {
            let remaining = max(0, nextReconnect.timeIntervalSinceNow)
            if remaining > 0 {
                timeRemaining = "Next attempt in \(Int(remaining))s"
            } else {
                timeRemaining = "Connecting..."
            }
        } else {
            timeRemaining = ""
        }
    }
}

/// Card showing connection history
@available(iOS 16.0, macOS 13.0, *)
struct ConnectionHistoryCard: View {
    @StateObject private var reliabilityManager = ConnectionReliabilityManager.shared
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Recent Events")
                .font(Typography.font(.headline))
                .foregroundColor(Colors.textPrimary(for: colorScheme))
            
            if reliabilityManager.connectionHistory.isEmpty {
                Text("No recent connection events")
                    .font(Typography.font(.caption))
                    .foregroundColor(Colors.textSecondary(for: colorScheme))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Spacing.lg)
            } else {
                VStack(spacing: Spacing.sm) {
                    ForEach(Array(reliabilityManager.connectionHistory.suffix(10).reversed().enumerated()), id: \.offset) { _, event in
                        ConnectionEventRow(event: event)
                    }
                }
            }
        }
        .padding(Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(Colors.bgCard(for: colorScheme))
        )
    }
}

/// Row displaying a single connection event
@available(iOS 16.0, macOS 13.0, *)
struct ConnectionEventRow: View {
    let event: ConnectionReliabilityManager.ConnectionEvent
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: eventIcon)
                .font(.system(size: 14))
                .foregroundColor(eventColor)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(eventTitle)
                    .font(Typography.font(.caption))
                    .foregroundColor(Colors.textPrimary(for: colorScheme))
                
                if let details = event.details {
                    Text(details)
                        .font(Typography.font(.caption))
                        .foregroundColor(Colors.textSecondary(for: colorScheme))
                }
            }
            
            Spacer()
            
            Text(event.timestamp, style: .time)
                .font(Typography.font(.caption))
                .foregroundColor(Colors.textSecondary(for: colorScheme))
        }
        .padding(.vertical, 4)
    }
    
    private var eventIcon: String {
        switch event.type {
        case .connected:
            return "checkmark.circle.fill"
        case .disconnected:
            return "xmark.circle.fill"
        case .reconnecting:
            return "arrow.clockwise"
        case .qualityChanged:
            return "antenna.radiowaves.left.and.right"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }
    
    private var eventColor: Color {
        switch event.type {
        case .connected:
            return .green
        case .disconnected:
            return .red
        case .reconnecting:
            return .orange
        case .qualityChanged:
            return .blue
        case .error:
            return .red
        }
    }
    
    private var eventTitle: String {
        switch event.type {
        case .connected:
            return "Connected"
        case .disconnected:
            return "Disconnected"
        case .reconnecting:
            return "Reconnecting"
        case .qualityChanged:
            return "Quality: \(event.quality?.rawValue ?? "Unknown")"
        case .error:
            return "Error"
        }
    }
}
