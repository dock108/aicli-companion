# Issue 121225-9: Unsent Messages Lost When Navigating Away

**Priority**: High  
**Component**: iOS App - Message Drafts & State Persistence  
**Beta Blocker**: Yes - Data loss issue  
**Discovered**: 2025-09-12  
**Status**: Open  
**Related Test Note**: USER_TEST_NOTES.md - Test Note 16

## Problem Description

When users type a message and navigate away before sending (to another chat or different view), the typed message is completely lost with no warning or draft saving.

## Business Impact

- **Data Loss**: Users lose potentially complex messages
- **User Frustration**: Must recreate lost thoughts
- **Productivity**: Time wasted retyping messages
- **Trust**: App appears unreliable

## Severity Factors

- Affects technical users writing detailed queries
- No warning before data loss
- No recovery mechanism
- Common user behavior (checking other chats)

## Debug & Triage Steps

### 1. Text Field State Tracking
```swift
// Monitor text field lifecycle
struct MessageInputView: View {
    @State private var messageText: String = ""
    
    var body: some View {
        TextField("Message", text: $messageText)
            .onChange(of: messageText) { newValue in
                print("📝 [DRAFT] Text changed: \(newValue.count) chars")
                saveDraft(newValue)
            }
            .onAppear {
                print("📝 [DRAFT] Input appeared, loading draft...")
                messageText = loadDraft() ?? ""
            }
            .onDisappear {
                print("📝 [DRAFT] Input disappearing with text: '\(messageText)'")
                if !messageText.isEmpty {
                    saveDraft(messageText)
                }
            }
    }
}
```

### 2. Navigation Interception
```swift
// Detect navigation away with unsent text
struct ChatView: View {
    @State private var showingNavigationWarning = false
    @State private var pendingNavigation: NavigationDestination?
    
    var body: some View {
        NavigationView {
            // Chat content
        }
        .onNavigationAttempt { destination in
            if hasUnsentMessage() {
                pendingNavigation = destination
                showingNavigationWarning = true
                return false // Prevent navigation
            }
            return true // Allow navigation
        }
        .alert("Unsent Message", isPresented: $showingNavigationWarning) {
            Button("Save Draft") {
                saveDraft()
                navigate(to: pendingNavigation)
            }
            Button("Discard") {
                discardDraft()
                navigate(to: pendingNavigation)
            }
            Button("Cancel", role: .cancel) {
                pendingNavigation = nil
            }
        } message: {
            Text("You have an unsent message. What would you like to do?")
        }
    }
}
```

## Root Cause Analysis

### Current Issues

1. **No Draft Persistence**
   - Text field state is local to view
   - Destroyed on navigation

2. **No Warning System**
   - Navigation happens immediately
   - No check for unsent content

3. **No Recovery Mechanism**
   - Once lost, cannot recover
   - No draft history

## Recommended Solution

### 1. Automatic Draft System

```swift
// Draft manager for all chats
class DraftManager: ObservableObject {
    private let userDefaults = UserDefaults.standard
    private let draftPrefix = "draft_"
    
    @Published var drafts: [String: String] = [:]
    
    init() {
        loadAllDrafts()
        setupAutoSave()
    }
    
    func saveDraft(for chatId: String, text: String) {
        if text.isEmpty {
            removeDraft(for: chatId)
        } else {
            drafts[chatId] = text
            userDefaults.set(text, forKey: "\(draftPrefix)\(chatId)")
            
            // Add metadata
            userDefaults.set(Date(), forKey: "\(draftPrefix)\(chatId)_date")
        }
    }
    
    func loadDraft(for chatId: String) -> String? {
        return drafts[chatId] ?? userDefaults.string(forKey: "\(draftPrefix)\(chatId)")
    }
    
    func removeDraft(for chatId: String) {
        drafts.removeValue(forKey: chatId)
        userDefaults.removeObject(forKey: "\(draftPrefix)\(chatId)")
        userDefaults.removeObject(forKey: "\(draftPrefix)\(chatId)_date")
    }
    
    func hasDraft(for chatId: String) -> Bool {
        return loadDraft(for: chatId) != nil
    }
    
    private func loadAllDrafts() {
        let keys = userDefaults.dictionaryRepresentation().keys
        for key in keys where key.hasPrefix(draftPrefix) && !key.contains("_date") {
            let chatId = String(key.dropFirst(draftPrefix.count))
            if let draft = userDefaults.string(forKey: key) {
                drafts[chatId] = draft
            }
        }
    }
    
    private func setupAutoSave() {
        // Auto-save drafts every 5 seconds
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            self.persistAllDrafts()
        }
    }
    
    private func persistAllDrafts() {
        for (chatId, text) in drafts {
            userDefaults.set(text, forKey: "\(draftPrefix)\(chatId)")
        }
    }
}
```

### 2. Draft-Aware Message Input

```swift
struct DraftAwareMessageInput: View {
    let chatId: String
    @StateObject private var draftManager = DraftManager.shared
    @State private var messageText: String = ""
    @State private var lastSavedText: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Draft indicator
            if draftManager.hasDraft(for: chatId) {
                HStack {
                    Image(systemName: "doc.text")
                        .foregroundColor(.secondary)
                    Text("Draft")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Clear") {
                        clearDraft()
                    }
                    .font(.caption)
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1))
            }
            
            // Message input
            HStack {
                TextField("Message", text: $messageText)
                    .onChange(of: messageText) { newValue in
                        debouncedSaveDraft(newValue)
                    }
                    .onAppear {
                        loadDraft()
                    }
                
                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                }
                .disabled(messageText.isEmpty)
            }
            .padding()
        }
    }
    
    private func loadDraft() {
        if let draft = draftManager.loadDraft(for: chatId) {
            messageText = draft
            lastSavedText = draft
        }
    }
    
    private func debouncedSaveDraft(_ text: String) {
        NSObject.cancelPreviousPerformRequests(withTarget: self)
        perform(#selector(saveDraftDelayed), with: text, afterDelay: 0.5)
    }
    
    @objc private func saveDraftDelayed(_ text: String) {
        if text != lastSavedText {
            draftManager.saveDraft(for: chatId, text: text)
            lastSavedText = text
        }
    }
    
    private func sendMessage() {
        // Send message
        sendToBackend(messageText)
        
        // Clear draft
        messageText = ""
        draftManager.removeDraft(for: chatId)
    }
    
    private func clearDraft() {
        messageText = ""
        draftManager.removeDraft(for: chatId)
    }
}
```

### 3. Navigation Warning System

```swift
struct NavigationInterceptor: ViewModifier {
    @Binding var hasUnsavedChanges: Bool
    let onSave: () -> Void
    let onDiscard: () -> Void
    
    @State private var showingAlert = false
    @State private var pendingAction: (() -> Void)?
    
    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(hasUnsavedChanges)
            .toolbar {
                if hasUnsavedChanges {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Back") {
                            showingAlert = true
                        }
                    }
                }
            }
            .alert("Unsaved Message", isPresented: $showingAlert) {
                Button("Save Draft") {
                    onSave()
                    pendingAction?()
                }
                Button("Discard", role: .destructive) {
                    onDiscard()
                    pendingAction?()
                }
                Button("Continue Editing", role: .cancel) {}
            } message: {
                Text("You have an unsaved message. What would you like to do?")
            }
    }
}
```

### 4. Visual Draft Indicators

```swift
struct ChatRow: View {
    let chat: Chat
    @ObservedObject var draftManager = DraftManager.shared
    
    var body: some View {
        HStack {
            // Chat info
            VStack(alignment: .leading) {
                Text(chat.title)
                    .font(.headline)
                
                if let draft = draftManager.loadDraft(for: chat.id) {
                    HStack {
                        Image(systemName: "doc.text")
                            .font(.caption2)
                        Text("Draft: \(draft.prefix(30))...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    Text(chat.lastMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Draft indicator badge
            if draftManager.hasDraft(for: chat.id) {
                Image(systemName: "doc.text.fill")
                    .foregroundColor(.blue)
                    .font(.caption)
            }
        }
    }
}
```

## Testing Plan

### Draft Persistence
- [ ] Draft saves automatically while typing
- [ ] Draft persists when navigating away
- [ ] Draft reloads when returning to chat
- [ ] Draft clears after sending message

### Navigation Warnings
- [ ] Warning appears with unsent text
- [ ] Can save draft from warning
- [ ] Can discard draft from warning
- [ ] Can cancel navigation

### Visual Indicators
- [ ] Draft badge shows in chat list
- [ ] Draft preview in chat row
- [ ] Draft indicator in input area

### Edge Cases
- [ ] Very long drafts (>5000 chars)
- [ ] Multiple drafts across chats
- [ ] Draft with attachments
- [ ] Draft persistence across app restarts

## Acceptance Criteria

- [ ] Drafts automatically save while typing
- [ ] Drafts persist across navigation
- [ ] Warning before losing unsent message
- [ ] Visual indicators for existing drafts
- [ ] Drafts clear after sending
- [ ] Works on iPhone and iPad

## Notes

Consider implementing draft expiry (e.g., auto-clear drafts older than 30 days) to prevent indefinite storage growth.

---
**Last Updated**: 2025-09-12