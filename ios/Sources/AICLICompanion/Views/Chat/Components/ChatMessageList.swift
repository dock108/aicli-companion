import SwiftUI

@available(iOS 16.0, macOS 13.0, *)
struct ChatMessageList: View {
    let messages: [Message]
    let isLoading: Bool
    let progressInfo: ProgressInfo?
    let isIPad: Bool
    let horizontalSizeClass: UserInterfaceSizeClass?
    let colorScheme: ColorScheme
    
    // Scroll tracking
    @Binding var isNearBottom: Bool
    @Binding var lastScrollPosition: CGFloat
    @Binding var scrollViewHeight: CGFloat
    @Binding var contentHeight: CGFloat
    
    // Callbacks
    let onScrollPositionChanged: (CGFloat) -> Void
    
    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { geometry in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(messages) { message in
                            QueueAwareMessageCell(message: message)
                                .id(message.id)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .offset(y: 8)),
                                    removal: .opacity
                                ))
                                .animation(.easeOut(duration: 0.12), value: messages.count)
                        }
                        
                        if isLoading {
                            ChatLoadingView(progressInfo: progressInfo, colorScheme: colorScheme)
                                .id("loading-indicator")
                        }
                    }
                    .padding(.horizontal, isIPad && horizontalSizeClass == .regular ? 40 : 16)
                    .padding(.vertical, 16)
                    .background(
                        GeometryReader { contentGeometry in
                            Color.clear
                                .preference(key: ContentHeightPreferenceKey.self, value: contentGeometry.size.height)
                        }
                    )
                }
                .onAppear {
                    scrollViewHeight = geometry.size.height
                    // Scroll to bottom when conversation opens
                    scrollToBottomReliably(proxy: proxy)
                }
                .onChange(of: geometry.size.height) { _, newHeight in
                    scrollViewHeight = newHeight
                }
                .onPreferenceChange(ContentHeightPreferenceKey.self) { value in
                    contentHeight = value
                }
                .background(
                    GeometryReader { scrollGeometry in
                        Color.clear
                            .preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: scrollGeometry.frame(in: .named("scroll")).origin.y
                            )
                    }
                )
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    lastScrollPosition = -value
                    onScrollPositionChanged(-value)
                }
                .onChange(of: messages.count) { oldCount, newCount in
                    // Handle all message count increases (including initial load)
                    if newCount > oldCount {
                        handleMessageCountChange(oldCount: oldCount, newCount: newCount, proxy: proxy)
                    }
                }
                .onChange(of: messages.isEmpty) { isEmpty in
                    // Handle when messages array changes from empty to populated
                    if !isEmpty {
                        // Messages just loaded, scroll to bottom
                        scrollToBottomReliably(proxy: proxy)
                    }
                }
                .onChange(of: isLoading) { newLoading in
                    handleLoadingStateChange(oldLoading: !newLoading, newLoading: newLoading, proxy: proxy)
                }
            }
        }
    }
    
    private func handleMessageCountChange(oldCount: Int, newCount: Int, proxy: ScrollViewProxy) {
        guard newCount > oldCount else { return }
        
        // Determine if we should auto-scroll to the newest message
        let shouldScroll: Bool
        
        if oldCount == 0 {
            // Initial load - always scroll to bottom
            shouldScroll = true
        } else if let lastMessage = messages.last {
            // New message added - check scroll behavior
            if lastMessage.sender == .user {
                // Always scroll for user messages (they just sent it)
                shouldScroll = true
            } else {
                // For assistant messages, only scroll if user is near bottom
                shouldScroll = isNearBottom
            }
        } else {
            shouldScroll = false
        }
        
        if shouldScroll {
            if let lastMessage = messages.last {
                scrollToMessage(lastMessage.id, proxy: proxy, animated: oldCount > 0 && lastMessage.sender == .assistant)
            }
        }
    }
    
    private func handleLoadingStateChange(oldLoading: Bool, newLoading: Bool, proxy: ScrollViewProxy) {
        // When loading starts (thinking indicator appears)
        if !oldLoading && newLoading && isNearBottom {
            scrollToLoadingIndicator(proxy: proxy)
        }
    }
    
    private func scrollToMessage(_ messageId: UUID, proxy: ScrollViewProxy, animated: Bool = true) {
        if animated {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                proxy.scrollTo(messageId, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(messageId, anchor: .bottom)
        }
    }
    
    private func scrollToLoadingIndicator(proxy: ScrollViewProxy) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            proxy.scrollTo("loading-indicator", anchor: .bottom)
        }
    }
    
    private func scrollToBottomReliably(proxy: ScrollViewProxy) {
        guard let lastMessage = messages.last else { return }
        
        // Multiple attempts with increasing delays to handle render timing
        DispatchQueue.main.async {
            proxy.scrollTo(lastMessage.id, anchor: .bottom)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            proxy.scrollTo(lastMessage.id, anchor: .bottom)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            proxy.scrollTo(lastMessage.id, anchor: .bottom)
        }
    }
}

// MARK: - Preference Keys

struct ContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
