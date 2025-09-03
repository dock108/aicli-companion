import SwiftUI

/// Compact device coordination status indicator for chat view
@available(iOS 16.0, macOS 13.0, *)
public struct DeviceCoordinationIndicator: View {
    @ObservedObject private var deviceCoordinator: DeviceCoordinator = .shared
    @ObservedObject private var cloudKitSync: CloudKitSyncManager = .shared
    
    @State private var showingDetails = false
    @State private var animateSync = false
    
    public init() {}
    
    public var body: some View {
        Button(action: { showingDetails = true }) {
            HStack(spacing: 8) {
                // Device Status Icon
                deviceStatusIcon
                    .frame(width: 16, height: 16)
                
                // Sync Status Icon
                syncStatusIcon
                    .frame(width: 16, height: 16)
                
                // Status Text
                Text(combinedStatusText)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.1))
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingDetails) {
            // TODO: Add SyncDetailsView implementation
            Text("Sync Details")
                .padding()
        }
        .onReceive(cloudKitSync.$syncStatus) { status in
            if status == .syncing {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    animateSync = true
                }
            } else {
                withAnimation(.easeOut(duration: 0.3)) {
                    animateSync = false
                }
            }
        }
    }
    
    // MARK: - Device Status Icon
    
    private var deviceStatusIcon: some View {
        Group {
            if deviceCoordinator.isPrimary {
                Image(systemName: "crown.fill")
                    .foregroundColor(.yellow)
            } else if !deviceCoordinator.activeDevices.isEmpty {
                Image(systemName: "person.2.fill")
                    .foregroundColor(.blue)
            } else {
                Image(systemName: "person.fill")
                    .foregroundColor(.gray)
            }
        }
    }
    
    // MARK: - Sync Status Icon
    
    private var syncStatusIcon: some View {
        Group {
            switch cloudKitSync.syncStatus {
            case .syncing:
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundColor(.blue)
                    .rotationEffect(.degrees(animateSync ? 360 : 0))
                    .animation(.linear(duration: 2.0).repeatForever(autoreverses: false), value: animateSync)
                
            case .synced:
                Image(systemName: "icloud.fill")
                    .foregroundColor(.green)
                
            case .failed:
                Image(systemName: "icloud.slash.fill")
                    .foregroundColor(.red)
                
            case .pending:
                Image(systemName: "icloud")
                    .foregroundColor(.orange)
                
            default:
                if cloudKitSync.iCloudAvailable {
                    Image(systemName: "icloud")
                        .foregroundColor(.gray)
                } else {
                    Image(systemName: "icloud.slash")
                        .foregroundColor(.red)
                }
            }
        }
    }
    
    // MARK: - Combined Status Text
    
    private var combinedStatusText: String {
        let deviceStatus = deviceCoordinator.isPrimary ? "Primary" : 
                          !deviceCoordinator.activeDevices.isEmpty ? "Secondary" : "Solo"
        
        let syncStatus = cloudKitSync.iCloudAvailable ? 
                        (cloudKitSync.syncStatus == .synced ? "Synced" : "Sync") :
                        "Offline"
        
        return "\(deviceStatus) • \(syncStatus)"
    }
}

// MARK: - Mini Sync Status Indicator

/// Ultra-compact sync status indicator for space-constrained areas
@available(iOS 16.0, macOS 13.0, *)
public struct MiniSyncStatusIndicator: View {
    @ObservedObject private var cloudKitSync: CloudKitSyncManager = .shared
    @State private var animateSync = false
    
    public init() {}
    
    public var body: some View {
        Group {
            switch cloudKitSync.syncStatus {
            case .syncing:
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundColor(.blue)
                    .font(.caption2)
                    .rotationEffect(.degrees(animateSync ? 360 : 0))
                    .onAppear {
                        withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                            animateSync = true
                        }
                    }
                
            case .synced:
                Image(systemName: "checkmark.icloud.fill")
                    .foregroundColor(.green)
                    .font(.caption2)
                
            case .failed:
                Image(systemName: "exclamationmark.icloud.fill")
                    .foregroundColor(.red)
                    .font(.caption2)
                
            case .pending:
                Image(systemName: "clock.badge.xmark")
                    .foregroundColor(.orange)
                    .font(.caption2)
                
            default:
                if cloudKitSync.iCloudAvailable {
                    Image(systemName: "icloud")
                        .foregroundColor(.gray)
                        .font(.caption2)
                } else {
                    EmptyView()
                }
            }
        }
        .frame(width: 12, height: 12)
    }
}

// MARK: - Primary Device Badge

/// Badge that appears when device is primary
@available(iOS 16.0, macOS 13.0, *)
public struct PrimaryDeviceBadge: View {
    @ObservedObject private var deviceCoordinator: DeviceCoordinator = .shared
    
    public init() {}
    
    public var body: some View {
        Group {
            if deviceCoordinator.isPrimary {
                HStack(spacing: 4) {
                    Image(systemName: "crown.fill")
                        .font(.caption2)
                    Text("PRIMARY")
                        .font(.caption2)
                        .fontWeight(.bold)
                }
                .foregroundColor(.yellow)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.yellow.opacity(0.15))
                .cornerRadius(8)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: deviceCoordinator.isPrimary)
    }
}

// MARK: - Sync Progress Overlay

/// Progress overlay that appears during sync operations
@available(iOS 16.0, macOS 13.0, *)
public struct SyncProgressOverlay: View {
    @ObservedObject private var cloudKitSync: CloudKitSyncManager = .shared
    
    public init() {}
    
    public var body: some View {
        Group {
            if cloudKitSync.syncStatus == .syncing {
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                        .scaleEffect(1.2)
                    
                    VStack(spacing: 4) {
                        Text("Syncing with iCloud")
                            .font(.headline)
                        
                        if cloudKitSync.syncProgress > 0 {
                            Text("\(Int(cloudKitSync.syncProgress * 100))% complete")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            ProgressView(value: cloudKitSync.syncProgress)
                                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                                .frame(width: 200)
                        }
                    }
                }
                .padding(24)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: cloudKitSync.syncStatus)
    }
}

// MARK: - Multi-Device Alert Banner

/// Banner that appears when multiple devices are active
@available(iOS 16.0, macOS 13.0, *)
public struct MultiDeviceAlertBanner: View {
    @ObservedObject private var deviceCoordinator: DeviceCoordinator = .shared
    @State private var showBanner = false
    
    public init() {}
    
    public var body: some View {
        Group {
            if showBanner && !deviceCoordinator.activeDevices.isEmpty && !deviceCoordinator.isPrimary {
                HStack(spacing: 12) {
                    Image(systemName: "person.2.badge.gearshape.fill")
                        .foregroundColor(.blue)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Multiple devices detected")
                            .font(.caption)
                            .fontWeight(.semibold)
                        
                        Text("Another device is primary for sending messages")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Details") {
                        // Show device coordination details
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: showBanner)
        .onReceive(deviceCoordinator.$activeDevices) { devices in
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(1.0)) {
                showBanner = !devices.isEmpty && !deviceCoordinator.isPrimary
            }
        }
        .onReceive(deviceCoordinator.$isPrimary) { isPrimary in
            if isPrimary {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    showBanner = false
                }
            }
        }
    }
}

// MARK: - Sync Error Banner

/// Banner that appears when sync fails
@available(iOS 16.0, macOS 13.0, *)
public struct SyncErrorBanner: View {
    @ObservedObject private var cloudKitSync: CloudKitSyncManager = .shared
    @State private var showError = false
    
    public init() {}
    
    public var body: some View {
        Group {
            if showError && cloudKitSync.syncStatus == .failed {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sync failed")
                            .font(.caption)
                            .fontWeight(.semibold)
                        
                        if let error = cloudKitSync.errorMessage {
                            Text(error)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                    
                    Spacer()
                    
                    Button("Retry") {
                        Task {
                            try? await cloudKitSync.performFullSync()
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.red.opacity(0.1))
                .cornerRadius(12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: showError)
        .onReceive(cloudKitSync.$syncStatus) { status in
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                showError = status == .failed
            }
        }
    }
}

// MARK: - Previews

@available(iOS 16.0, macOS 13.0, *)
#Preview("Device Coordination Indicator") {
    VStack(spacing: 20) {
        DeviceCoordinationIndicator()
        
        HStack {
            MiniSyncStatusIndicator()
            PrimaryDeviceBadge()
        }
        
        MultiDeviceAlertBanner()
        
        SyncErrorBanner()
    }
    .padding()
    .background(Color.gray.opacity(0.1))
}