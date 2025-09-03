import SwiftUI
import CloudKit

/// Displays CloudKit sync status and device coordination information
@available(iOS 16.0, macOS 13.0, *)
public struct SyncStatusView: View {
    @ObservedObject private var cloudKitSync: CloudKitSyncManager = .shared
    @ObservedObject private var deviceCoordinator: DeviceCoordinator = .shared
    @State private var showingSyncDetails = false
    @State private var showingDeviceList = false
    
    public init() {}
    
    public var body: some View {
        HStack(spacing: 12) {
            // CloudKit Sync Status
            syncStatusButton
            
            // Device Coordination Status
            deviceStatusButton
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        .sheet(isPresented: $showingSyncDetails) {
            SyncDetailsView()
        }
        .sheet(isPresented: $showingDeviceList) {
            DeviceListView()
        }
    }
    
    // MARK: - Sync Status Button
    
    private var syncStatusButton: some View {
        Button(action: { showingSyncDetails = true }) {
            HStack(spacing: 6) {
                syncStatusIcon
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(syncStatusText)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(syncStatusColor)
                    
                    if let lastSyncDate = cloudKitSync.lastSyncDate {
                        Text(relativeDateString(for: lastSyncDate))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
    
    private var syncStatusIcon: some View {
        Group {
            switch cloudKitSync.syncStatus {
            case .syncing:
                ProgressView()
                    .scaleEffect(0.8)
                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
            case .synced:
                Image(systemName: "icloud.and.arrow.up")
                    .foregroundColor(.green)
            case .failed:
                Image(systemName: "icloud.slash")
                    .foregroundColor(.red)
            case .pending:
                Image(systemName: "icloud")
                    .foregroundColor(.orange)
            default:
                Image(systemName: "icloud")
                    .foregroundColor(.gray)
            }
        }
        .frame(width: 16, height: 16)
    }
    
    private var syncStatusText: String {
        if !cloudKitSync.iCloudAvailable {
            return "iCloud Unavailable"
        }
        
        switch cloudKitSync.syncStatus {
        case .syncing:
            return "Syncing..."
        case .synced:
            return "Synced"
        case .failed:
            return "Sync Failed"
        case .pending:
            return "Sync Pending"
        default:
            return "Unknown"
        }
    }
    
    private var syncStatusColor: Color {
        switch cloudKitSync.syncStatus {
        case .syncing:
            return .blue
        case .synced:
            return .green
        case .failed:
            return .red
        case .pending:
            return .orange
        default:
            return .gray
        }
    }
    
    // MARK: - Device Status Button
    
    private var deviceStatusButton: some View {
        Button(action: { showingDeviceList = true }) {
            HStack(spacing: 6) {
                deviceStatusIcon
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(deviceStatusText)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(deviceStatusColor)
                    
                    Text("\(deviceCoordinator.activeDevices.count + 1) device\(deviceCoordinator.activeDevices.count == 0 ? "" : "s")")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
    
    private var deviceStatusIcon: some View {
        Group {
            if deviceCoordinator.isPrimary {
                Image(systemName: "crown.fill")
                    .foregroundColor(.yellow)
            } else if !deviceCoordinator.activeDevices.isEmpty {
                Image(systemName: "person.2")
                    .foregroundColor(.blue)
            } else {
                Image(systemName: "person")
                    .foregroundColor(.gray)
            }
        }
        .frame(width: 16, height: 16)
    }
    
    private var deviceStatusText: String {
        if deviceCoordinator.isPrimary {
            return "Primary Device"
        } else if !deviceCoordinator.activeDevices.isEmpty {
            return "Secondary Device"
        } else {
            return "Only Device"
        }
    }
    
    private var deviceStatusColor: Color {
        if deviceCoordinator.isPrimary {
            return .yellow
        } else if !deviceCoordinator.activeDevices.isEmpty {
            return .blue
        } else {
            return .gray
        }
    }
    
    // MARK: - Helper Methods
    
    private func relativeDateString(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Sync Details View

@available(iOS 16.0, macOS 13.0, *)
private struct SyncDetailsView: View {
    @ObservedObject private var cloudKitSync: CloudKitSyncManager = .shared
    @Environment(\.dismiss) private var dismiss
    @State private var isRefreshing = false
    
    var body: some View {
        NavigationView {
            List {
                Section("iCloud Status") {
                    StatusRow(
                        title: "iCloud Available",
                        value: cloudKitSync.iCloudAvailable ? "Yes" : "No",
                        systemImage: cloudKitSync.iCloudAvailable ? "checkmark.circle.fill" : "xmark.circle.fill",
                        color: cloudKitSync.iCloudAvailable ? .green : .red
                    )
                    
                    StatusRow(
                        title: "Sync Status",
                        value: syncStatusDescription,
                        systemImage: syncStatusIcon,
                        color: syncStatusColor
                    )
                    
                    if let lastSync = cloudKitSync.lastSyncDate {
                        StatusRow(
                            title: "Last Sync",
                            value: DateFormatter.shortDateTime.string(from: lastSync),
                            systemImage: "clock",
                            color: .blue
                        )
                    }
                }
                
                if cloudKitSync.syncStatus == .syncing {
                    Section("Sync Progress") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Progress")
                                Spacer()
                                Text("\(Int(cloudKitSync.syncProgress * 100))%")
                                    .foregroundColor(.secondary)
                            }
                            
                            ProgressView(value: cloudKitSync.syncProgress)
                                .progressViewStyle(LinearProgressViewStyle())
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                if let errorMessage = cloudKitSync.errorMessage {
                    Section("Error") {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
                
                Section("Actions") {
                    Button(action: refreshSync) {
                        HStack {
                            if isRefreshing {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text("Refresh from iCloud")
                        }
                    }
                    .disabled(isRefreshing || !cloudKitSync.iCloudAvailable)
                    
                    Button(action: performFullSync) {
                        HStack {
                            Image(systemName: "icloud.and.arrow.up.fill")
                            Text("Force Full Sync")
                        }
                    }
                    .disabled(isRefreshing || !cloudKitSync.iCloudAvailable)
                }
            }
            .navigationTitle("Sync Status")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            #else
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            #endif
        }
    }
    
    private var syncStatusDescription: String {
        switch cloudKitSync.syncStatus {
        case .syncing:
            return "Syncing with iCloud..."
        case .synced:
            return "Up to date"
        case .failed:
            return "Failed to sync"
        case .pending:
            return "Waiting to sync"
        default:
            return "Unknown"
        }
    }
    
    private var syncStatusIcon: String {
        switch cloudKitSync.syncStatus {
        case .syncing:
            return "arrow.triangle.2.circlepath"
        case .synced:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .pending:
            return "clock.fill"
        default:
            return "questionmark.circle"
        }
    }
    
    private var syncStatusColor: Color {
        switch cloudKitSync.syncStatus {
        case .syncing:
            return .blue
        case .synced:
            return .green
        case .failed:
            return .red
        case .pending:
            return .orange
        default:
            return .gray
        }
    }
    
    private func refreshSync() {
        isRefreshing = true
        Task {
            do {
                try await cloudKitSync.refreshFromCloudKit()
            } catch {
                print("Failed to refresh from CloudKit: \(error)")
            }
            
            await MainActor.run {
                isRefreshing = false
            }
        }
    }
    
    private func performFullSync() {
        isRefreshing = true
        Task {
            do {
                try await cloudKitSync.performFullSync()
            } catch {
                print("Failed to perform full sync: \(error)")
            }
            
            await MainActor.run {
                isRefreshing = false
            }
        }
    }
}

// MARK: - Device List View

@available(iOS 16.0, macOS 13.0, *)
private struct DeviceListView: View {
    @ObservedObject private var deviceCoordinator: DeviceCoordinator = .shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingTransferAlert = false
    @State private var targetDeviceId: String?
    
    var body: some View {
        NavigationView {
            List {
                Section("Current Device") {
                    DeviceRow(
                        deviceId: deviceCoordinator.currentDeviceId,
                        isPrimary: deviceCoordinator.isPrimary,
                        isCurrentDevice: true
                    )
                }
                
                if !deviceCoordinator.activeDevices.isEmpty {
                    Section("Other Devices") {
                        ForEach(deviceCoordinator.activeDevices) { device in
                            DeviceRow(
                                deviceId: device.deviceId,
                                platform: device.platform,
                                lastSeen: device.lastSeen,
                                isPrimary: device.isPrimary,
                                isCurrentDevice: false
                            ) {
                                if deviceCoordinator.isPrimary {
                                    targetDeviceId = device.deviceId
                                    showingTransferAlert = true
                                }
                            }
                        }
                    }
                }
                
                Section("Device Coordination") {
                    if !deviceCoordinator.isPrimary && deviceCoordinator.primaryElectionStatus != .requesting {
                        Button("Request Primary Status") {
                            Task {
                                do {
                                    try await deviceCoordinator.requestPrimary()
                                } catch {
                                    print("Failed to request primary status: \(error)")
                                }
                            }
                        }
                    }
                    
                    if deviceCoordinator.isPrimary {
                        Button("Release Primary Status") {
                            Task {
                                do {
                                    try await deviceCoordinator.releasePrimary()
                                } catch {
                                    print("Failed to release primary status: \(error)")
                                }
                            }
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Devices")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            #else
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            #endif
        }
        .alert("Transfer Primary Status", isPresented: $showingTransferAlert) {
            Button("Transfer") {
                if let deviceId = targetDeviceId {
                    Task {
                        do {
                            try await deviceCoordinator.transferPrimary(to: deviceId)
                        } catch {
                            print("Failed to transfer primary status: \(error)")
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Transfer primary device status to the selected device?")
        }
    }
}

// MARK: - Supporting Views

@available(iOS 16.0, macOS 13.0, *)
private struct StatusRow: View {
    let title: String
    let value: String
    let systemImage: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: systemImage)
                .foregroundColor(color)
                .frame(width: 20)
            
            Text(title)
            
            Spacer()
            
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}

@available(iOS 16.0, macOS 13.0, *)
private struct DeviceRow: View {
    let deviceId: String
    let platform: String?
    let lastSeen: Date?
    let isPrimary: Bool
    let isCurrentDevice: Bool
    let onTap: (() -> Void)?
    
    init(
        deviceId: String,
        platform: String? = nil,
        lastSeen: Date? = nil,
        isPrimary: Bool,
        isCurrentDevice: Bool,
        onTap: (() -> Void)? = nil
    ) {
        self.deviceId = deviceId
        self.platform = platform
        self.lastSeen = lastSeen
        self.isPrimary = isPrimary
        self.isCurrentDevice = isCurrentDevice
        self.onTap = onTap
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(isCurrentDevice ? "This Device" : (platform ?? "iOS"))
                        .font(.headline)
                    
                    if isPrimary {
                        Image(systemName: "crown.fill")
                            .foregroundColor(.yellow)
                            .font(.caption)
                    }
                }
                
                Text(deviceId.prefix(8) + "...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let lastSeen = lastSeen {
                    Text("Last seen \(RelativeDateTimeFormatter().localizedString(for: lastSeen, relativeTo: Date()))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if isPrimary {
                Text("Primary")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.yellow.opacity(0.2))
                    .foregroundColor(.yellow)
                    .cornerRadius(8)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
    }
}

// MARK: - DateFormatter Extension

private extension DateFormatter {
    static let shortDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

// MARK: - Preview

@available(iOS 16.0, macOS 13.0, *)
#Preview {
    VStack {
        SyncStatusView()
            .padding()
        
        Spacer()
    }
    .background(Color.gray.opacity(0.1))
}