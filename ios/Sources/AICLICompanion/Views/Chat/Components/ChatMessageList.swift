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
    @State private var hasScrolledToThinking: Bool = false
    @State private var lastScrollTime: Date = Date()
    
    
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
                        .padding(.horizontal, 4)
                        .id("claude-processing")
                    }
                    
                    // Small bottom padding for scroll alignment
                    Color.clear
                        .frame(height: 20) // Just enough to prevent content from being cut off
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
                let newScrollOffset = frame.minY
                let newContentHeight = frame.height
                
                // Only update if values have changed significantly (avoid micro-updates)
                if abs(newScrollOffset - scrollOffset) > 1 || abs(newContentHeight - contentHeight) > 1 {
                    scrollOffset = newScrollOffset
                    contentHeight = newContentHeight
                    
                    // Calculate if we're near bottom (within 100 points)
                    let distanceFromBottom = contentHeight - visibleHeight + scrollOffset
                    isNearBottom = distanceFromBottom < 100
                    
                    // Only animate button visibility on significant changes
                    if distanceFromBottom > 200 && !showScrollButton {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showScrollButton = true
                        }
                    } else if distanceFromBottom <= 200 && showScrollButton {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showScrollButton = false
                        }
                    }
                    
                    // Update auto-scroll state based on position
                    if distanceFromBottom > 150 && shouldAutoScroll {
                        shouldAutoScroll = false
                    } else if distanceFromBottom < 50 && !shouldAutoScroll {
                        shouldAutoScroll = true
                        if unreadMessageCount > 0 {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                unreadMessageCount = 0
                            }
                        }
                    }
                }
            }
            .onAppear {
                // Start at bottom like iMessage
                scrollToBottom(proxy, animated: false)
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
            .onChange(of: isLoading) { oldValue, newValue in
                // Only scroll when transitioning from not loading to loading
                // Add debounce to prevent rapid triggering
                let now = Date()
                if !oldValue && newValue && shouldAutoScroll && !hasScrolledToThinking {
                    // Check if enough time has passed since last scroll (300ms debounce)
                    if now.timeIntervalSince(lastScrollTime) > 0.3 {
                        hasScrolledToThinking = true
                        lastScrollTime = now
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo("loading-indicator", anchor: .bottom)
                            }
                        }
                    }
                } else if oldValue && !newValue {
                    // Reset flag when loading completes
                    hasScrolledToThinking = false
                }
            }
            .onChange(of: claudeStatus.isProcessing) { oldValue, newValue in
                // Only scroll when transitioning from not processing to processing
                // Add debounce to prevent rapid triggering
                let now = Date()
                if !oldValue && newValue && shouldAutoScroll && !hasScrolledToThinking {
                    // Check if enough time has passed since last scroll (300ms debounce)
                    if now.timeIntervalSince(lastScrollTime) > 0.3 {
                        hasScrolledToThinking = true
                        lastScrollTime = now
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo("claude-processing", anchor: .bottom)
                            }
                        }
                    }
                } else if oldValue && !newValue {
                    // Reset flag when processing completes
                    hasScrolledToThinking = false
                }
            }
            
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
                .padding(.bottom, 100) // Above input bar with proper spacing
            }
        }
    }
    
    // MARK: - Enhanced Scroll Management
    
    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        // Determine the best target to scroll to
        let targetId: String
        if isLoading {
            targetId = "loading-indicator"
        } else if claudeStatus.isProcessing {
            targetId = "claude-processing"
        } else if !messages.isEmpty {
            targetId = messages.last?.id.uuidString ?? "bottom-spacer"
        } else {
            targetId = "bottom-spacer"
        }
        
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
