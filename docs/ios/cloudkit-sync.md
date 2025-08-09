# CloudKit Cross-Device Sync

## Overview

AICLI Companion now supports cross-device synchronization of conversations using Apple CloudKit. This allows users to seamlessly continue their Claude conversations across all their Apple devices (iPhone, iPad, Mac).

## Architecture

### Key Components

1. **CloudKitSyncManager** (`ios/Sources/AICLICompanion/Services/CloudKit/CloudKitSyncManager.swift`)
   - Singleton service managing all CloudKit operations
   - Handles iCloud availability checks
   - Manages message sync operations
   - Provides sync status updates

2. **CloudKit Schema** (`ios/Sources/AICLICompanion/Models/CloudKit/CloudKitSchema.swift`)
   - Defines CloudKit record types (Message, Session, SyncMetadata)
   - Centralizes field keys for consistency

3. **Message Extensions** (`ios/Sources/AICLICompanion/Message.swift`)
   - Added CloudKit-specific properties (excluded from Codable)
   - Conversion methods between Message and CKRecord

4. **SyncStatusView** (`ios/Sources/AICLICompanion/Views/SyncStatusView.swift`)
   - Visual indicator of sync status
   - Shows last sync time
   - Displays sync errors if any

### Data Flow

1. **Local First**: Messages are always saved locally first
2. **Background Sync**: CloudKit sync happens asynchronously in background
3. **Automatic Sync**: Syncs on app launch, project switch, and app activation
4. **Manual Sync**: Users can trigger sync via the SyncStatusView

### Sync Strategy

- **Soft Delete**: Messages marked as deleted per device, not removed from CloudKit
- **Last-Write-Wins**: Conflict resolution based on timestamp
- **Per-Device Tracking**: Tracks which devices have read/deleted messages
- **Offline Support**: Queues sync operations when offline

## Setup Requirements

### For Developers

1. **Enable CloudKit Capability**:
   - Open Xcode project
   - Select iOS app target
   - Go to "Signing & Capabilities"
   - Add "iCloud" capability
   - Check "CloudKit"

2. **Entitlements Configuration**:
   The `ios/App/AICLICompanion.entitlements` file must include:
   ```xml
   <key>com.apple.developer.icloud-container-identifiers</key>
   <array>
       <string>iCloud.com.aicli.companion</string>
   </array>
   <key>com.apple.developer.icloud-services</key>
   <array>
       <string>CloudKit</string>
   </array>
   ```

3. **Container Configuration**:
   - Container ID: `iCloud.com.aicli.companion`
   - Automatically created when capability is added

4. **CloudKit Dashboard Setup**:
   - Go to https://icloud.developer.apple.com
   - Sign in with Apple Developer account
   - Select container
   - Create indexes for Message record type:
     - `timestamp` (SORTABLE)
     - `projectPath` (QUERYABLE)
     - `sessionId` (QUERYABLE)

### For Users

1. **iCloud Sign-In**: Must be signed into iCloud on device
2. **iCloud Drive**: Must have iCloud Drive enabled
3. **Network**: Requires internet connection for sync

## Implementation Details

### Message Sync Properties

```swift
struct Message {
    // CloudKit properties (excluded from Codable)
    var cloudKitRecordID: CKRecord.ID?
    var readByDevices: [String] = []
    var deletedByDevices: [String] = []
    var syncedAt: Date?
    var needsSync: Bool = true
}
```

### Sync Triggers

1. **User Message Send**: Syncs immediately after local save
2. **Assistant Response**: Syncs when response received
3. **App Launch**: Fetches messages from CloudKit
4. **App Activation**: Syncs when returning from background
5. **Project Switch**: Syncs messages for new project

### Error Handling

- **iCloud Not Available**: Shows warning in UI
- **Sync Failures**: Logged but don't block local operations
- **Network Issues**: Queues for retry when connected

## Testing

### Simulator Testing

1. Sign into iCloud in simulator Settings
2. Send test messages
3. Check Console for sync logs
4. Verify in CloudKit Dashboard

### Device Testing

1. Install on multiple devices
2. Sign into same iCloud account
3. Send messages on Device A
4. Verify sync on Device B

### Offline Testing

1. Enable Airplane Mode
2. Send messages (saved locally)
3. Disable Airplane Mode
4. Verify sync completes

## Troubleshooting

### Messages Not Syncing

1. **Check iCloud Status**:
   - Settings > [Your Name] > iCloud
   - Ensure iCloud Drive is enabled

2. **Verify Container**:
   - Check CloudKit Dashboard
   - Confirm records are being created

3. **Review Logs**:
   - Look for CloudKit errors in Console
   - Check sync status in app UI

### Sync Conflicts

- Last-write-wins strategy automatically resolves conflicts
- Messages sorted by timestamp maintain order
- Duplicate detection prevents message duplication

## Performance Considerations

- **Batch Size**: Limited to 100 messages per fetch
- **Sync Frequency**: On-demand, not continuous
- **Data Usage**: Minimal - only text messages synced
- **Battery Impact**: Negligible due to on-demand sync

## Privacy & Security

- **Private Database**: All data stored in user's private CloudKit database
- **End-to-End**: Apple handles encryption in transit and at rest
- **User Control**: User can disable iCloud sync in Settings
- **Data Ownership**: User owns all their CloudKit data

## Future Enhancements

- [ ] Selective sync (last 30 days only)
- [ ] Conversation sharing via CloudKit
- [ ] Backup/restore functionality
- [ ] Sync throttling for large conversations
- [ ] Push notifications for new messages

## Rollback Instructions

If CloudKit sync causes issues:

1. **Disable in Code**:
   ```swift
   // In CloudKitSyncManager.init()
   self.iCloudAvailable = false
   ```

2. **Remove Capability**:
   - Xcode > Signing & Capabilities
   - Remove iCloud capability

3. **Clean Build**:
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData
   ```

## References

- [Apple CloudKit Documentation](https://developer.apple.com/documentation/cloudkit)
- [CloudKit Dashboard](https://icloud.developer.apple.com)
- [CloudKit Best Practices](https://developer.apple.com/videos/play/wwdc2021/10015/)