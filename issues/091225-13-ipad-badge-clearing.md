# Issue 121225-10: Badge Counts Don't Clear Properly on iPad

**Priority**: Medium  
**Component**: iOS App - Notification Badge Management  
**Beta Blocker**: No - But affects user experience  
**Discovered**: 2025-09-12  
**Status**: Open  
**Related Test Note**: USER_TEST_NOTES.md - Test Note 17  
**Device Specific**: iPad only

## Problem Description

Badge counts (notification indicators) don't clear properly on iPad, remaining visible after viewing messages. This appears to be iPad-specific and may relate to multitasking behaviors.

## Business Impact

- **User Confusion**: Incorrect unread counts mislead users
- **Unnecessary Checking**: Users recheck already-read messages
- **Professional Image**: Makes app appear buggy
- **iPad Experience**: Degrades iPad-specific experience

## Debug & Triage Steps

### 1. Badge Update Logging
```swift
// Comprehensive badge tracking
class BadgeManager {
    static func updateBadge(to count: Int, source: String) {
        print("🔴 [BADGE] Update requested: \(count) from \(source)")
        
        // Update app icon badge
        UNUserNotificationCenter.current().setBadgeCount(count) { error in
            if let error = error {
                print("❌ [BADGE] Failed to set badge: \(error)")
            } else {
                print("✅ [BADGE] Badge set to \(count)")
            }
        }
        
        // Verify update
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            verifyBadgeCount(expected: count)
        }
    }
    
    static func verifyBadgeCount(expected: Int) {
        let actual = UIApplication.shared.applicationIconBadgeNumber
        if actual != expected {
            print("⚠️ [BADGE] Mismatch! Expected: \(expected), Actual: \(actual)")
        }
    }
}
```

### 2. iPad Multitasking State Detection
```swift
// Monitor iPad-specific states
class iPadStateMonitor {
    func monitorMultitaskingState() {
        if UIDevice.current.userInterfaceIdiom == .pad {
            // Check if in split view
            if let window = UIApplication.shared.windows.first {
                let isFullScreen = window.frame == UIScreen.main.bounds
                let isCompact = window.traitCollection.horizontalSizeClass == .compact
                
                print("📱 [iPad] Full Screen: \(isFullScreen), Compact: \(isCompact)")
            }
            
            // Monitor scene state
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                print("📱 [iPad] Scene State: \(scene.activationState.rawValue)")
            }
        }
    }
}
```

### 3. Badge Clear Timing Analysis
```swift
// Track when badges should clear
extension ChatView {
    func onChatOpened() {
        let timestamp = Date()
        print("💬 [BADGE] Chat opened at \(timestamp)")
        
        // Mark messages as read
        markMessagesAsRead()
        
        // Clear badge with delay for iPad
        if UIDevice.current.userInterfaceIdiom == .pad {
            // iPad needs longer delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                updateBadgeCount()
            }
        } else {
            updateBadgeCount()
        }
    }
    
    func updateBadgeCount() {
        let unreadCount = calculateUnreadCount()
        print("🔴 [BADGE] Updating to \(unreadCount) unread")
        
        BadgeManager.updateBadge(to: unreadCount, source: "ChatView")
    }
}
```

## Root Cause Analysis

### iPad-Specific Issues

1. **Scene Lifecycle Differences**
   - iPad apps can have multiple scenes
   - Split View affects lifecycle events
   - Background refresh timing differs

2. **Notification Center Behavior**
   - iPad groups notifications differently
   - Notification Center may cache badge count
   - Clear commands may be delayed/ignored

3. **Multitasking Interference**
   - Slide Over maintains separate state
   - Split View may not trigger badge updates
   - Stage Manager adds complexity

## Recommended Solution

### 1. iPad-Aware Badge Manager

```swift
class iPadBadgeManager: ObservableObject {
    @Published var appBadgeCount: Int = 0
    @Published var chatBadgeCounts: [String: Int] = [:]
    
    private var updateTimer: Timer?
    private let updateQueue = DispatchQueue(label: "badge.update", qos: .userInitiated)
    
    func clearBadge(for chatId: String) {
        updateQueue.async { [weak self] in
            self?.chatBadgeCounts[chatId] = 0
            self?.scheduleUpdate()
        }
    }
    
    func setBadge(_ count: Int, for chatId: String) {
        updateQueue.async { [weak self] in
            self?.chatBadgeCounts[chatId] = count
            self?.scheduleUpdate()
        }
    }
    
    private func scheduleUpdate() {
        // Debounce updates on iPad
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.performUpdate()
        }
    }
    
    private func performUpdate() {
        let totalUnread = chatBadgeCounts.values.reduce(0, +)
        
        DispatchQueue.main.async { [weak self] in
            self?.appBadgeCount = totalUnread
            
            // Multiple update attempts for iPad
            if UIDevice.current.userInterfaceIdiom == .pad {
                self?.updateWithRetry(count: totalUnread, attempts: 3)
            } else {
                self?.updateBadgeOnce(count: totalUnread)
            }
        }
    }
    
    private func updateWithRetry(count: Int, attempts: Int) {
        updateBadgeOnce(count: count)
        
        if attempts > 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.updateWithRetry(count: count, attempts: attempts - 1)
            }
        }
    }
    
    private func updateBadgeOnce(count: Int) {
        // Method 1: UNUserNotificationCenter
        UNUserNotificationCenter.current().setBadgeCount(count)
        
        // Method 2: Legacy API (backup)
        UIApplication.shared.applicationIconBadgeNumber = count
        
        // Method 3: Force notification center refresh
        if count == 0 {
            UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        }
    }
}
```

### 2. Scene-Aware Badge Updates

```swift
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    func sceneDidBecomeActive(_ scene: UIScene) {
        print("🎬 [SCENE] Became active")
        BadgeRefreshCoordinator.shared.refreshBadges()
    }
    
    func sceneWillResignActive(_ scene: UIScene) {
        print("🎬 [SCENE] Will resign active")
        BadgeRefreshCoordinator.shared.forceBadgeUpdate()
    }
    
    func sceneDidEnterBackground(_ scene: UIScene) {
        print("🎬 [SCENE] Entered background")
        BadgeRefreshCoordinator.shared.persistBadgeState()
    }
}
```

### 3. Manual Badge Refresh Option

```swift
struct SettingsView: View {
    @StateObject private var badgeManager = iPadBadgeManager.shared
    
    var body: some View {
        Form {
            Section("Notifications") {
                HStack {
                    Text("Badge Count")
                    Spacer()
                    Text("\(badgeManager.appBadgeCount)")
                        .foregroundColor(.secondary)
                }
                
                Button("Clear All Badges") {
                    clearAllBadges()
                }
                
                Button("Refresh Badge Count") {
                    refreshBadgeCount()
                }
                
                if UIDevice.current.userInterfaceIdiom == .pad {
                    Toggle("Force Badge Updates", isOn: $forceBadgeUpdates)
                        .onChange(of: forceBadgeUpdates) { enabled in
                            UserDefaults.standard.set(enabled, forKey: "forceBadgeUpdates")
                        }
                }
            }
        }
    }
    
    private func clearAllBadges() {
        badgeManager.clearAll()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UIApplication.shared.applicationIconBadgeNumber = 0
    }
}
```

### 4. CloudKit Badge Sync

```swift
// Sync badge state across devices
class CloudKitBadgeSync {
    func syncBadgeCount(_ count: Int) {
        let record = CKRecord(recordType: "BadgeState")
        record["deviceId"] = UIDevice.current.identifierForVendor?.uuidString
        record["badgeCount"] = count
        record["timestamp"] = Date()
        record["deviceType"] = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        
        CKContainer.default().privateCloudDatabase.save(record) { _, error in
            if let error = error {
                print("❌ [BADGE] CloudKit sync failed: \(error)")
            }
        }
    }
    
    func fetchRemoteBadgeState() {
        let predicate = NSPredicate(format: "deviceId != %@", 
                                   UIDevice.current.identifierForVendor?.uuidString ?? "")
        let query = CKQuery(recordType: "BadgeState", predicate: predicate)
        
        CKContainer.default().privateCloudDatabase.perform(query) { records, error in
            // Compare and reconcile badge states
        }
    }
}
```

## Testing Plan

### iPad Configurations
- [ ] iPad Pro 12.9" - Full screen
- [ ] iPad Pro 11" - Split View (50/50)
- [ ] iPad Air - Split View (30/70)
- [ ] iPad mini - Slide Over
- [ ] iPad with Stage Manager

### Scenarios
- [ ] Open chat → Badge clears
- [ ] Switch between chats → Badges update
- [ ] Background → Foreground → Badge persists
- [ ] Split View → Badge updates correctly
- [ ] Multiple scenes → Independent badges

### Verification Methods
- [ ] Visual badge count matches expected
- [ ] Settings shows correct count
- [ ] Notification Center reflects badge
- [ ] Force refresh works

## Acceptance Criteria

- [ ] Badges clear when viewing messages
- [ ] Badges persist correctly across app states
- [ ] Manual refresh option available
- [ ] Works in all iPad multitasking modes
- [ ] No badge count drift over time

## Workaround for Users

Until fixed, users can:
1. Force-quit and reopen app
2. Use Settings → Clear All Badges
3. Pull down Notification Center to refresh

## Notes

Consider implementing a badge diagnostic mode that logs all badge operations for debugging user issues.

---
**Last Updated**: 2025-09-12