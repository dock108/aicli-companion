# Issue 121225-2: Chat Thread UI Instability with Long Messages

**Priority**: High  
**Component**: iOS App - Chat View UI  
**Beta Blocker**: Yes - Core functionality affected  
**Discovered**: 2025-09-06  
**Status**: Open  
**Related Test Note**: USER_TEST_NOTES.md - Test Note 7  
**Related Issues**: #121225-3 (App Reload) - May compound message loss

## Problem Description

When users send long messages, the chat thread UI exhibits severe instability including flashing content, disappearing/reappearing messages, and rapid unwanted scrolling. This creates a disorienting experience that makes the app feel broken.

## Business Impact

- **User Experience**: Core chat functionality appears broken
- **Data Integrity Concern**: Users worry messages aren't being sent properly
- **Productivity Loss**: Users lose their place in conversations
- **Trust**: Unstable UI reduces confidence in the app

## Symptoms

1. **Visual Glitches**
   - Chat content flashes white/blank
   - Messages temporarily disappear then reappear
   - UI elements jump around

2. **Scrolling Issues**
   - Rapid automatic scrolling up and down
   - Unable to maintain scroll position
   - Scroll position jumps while typing

3. **Performance**
   - UI becomes sluggish
   - Animations stutter or skip
   - Touch responsiveness degrades

## Debug & Triage Steps

### 1. Performance Profiling
```swift
// Add performance markers in ChatView
let startTime = CFAbsoluteTimeGetCurrent()
// ... render operation ...
let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
if timeElapsed > 0.016 { // More than 16ms = frame drop
    print("⚠️ Slow render: \(timeElapsed)s")
}
```

### 2. Identify Render Triggers
```swift
// Add debug logging to track what causes re-renders
struct ChatView: View {
    init() {
        print("🔄 ChatView init")
    }
    
    var body: some View {
        let _ = print("🎨 ChatView body called")
        // ... view code ...
    }
}
```

### 3. ScrollView Diagnostics
```bash
# Check for ScrollView issues
grep -r "ScrollViewReader" ios/Sources/
grep -r "scrollTo" ios/Sources/
grep -r "withAnimation" ios/Sources/ | grep -i scroll
```

### 4. Memory & Layout Analysis
- Use Xcode Instruments to profile memory during long message send
- Enable Layout debugging in Xcode
- Check for constraint ambiguity
- Monitor for excessive view recreation

## Root Cause Analysis

### Suspected Causes

1. **Multiple Animation Conflicts**
   ```swift
   // Problematic: Multiple simultaneous animations
   withAnimation { 
       messages.append(newMessage) 
   }
   withAnimation { 
       scrollToBottom() 
   }
   ```

2. **Excessive Re-rendering**
   - Text measurement happening multiple times
   - View hierarchy rebuilding on each character
   - ForEach not properly identifying views

3. **ScrollView Performance**
   ```swift
   // Potential issue: Not using lazy loading
   ScrollView {
       ForEach(messages) { message in
           // Heavy view computation
       }
   }
   ```

## Recommended Solution

### Immediate Fixes

1. **Debounce UI Updates**
   ```swift
   class ChatViewModel: ObservableObject {
       private var updateTimer: Timer?
       
       func scheduleUpdate() {
           updateTimer?.invalidate()
           updateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { _ in
               self.performUpdate()
           }
       }
   }
   ```

2. **Optimize ScrollView**
   ```swift
   ScrollViewReader { proxy in
       ScrollView {
           LazyVStack(spacing: 8) { // Use LazyVStack
               ForEach(messages) { message in
                   MessageView(message: message)
                       .id(message.id) // Ensure proper identification
               }
           }
       }
       .onChange(of: messages.count) { _ in
           // Single, delayed scroll
           DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
               withAnimation(.easeOut(duration: 0.3)) {
                   proxy.scrollTo(messages.last?.id, anchor: .bottom)
               }
           }
       }
   }
   ```

3. **Text Rendering Optimization**
   ```swift
   struct MessageView: View {
       let message: Message
       @State private var textHeight: CGFloat = 100 // Estimated height
       
       var body: some View {
           Text(message.content)
               .fixedSize(horizontal: false, vertical: true)
               .frame(minHeight: textHeight)
               .background(GeometryReader { geometry in
                   Color.clear.preference(
                       key: HeightPreferenceKey.self,
                       value: geometry.size.height
                   )
               })
               .onPreferenceChange(HeightPreferenceKey.self) { height in
                   if abs(height - textHeight) > 10 { // Only update if significant change
                       textHeight = height
                   }
               }
       }
   }
   ```

### Long-term Improvements

1. **Virtual Scrolling**
   - Implement message windowing
   - Only render visible messages plus buffer
   - Recycle view instances

2. **Message Chunking**
   - Break long messages into chunks
   - Progressive rendering

3. **Separate Composition View**
   - Isolate input field from message list
   - Prevent input changes from triggering list re-render

## Testing Plan

1. **Test Scenarios**
   - Send 1000+ character message
   - Send multiple long messages rapidly
   - Long message while scrolling
   - Long message with attachments
   - Test on older devices (iPhone 11, iPad Air 3)

2. **Performance Metrics**
   - Frame rate during message send
   - Memory usage before/after
   - Time to render new message
   - Scroll performance with 100+ messages

## Acceptance Criteria

- [ ] No visual glitches when sending long messages
- [ ] Smooth scrolling maintained during message send
- [ ] <16ms render time for new messages
- [ ] No memory leaks during extended chat sessions
- [ ] Consistent behavior across all iOS devices
- [ ] Text input remains responsive while rendering

## Notes

Consider implementing a "message too long" warning if messages exceed a certain character count (e.g., 5000 characters) to prevent extreme cases.

---
**Last Updated**: 2025-09-12