import SwiftUI
import Charts

/// View displaying performance metrics and monitoring data
@available(iOS 16.0, macOS 13.0, *)
struct PerformanceDashboard: View {
    @StateObject private var performanceMonitor = PerformanceMonitor.shared
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
                        // Message Processing Metrics
                        MessageProcessingCard()
                        
                        // Connection Stability Metrics
                        ConnectionStabilityCard()
                        
                        // Current Session Stats
                        SessionStatsCard()
                    }
                    .padding(Spacing.md)
                }
            }
            .navigationTitle("Performance Metrics")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
                #else
                ToolbarItem(placement: .automatic) {
                    Button("Done") {
                        dismiss()
                    }
                }
                #endif
            }
        }
    }
}

/// Card showing message processing metrics
@available(iOS 16.0, macOS 13.0, *)
struct MessageProcessingCard: View {
    @StateObject private var performanceMonitor = PerformanceMonitor.shared
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Label("Message Processing", systemImage: "speedometer")
                    .font(Typography.font(.heading3))
                    .foregroundColor(Colors.textPrimary(for: colorScheme))
                
                Spacer()
            }
            
            VStack(spacing: Spacing.sm) {
                MetricRow(
                    title: "Average Processing Time",
                    value: String(format: "%.2fs", performanceMonitor.averageMessageProcessingTime),
                    icon: "clock",
                    color: performanceColorForTime(performanceMonitor.averageMessageProcessingTime)
                )
                
                MetricRow(
                    title: "Messages Processed",
                    value: "\(performanceMonitor.messagesProcessedCount)",
                    icon: "message",
                    color: .blue
                )
                
                if performanceMonitor.messagesProcessedCount > 0 {
                    ProgressView(value: min(performanceMonitor.averageMessageProcessingTime, 5.0), total: 5.0) {
                        Text("Processing Speed")
                            .font(Typography.font(.caption))
                            .foregroundColor(Colors.textSecondary(for: colorScheme))
                    }
                    .tint(performanceColorForTime(performanceMonitor.averageMessageProcessingTime))
                }
            }
        }
        .padding(Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(Colors.bgCard(for: colorScheme))
        )
    }
    
    private func performanceColorForTime(_ time: TimeInterval) -> Color {
        if time < 1.0 {
            return .green
        } else if time < 3.0 {
            return .yellow
        } else {
            return .red
        }
    }
}

/// Card showing connection stability metrics
@available(iOS 16.0, macOS 13.0, *)
struct ConnectionStabilityCard: View {
    @StateObject private var performanceMonitor = PerformanceMonitor.shared
    @StateObject private var reliabilityManager = ConnectionReliabilityManager.shared
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Label("Connection Stability", systemImage: "wifi")
                    .font(Typography.font(.heading3))
                    .foregroundColor(Colors.textPrimary(for: colorScheme))
                
                Spacer()
                
                ConnectionQualityBadge(quality: reliabilityManager.connectionQuality)
            }
            
            VStack(spacing: Spacing.sm) {
                MetricRow(
                    title: "Stability Score",
                    value: String(format: "%.0f%%", performanceMonitor.connectionStabilityScore),
                    icon: "chart.line.uptrend.xyaxis",
                    color: stabilityColor(performanceMonitor.connectionStabilityScore)
                )
                
                MetricRow(
                    title: "Connection Uptime",
                    value: String(format: "%.1f%%", performanceMonitor.connectionUptime * 100),
                    icon: "arrow.up.circle",
                    color: .green
                )
                
                if performanceMonitor.connectionStabilityScore < 100 {
                    HStack {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundColor(Colors.accentWarning)
                        
                        Text("Connection has been unstable recently")
                            .font(Typography.font(.caption))
                            .foregroundColor(Colors.textSecondary(for: colorScheme))
                    }
                    .padding(.top, 4)
                }
                
                // Stability gauge
                StabilityGauge(score: performanceMonitor.connectionStabilityScore)
                    .frame(height: 120)
                    .padding(.top, Spacing.sm)
            }
        }
        .padding(Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(Colors.bgCard(for: colorScheme))
        )
    }
    
    private func stabilityColor(_ score: Double) -> Color {
        if score >= 90 {
            return .green
        } else if score >= 70 {
            return .yellow
        } else {
            return .red
        }
    }
}

/// Card showing current session statistics
@available(iOS 16.0, macOS 13.0, *)
struct SessionStatsCard: View {
    @StateObject private var performanceMonitor = PerformanceMonitor.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var sessionDuration: String = "0m"
    
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Label("Current Session", systemImage: "timer")
                    .font(Typography.font(.heading3))
                    .foregroundColor(Colors.textPrimary(for: colorScheme))
                
                Spacer()
            }
            
            VStack(spacing: Spacing.sm) {
                MetricRow(
                    title: "Session Duration",
                    value: sessionDuration,
                    icon: "clock.fill",
                    color: .blue
                )
                
                let metrics = performanceMonitor.getCurrentMetrics()
                    MetricRow(
                        title: "Memory Usage",
                        value: String(format: "%.1f MB", metrics.metrics.app.memoryUsage),
                        icon: "memorychip",
                        color: memoryColor(metrics.metrics.app.memoryUsage)
                    )
            }
        }
        .padding(Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(Colors.bgCard(for: colorScheme))
        )
        .onAppear {
            updateSessionDuration()
        }
        .onReceive(timer) { _ in
            updateSessionDuration()
        }
    }
    
    private func updateSessionDuration() {
        let metrics = performanceMonitor.getCurrentMetrics()
        let duration = metrics.metrics.app.sessionDuration
        
        if duration < 3600 {
            sessionDuration = "\(Int(duration / 60))m"
        } else {
            let hours = Int(duration / 3600)
            let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
            sessionDuration = "\(hours)h \(minutes)m"
        }
    }
    
    private func memoryColor(_ usage: Double) -> Color {
        if usage < 100 {
            return .green
        } else if usage < 200 {
            return .yellow
        } else {
            return .red
        }
    }
}

/// Row displaying a single metric
@available(iOS 16.0, macOS 13.0, *)
struct MetricRow: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)
                .frame(width: 24)
            
            Text(title)
                .font(Typography.font(.body))
                .foregroundColor(Colors.textPrimary(for: colorScheme))
            
            Spacer()
            
            Text(value)
                .font(Typography.font(.heading3))
                .foregroundColor(color)
        }
        .padding(.vertical, 4)
    }
}

/// Connection quality badge
@available(iOS 16.0, macOS 13.0, *)
struct ConnectionQualityBadge: View {
    let quality: ConnectionReliabilityManager.ConnectionQuality
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: quality.icon)
                .font(.system(size: 12))
            
            Text(quality.rawValue)
                .font(Typography.font(.caption))
        }
        .foregroundColor(qualityColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(qualityColor.opacity(0.15))
        )
        .overlay(
            Capsule()
                .stroke(qualityColor.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var qualityColor: Color {
        switch quality {
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

/// Gauge view for stability score
@available(iOS 16.0, macOS 13.0, *)
struct StabilityGauge: View {
    let score: Double
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background arc
                Circle()
                    .trim(from: 0.25, to: 0.75)
                    .stroke(
                        colorScheme == .dark ? Colors.strokeLight : Colors.strokeDark,
                        style: StrokeStyle(lineWidth: 20, lineCap: .round)
                    )
                    .rotationEffect(.degrees(90))
                
                // Progress arc
                Circle()
                    .trim(from: 0.25, to: 0.25 + (score / 100) * 0.5)
                    .stroke(
                        LinearGradient(
                            colors: [stabilityColor(score), stabilityColor(score).opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 20, lineCap: .round)
                    )
                    .rotationEffect(.degrees(90))
                    .animation(.spring(), value: score)
                
                // Score text
                VStack(spacing: 4) {
                    Text(String(format: "%.0f", score))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(Colors.textPrimary(for: colorScheme))
                    
                    Text("Stability")
                        .font(Typography.font(.caption))
                        .foregroundColor(Colors.textSecondary(for: colorScheme))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
    
    private func stabilityColor(_ score: Double) -> Color {
        if score >= 90 {
            return .green
        } else if score >= 70 {
            return .yellow
        } else {
            return .red
        }
    }
}
