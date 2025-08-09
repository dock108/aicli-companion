import SwiftUI

@available(iOS 16.0, macOS 13.0, *)
struct SyncStatusView: View {
    @StateObject private var syncManager = CloudKitSyncManager.shared
    @State private var showDetails = false
    
    var body: some View {
        HStack(spacing: 8) {
            switch syncManager.syncStatus {
            case .idle:
                if syncManager.iCloudAvailable {
                    Image(systemName: "icloud")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    if let lastSync = syncManager.lastSyncDate {
                        Text("Synced \(lastSync, style: .relative)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    EmptyView()
                }
                
            case .checking:
                ProgressView()
                    .scaleEffect(0.8)
                Text("Checking...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
            case .syncing(let progress):
                ProgressView(value: progress)
                    .progressViewStyle(LinearProgressViewStyle())
                    .frame(width: 60)
                Text("Syncing...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
                if let lastSync = syncManager.lastSyncDate {
                    Text("Synced \(lastSync, style: .relative)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
            case .error(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.caption)
                Text(message)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundColor(.orange)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        #if os(iOS)
        .background(Color(UIColor.secondarySystemBackground))
        #else
        .background(Color(NSColor.controlBackgroundColor))
        #endif
        .cornerRadius(8)
        .animation(.easeInOut, value: syncManager.syncStatus)
        .onTapGesture {
            showDetails.toggle()
        }
        .popover(isPresented: $showDetails) {
            SyncDetailsView()
                #if os(iOS)
                .frame(minWidth: 300, minHeight: 200)
                #else
                .frame(width: 350, height: 250)
                #endif
        }
    }
}

@available(iOS 16.0, macOS 13.0, *)
struct SyncDetailsView: View {
    @StateObject private var syncManager = CloudKitSyncManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("CloudKit Sync Status")
                .font(.headline)
                .padding(.bottom, 4)
            
            // iCloud Status
            HStack {
                Image(systemName: syncManager.iCloudAvailable ? "icloud.fill" : "icloud.slash.fill")
                    .foregroundColor(syncManager.iCloudAvailable ? .green : .red)
                Text(syncManager.iCloudAvailable ? "iCloud Available" : "iCloud Not Available")
                    .font(.subheadline)
            }
            
            // Last Sync Time
            if let lastSync = syncManager.lastSyncDate {
                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(.secondary)
                    Text("Last synced \(lastSync, formatter: relativeDateFormatter)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            // Sync Errors
            if !syncManager.syncErrors.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recent Errors:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    ForEach(syncManager.syncErrors.prefix(3), id: \.self) { error in
                        Text("• \(error.localizedDescription)")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            
            Spacer()
            
            // Manual Sync Button
            Button(action: {
                Task {
                    await syncManager.performFullSync()
                }
            }) {
                Label("Sync Now", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!syncManager.iCloudAvailable || syncManager.syncStatus != .idle)
        }
        .padding()
    }
    
    private var relativeDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }
}

@available(iOS 16.0, macOS 13.0, *)
struct SyncStatusView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            SyncStatusView()
            
            SyncDetailsView()
                .frame(width: 350, height: 250)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
        }
        .padding()
    }
}
