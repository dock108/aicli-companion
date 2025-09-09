import SwiftUI
#if os(iOS)
import UIKit
#endif

@available(iOS 16.0, macOS 13.0, *)
struct ChatMessageList: View {
    let messages: [Message]
    let isLoading: Bool
    let progressInfo: ProgressInfo?
    let isIPad: Bool
    let horizontalSizeClass: UserInterfaceSizeClass?
    let colorScheme: ColorScheme
    @ObservedObject var claudeStatus: Project.StatusInfo
    
    // Enhanced scroll state management
    @State private var isNearBottom: Bool = true
    @State private var shouldAutoScroll: Bool = true
    @State private var scrollOffset: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var visibleHeight: CGFloat = 0
    @State private var showScrollButton: Bool = false
    @State private var unreadMessageCount: Int = 0
    
    // For detecting bottom padding needs
    @State private var keyboardHeight: CGFloat = 0
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(messages) { message in
                        QueueAwareMessageCell(message: message)
                            .id(message.id)
                    }
                    
                    // Show typing bubble when Claude is processing or app is loading
                    if isLoading {
                        ThinkingIndicator(progressInfo: progressInfo)
                            .padding(.horizontal, 4)
                            .id("loading-indicator")
                            .onAppear {
                                // CRITICAL: Auto-scroll when thinking indicator appears
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        proxy.scrollTo("loading-indicator", anchor: .bottom)
                                    }
                                }
                            }
                    } else if claudeStatus.isProcessing {
                        // Show typing bubble when Claude is working
                        let activity = claudeStatus.lastActivity ?? "Thinking"
                        ThinkingIndicator(progressInfo: ProgressInfo(
                            message: activity,
                            progress: nil,
                            stage: activity,
                            estimatedTimeRemaining: nil,
                            isIndeterminate: true
                        ))
                        .onAppear {
                            print("💬 ChatMessageList: Showing typing bubble - Activity: \(activity), Elapsed: \(claudeStatus.elapsedSeconds)s")
                            // CRITICAL: Auto-scroll when Claude starts processing
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    proxy.scrollTo("claude-processing", anchor: .bottom)
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                        .id("claude-processing")
                    }
                    
                    // Bottom padding to ensure content is visible above input bar
                    // This is critical for the thinking indicator visibility
                    Color.clear
                        .frame(height: 80 + keyboardHeight) // Input bar height + keyboard
                        .id("bottom-spacer")
                }
                .padding(.horizontal, isIPad && horizontalSizeClass == .regular ? 20 : 16)
                .padding(.top, 16)
                .background(
                    GeometryReader { geometry in
                        Color.clear
                            .preference(key: ScrollOffsetKey.self,
                                      value: geometry.frame(in: .named("scroll")))
                    }
                )
            }
            .coordinateSpace(name: "scroll")
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear {
                            visibleHeight = geometry.size.height
                        }
                        .onChange(of: geometry.size.height) { _, newHeight in
                            visibleHeight = newHeight
                        }
                }
            )
            .onPreferenceChange(ScrollOffsetKey.self) { frame in
                // Track scroll position more accurately
                scrollOffset = frame.minY
                contentHeight = frame.height
                
                // Calculate if we're near bottom (within 100 points)
                let distanceFromBottom = contentHeight - visibleHeight + scrollOffset
                isNearBottom = distanceFromBottom < 100
                
                // Show scroll button when user scrolls up more than 200 points
                withAnimation(.easeInOut(duration: 0.2)) {
                    showScrollButton = distanceFromBottom > 200
                }
                
                // If user scrolled up significantly (more than 150 points from bottom), disable auto-scroll
                if distanceFromBottom > 150 {
                    shouldAutoScroll = false
                } else if distanceFromBottom < 50 {
                    // Re-enable auto-scroll when very close to bottom
                    shouldAutoScroll = true
                    // Hide button when near bottom
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showScrollButton = false
                        unreadMessageCount = 0
                    }
                }
            }
            .onAppear {
                // Start at bottom like iMessage
                scrollToBottom(proxy, animated: false)
                setupKeyboardObservers()
            }
            .onDisappear {
                removeKeyboardObservers()
            }
            .onChange(of: messages.count) { oldCount, newCount in
                // Auto-scroll on new messages if appropriate
                if newCount > oldCount {
                    if shouldAutoScroll {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            scrollToBottom(proxy, animated: true)
                        }
                    } else {
                        // User is scrolled up, increment unread count
                        let newMessages = newCount - oldCount
                        withAnimation(.easeInOut(duration: 0.2)) {
                            unreadMessageCount += newMessages
                        }
                    }
                }
            }
            .onChange(of: isLoading) { _, loading in
                // Ensure thinking indicator is visible when it appears
                if loading && shouldAutoScroll {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo("loading-indicator", anchor: .bottom)
                        }
                    }
                }
            }
            .onChange(of: claudeStatus.isProcessing) { _, isProcessing in
                // CRITICAL: Scroll when Claude status changes to processing
                if isProcessing && shouldAutoScroll {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo("claude-processing", anchor: .bottom)
                        }
                    }
                }
            }
            #if os(iOS)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
                handleKeyboardShow(notification)
                // Scroll to bottom when keyboard appears (if near bottom)
                if shouldAutoScroll {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        scrollToBottom(proxy, animated: true)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { notification in
                handleKeyboardHide(notification)
            }
            #endif
            
            // Scroll to bottom button overlay
            .overlay(alignment: .bottomTrailing) {
                ScrollToBottomButton(
                    isVisible: showScrollButton,
                    unreadCount: unreadMessageCount
                ) {
                    // Scroll to bottom action
                    scrollToBottom(proxy, animated: true)
                    unreadMessageCount = 0
                }
                .padding(.trailing, 16)
                .padding(.bottom, 90) // Above input bar
            }
        }
    }
    
    // MARK: - Enhanced Scroll Management
    
    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        // Try to scroll to bottom spacer for better positioning
        let targetId = "bottom-spacer"
        
        if animated {
            withAnimation(.easeOut(duration: 0.3)) {
                proxy.scrollTo(targetId, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(targetId, anchor: .bottom)
        }
        
        // Update state
        isNearBottom = true
        shouldAutoScroll = true
    }
    
    // MARK: - Keyboard Handling
    
    #if os(iOS)
    private func setupKeyboardObservers() {
        // Observers are already set up via onReceive
    }
    
    private func removeKeyboardObservers() {
        // Cleanup handled automatically by SwiftUI
    }
    
    private func handleKeyboardShow(_ notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else {
            return
        }
        
        withAnimation(.easeOut(duration: duration)) {
            keyboardHeight = keyboardFrame.height
        }
    }
    
    private func handleKeyboardHide(_ notification: Notification) {
        guard let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else {
            return
        }
        
        withAnimation(.easeOut(duration: duration)) {
            keyboardHeight = 0
        }
    }
    #else
    private func setupKeyboardObservers() {}
    private func removeKeyboardObservers() {}
    #endif
}

// MARK: - Preference Keys

struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

struct ScrollDetectionKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
