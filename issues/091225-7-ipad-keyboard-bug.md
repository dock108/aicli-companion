# Issue 121225-4: iPad Keyboard Remains Open with Message Stuck in Input Field

**Priority**: High  
**Component**: iOS App - Message Input & Keyboard Management  
**Beta Blocker**: Yes - Core messaging functionality broken on iPad  
**Discovered**: 2025-09-09  
**Status**: Open  
**Related Test Note**: USER_TEST_NOTES.md - Test Note 9  
**Device Specific**: iPad (all models)

## Problem Description

On iPad, after tapping the send button, the keyboard remains open and the sent message text stays in the input field, even though the message was successfully sent to the backend. This creates confusion about whether the message was sent and often results in duplicate sends.

## Business Impact

- **Duplicate Messages**: Users send the same message multiple times
- **User Confusion**: Unclear if message was actually sent
- **iPad Experience**: Makes iPad version feel broken
- **Professional Use**: iPad often used in professional settings

## Debug & Triage Steps

### 1. Keyboard State Monitoring
```swift
// Add keyboard state logging
extension View {
    func logKeyboardEvents() -> some View {
        self
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                print("⌨️ [KEYBOARD] Will Show - \(Date())")
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                print("⌨️ [KEYBOARD] Did Show - \(Date())")
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                print("⌨️ [KEYBOARD] Will Hide - \(Date())")
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
                print("⌨️ [KEYBOARD] Did Hide - \(Date())")
            }
    }
}
```

### 2. Text Field State Analysis
```swift
// Debug text field behavior
struct MessageInputView: View {
    @State private var messageText: String = ""
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        TextField("Message", text: $messageText)
            .onChange(of: messageText) { newValue in
                print("📝 Text changed: '\(newValue)' Length: \(newValue.count)")
            }
            .onChange(of: isInputFocused) { focused in
                print("🎯 Focus changed: \(focused)")
            }
            .onSubmit {
                print("✉️ OnSubmit triggered")
                sendMessage()
            }
    }
}
```

### 3. iPad-Specific Testing
```bash
# Check for iPad-specific code
grep -r "UIDevice.current.userInterfaceIdiom" ios/Sources/
grep -r "horizontalSizeClass" ios/Sources/
grep -r "iPad" ios/Sources/
```

### 4. Send Flow Tracing
```swift
func sendMessage() {
    print("📤 [SEND] 1. Send button tapped")
    let messageToSend = messageText
    print("📤 [SEND] 2. Message captured: '\(messageToSend)'")
    
    // Clear immediately
    messageText = ""
    print("📤 [SEND] 3. Text field cleared")
    
    // Dismiss keyboard
    isInputFocused = false
    print("📤 [SEND] 4. Focus removed")
    
    // Hide keyboard explicitly
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    print("📤 [SEND] 5. Resign first responder sent")
    
    // Send to backend
    Task {
        print("📤 [SEND] 6. Sending to backend...")
        await networkManager.send(messageToSend)
        print("📤 [SEND] 7. Backend send complete")
    }
}
```

## Root Cause Analysis

### iPad-Specific Issues

1. **Keyboard Dock Mode**
   - iPad keyboard can be docked/undocked
   - Split keyboard mode behaves differently
   - External keyboard changes behavior

2. **Multitasking Interference**
   - Split View affects keyboard management
   - Slide Over may interfere with focus
   - Stage Manager (iPadOS 16+) adds complexity

3. **Focus Management Differences**
   - iPad has different focus behavior than iPhone
   - Multiple focus targets in larger screen

## Recommended Solution

### Immediate Fix

```swift
struct MessageInputView: View {
    @State private var messageText: String = ""
    @FocusState private var isInputFocused: Bool
    @State private var isSending: Bool = false
    
    var body: some View {
        HStack {
            TextField("Message", text: $messageText)
                .focused($isInputFocused)
                .disabled(isSending) // Prevent input during send
                .submitLabel(.send)
                .onSubmit {
                    sendMessage()
                }
            
            Button(action: sendMessage) {
                Image(systemName: "paperplane.fill")
            }
            .disabled(messageText.isEmpty || isSending)
        }
    }
    
    private func sendMessage() {
        guard !messageText.isEmpty, !isSending else { return }
        
        isSending = true
        let message = messageText
        
        // Clear text IMMEDIATELY
        messageText = ""
        
        // Force keyboard dismissal on iPad
        if UIDevice.current.userInterfaceIdiom == .pad {
            // iPad-specific dismissal
            DispatchQueue.main.async {
                isInputFocused = false
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil,
                    from: nil,
                    for: nil
                )
            }
        } else {
            // iPhone dismissal
            isInputFocused = false
        }
        
        // Send message
        Task {
            await sendToBackend(message)
            await MainActor.run {
                isSending = false
            }
        }
    }
}
```

### Comprehensive iPad Solution

```swift
// iPad-aware keyboard manager
class iPadKeyboardManager: ObservableObject {
    @Published var keyboardHeight: CGFloat = 0
    @Published var isKeyboardVisible: Bool = false
    
    init() {
        setupKeyboardObservers()
    }
    
    private func setupKeyboardObservers() {
        // Monitor keyboard frame changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardFrameChanged),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
    }
    
    @objc private func keyboardFrameChanged(_ notification: Notification) {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        
        if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
            // Handle docked, undocked, and split keyboard
            print("⌨️ iPad Keyboard frame: \(keyboardFrame)")
            
            // Force dismiss if needed
            if shouldForceDismiss {
                forceKeyboardDismiss()
            }
        }
    }
    
    func forceKeyboardDismiss() {
        // Multiple approaches to ensure dismissal
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        
        // Backup: End editing on all windows
        UIApplication.shared.windows.forEach { window in
            window.endEditing(true)
        }
    }
}
```

### External Keyboard Support

```swift
// Detect and handle external keyboard
var isExternalKeyboardConnected: Bool {
    #if targetEnvironment(macCatalyst)
    return true
    #else
    // Check if software keyboard is being suppressed
    let isExternalKeyboard = UITextInputMode.activeInputModes.contains { mode in
        mode.responds(to: #selector(getter: UITextInputMode.hardwareLayout))
    }
    return isExternalKeyboard
    #endif
}
```

## Testing Plan

### Device Matrix
- [ ] iPad Pro 12.9" (all generations)
- [ ] iPad Pro 11"
- [ ] iPad Air
- [ ] iPad mini
- [ ] iPad (standard)

### Keyboard Configurations
- [ ] Docked keyboard
- [ ] Undocked keyboard
- [ ] Split keyboard
- [ ] External keyboard (Magic Keyboard, Smart Keyboard)
- [ ] Pencil input with Scribble

### Multitasking Modes
- [ ] Full screen
- [ ] Split View (50/50)
- [ ] Split View (70/30)
- [ ] Slide Over
- [ ] Stage Manager (iPadOS 16+)

## Acceptance Criteria

- [ ] Message text clears immediately on send (iPad)
- [ ] Keyboard dismisses on send (iPad)
- [ ] No duplicate sends due to confusion
- [ ] Works with all keyboard configurations
- [ ] Works in all multitasking modes
- [ ] External keyboard support

## Notes

Consider adding a visual "Message Sent" confirmation specifically for iPad to address the larger screen's different UX expectations.

---
**Last Updated**: 2025-09-12