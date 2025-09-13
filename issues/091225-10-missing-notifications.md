# Issue 121225-7: Suspected Missing Push Notifications (APNS)

**Priority**: Medium (Under Investigation)  
**Component**: Server & iOS App - Push Notification Delivery  
**Beta Blocker**: Potentially - If confirmed  
**Discovered**: 2025-09-10  
**Status**: Under Observation  
**Related Test Note**: USER_TEST_NOTES.md - Test Note 14

## Problem Description

There is suspicion that not all push notifications are being delivered, particularly when a message arrives while the user is actively in another chat. The issue is not confirmed but needs investigation.

## Business Impact

- **Message Awareness**: Users may miss important responses
- **Trust**: Users lose confidence in notification reliability
- **Engagement**: Reduced app engagement without notifications
- **Support**: Hard to diagnose user complaints

## Observed Patterns

1. **Active Chat Scenario**
   - User in Chat A
   - Message arrives for Chat B
   - No notification appears for Chat B

2. **Notification Coalescing**
   - Multiple messages arrive quickly
   - Only one notification shown
   - Others appear to be lost

## Debug & Triage Steps

### 1. Notification Logging System

```javascript
// Server-side notification tracking
class NotificationTracker {
    constructor() {
        this.sentNotifications = new Map();
    }
    
    async sendNotification(deviceToken, payload) {
        const notificationId = uuid.v4();
        const timestamp = Date.now();
        
        // Log before sending
        this.sentNotifications.set(notificationId, {
            deviceToken,
            payload,
            timestamp,
            status: 'pending'
        });
        
        try {
            const result = await apnProvider.send(notification, deviceToken);
            
            // Log success/failure
            this.sentNotifications.get(notificationId).status = result.failed.length > 0 ? 'failed' : 'sent';
            this.sentNotifications.get(notificationId).apnsId = result.sent[0]?.id;
            
            console.log(`📱 [APNS] Notification ${notificationId}: ${result.failed.length > 0 ? '❌ Failed' : '✅ Sent'}`);
            
            return { notificationId, result };
        } catch (error) {
            this.sentNotifications.get(notificationId).status = 'error';
            this.sentNotifications.get(notificationId).error = error.message;
            throw error;
        }
    }
    
    getNotificationHistory(deviceToken, hours = 24) {
        const cutoff = Date.now() - (hours * 60 * 60 * 1000);
        return Array.from(this.sentNotifications.values())
            .filter(n => n.deviceToken === deviceToken && n.timestamp > cutoff)
            .sort((a, b) => b.timestamp - a.timestamp);
    }
}
```

### 2. iOS Notification Reception Tracking

```swift
class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    private var receivedNotifications: [NotificationRecord] = []
    
    struct NotificationRecord {
        let id: String
        let timestamp: Date
        let chatId: String?
        let displayed: Bool
        let appState: UIApplication.State
    }
    
    // Track all incoming notifications
    func userNotificationCenter(_ center: UNUserNotificationCenter, 
                               willPresent notification: UNNotification,
                               withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        
        let record = NotificationRecord(
            id: notification.request.identifier,
            timestamp: Date(),
            chatId: notification.request.content.userInfo["chatId"] as? String,
            displayed: true,
            appState: UIApplication.shared.applicationState
        )
        
        receivedNotifications.append(record)
        print("📱 [NOTIFICATION] Received: \(record.id), State: \(record.appState)")
        
        // Determine if should show
        let shouldShow = shouldDisplayNotification(for: record)
        
        if shouldShow {
            completionHandler([.banner, .sound, .badge])
        } else {
            print("⚠️ [NOTIFICATION] Suppressed: \(record.id)")
            completionHandler([])
        }
    }
    
    private func shouldDisplayNotification(for record: NotificationRecord) -> Bool {
        // Check if user is in different chat
        if let notificationChatId = record.chatId,
           let currentChatId = ChatViewModel.shared.currentChatId,
           notificationChatId == currentChatId {
            // User is already in this chat, don't show notification
            return false
        }
        
        return true
    }
    
    // Diagnostic method
    func compareWithServer() async {
        let serverNotifications = await fetchServerNotificationLog()
        let clientNotifications = Set(receivedNotifications.map { $0.id })
        
        let missing = serverNotifications.filter { !clientNotifications.contains($0.id) }
        
        if !missing.isEmpty {
            print("⚠️ [NOTIFICATION] Missing \(missing.count) notifications:")
            missing.forEach { print("  - \($0)") }
        }
    }
}
```

### 3. APNS Delivery Verification

```javascript
// Server endpoint to verify notification delivery
app.get('/api/notifications/verify/:deviceToken', async (req, res) => {
    const { deviceToken } = req.params;
    const { hours = 24 } = req.query;
    
    // Get server send history
    const sentHistory = notificationTracker.getNotificationHistory(deviceToken, hours);
    
    // Get APNS feedback (if available)
    const apnsFeedback = await checkAPNSFeedback(deviceToken);
    
    res.json({
        sent: sentHistory.length,
        delivered: sentHistory.filter(n => n.status === 'sent').length,
        failed: sentHistory.filter(n => n.status === 'failed').length,
        errors: sentHistory.filter(n => n.status === 'error'),
        apnsFeedback
    });
});
```

### 4. Notification Identifier Analysis

```swift
// Check for notification replacement
extension UNUserNotificationCenter {
    func checkForReplacedNotifications() {
        getPendingNotificationRequests { requests in
            let identifiers = requests.map { $0.identifier }
            let duplicates = identifiers.filter { id in
                identifiers.filter { $0 == id }.count > 1
            }
            
            if !duplicates.isEmpty {
                print("⚠️ [NOTIFICATION] Duplicate identifiers found: \(duplicates)")
            }
        }
        
        getDeliveredNotifications { notifications in
            // Check if notifications are being replaced
            let grouped = Dictionary(grouping: notifications) { $0.request.identifier }
            grouped.forEach { (id, notifs) in
                if notifs.count > 1 {
                    print("⚠️ [NOTIFICATION] Multiple notifications with same ID: \(id)")
                }
            }
        }
    }
}
```

## Root Cause Hypotheses

### 1. Notification Coalescing
```javascript
// Problem: Using same identifier
const notification = new apn.Notification({
    id: chatId, // ❌ Same ID for all messages in chat
    // Should be:
    id: `${chatId}-${messageId}`, // ✅ Unique per message
});
```

### 2. Foreground Suppression
```swift
// Problem: Suppressing all notifications when app is active
if UIApplication.shared.applicationState == .active {
    completionHandler([]) // ❌ Suppresses all
}
// Should check if user is in different chat
```

### 3. Rate Limiting
- APNS may throttle rapid notifications
- Need to implement notification batching

## Recommended Solution

### 1. Unique Notification IDs
```javascript
function createNotification(chatId, messageId, content) {
    return new apn.Notification({
        id: `${chatId}-${messageId}-${Date.now()}`, // Guaranteed unique
        threadId: chatId, // Groups in notification center
        alert: content,
        badge: await getUnreadCount(deviceToken),
        sound: 'default',
        contentAvailable: true,
        mutableContent: true
    });
}
```

### 2. Smart Foreground Handling
```swift
func shouldShowNotification(for chatId: String) -> Bool {
    guard UIApplication.shared.applicationState == .active else {
        return true // Always show when not active
    }
    
    // Check if user is in different chat
    if let currentChat = currentChatId {
        return currentChat != chatId
    }
    
    return true
}
```

### 3. Notification Debugging View
```swift
struct NotificationDebugView: View {
    @StateObject private var debugger = NotificationDebugger()
    
    var body: some View {
        List {
            Section("Statistics") {
                LabeledContent("Sent (Server)", "\(debugger.serverSent)")
                LabeledContent("Received (Client)", "\(debugger.clientReceived)")
                LabeledContent("Displayed", "\(debugger.displayed)")
                LabeledContent("Suppressed", "\(debugger.suppressed)")
                LabeledContent("Missing", "\(debugger.missing)")
            }
            
            Section("Recent Notifications") {
                ForEach(debugger.recentNotifications) { notification in
                    NotificationRow(notification: notification)
                }
            }
        }
    }
}
```

## Testing Plan

### Scenarios to Test
1. **Rapid Messages**
   - Send 10 messages within 1 second
   - Verify all notifications received

2. **Active Chat**
   - Open Chat A
   - Send message to Chat B
   - Verify notification appears

3. **Background/Foreground**
   - Test with app in different states
   - Verify correct behavior in each

4. **Network Conditions**
   - Test on WiFi/Cellular
   - Test with poor connectivity

## Monitoring Implementation

```javascript
// Add monitoring endpoint
app.get('/api/notifications/stats', async (req, res) => {
    const stats = {
        last24Hours: {
            sent: await getNotificationCount('sent', 24),
            delivered: await getNotificationCount('delivered', 24),
            failed: await getNotificationCount('failed', 24),
            complaints: await getComplaintCount(24)
        },
        byHour: await getHourlyStats(),
        failureReasons: await getFailureReasons()
    };
    
    res.json(stats);
});
```

## Acceptance Criteria

- [ ] All sent notifications are logged
- [ ] Client tracks received notifications
- [ ] Comparison tool shows missing notifications
- [ ] Unique ID per notification
- [ ] Smart foreground handling implemented
- [ ] Debug view available in development
- [ ] Monitoring dashboard available

## Notes

Until confirmed as an actual issue, keep monitoring in place but don't make major architectural changes. Focus on logging and observation first.

---
**Last Updated**: 2025-09-12