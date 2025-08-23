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
    
    // Simple scroll state - only what we actually need
    @State private var isNearBottom: Bool = true
    @State private var shouldAutoScroll: Bool = true
    
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
                        .onAppear {
                            print("💬 ChatMessageList: Showing typing bubble - Activity: \(activity), Elapsed: \(claudeStatus.elapsedSeconds)s")
                        }
                        .padding(.horizontal, 4)
                        .id("claude-processing")
                    }
                }
                .padding(.horizontal, isIPad && horizontalSizeClass == .regular ? 20 : 16)
                .padding(.vertical, 16)
            }
            .background(
                // Simple scroll detection using GeometryReader
                GeometryReader { geometry in
                    Color.clear
                        .preference(key: ScrollDetectionKey.self, value: geometry.frame(in: .named("scroll")).minY)
                }
            )
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(ScrollDetectionKey.self) { value in
                // Simple detection: if we're scrolling up significantly, stop auto-scroll
                let scrollOffset = -value
                
                // If user scrolled up more than 50 points, stop auto-scroll
                if scrollOffset > 50 {
                    shouldAutoScroll = false
                    isNearBottom = false
                } else if scrollOffset < 10 {
                    // If near top of scroll (bottom of messages), resume auto-scroll
                    shouldAutoScroll = true
                    isNearBottom = true
                }
            }
            .onAppear {
                // Simple: always start at bottom like iMessage
                scrollToBottom(proxy, animated: false)
            }
            .onChange(of: messages.count) { oldCount, newCount in
                // Simple rule: if user is near bottom and messages increased, scroll to new messages
                if newCount > oldCount && shouldAutoScroll {
                    scrollToBottom(proxy, animated: true)
                }
            }
            .onChange(of: isLoading) { _, loading in
                // Show loading indicator at bottom if user should see it
                if loading && shouldAutoScroll {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo("loading-indicator", anchor: .bottom)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .scrollToBottom)) { _ in
                scrollToBottom(proxy, animated: true)
            }
            #if os(iOS)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                // Scroll to bottom when keyboard appears (if near bottom)
                if shouldAutoScroll {
                    scrollToBottom(proxy, animated: true)
                }
            }
            #endif
        }
    }
    
    // MARK: - Simple Scroll Management
    
    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let lastMessage = messages.last else { return }
        
        if animated {
            withAnimation(.easeOut(duration: 0.3)) {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(lastMessage.id, anchor: .bottom)
        }
        
        // Update state
        isNearBottom = true
        shouldAutoScroll = true
    }
    
    // updateScrollState is now handled inline in onPreferenceChange
}

// MARK: - Preference Key for Scroll Detection

struct ScrollDetectionKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
