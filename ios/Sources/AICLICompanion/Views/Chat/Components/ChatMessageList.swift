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
    
    // Enhanced scroll state management
    @State private var hasInitiallyScrolled: Bool = false
    @State private var isScrollingProgrammatically: Bool = false
    @State private var isUserScrolling: Bool = false
    @State private var scrollDebounceTask: Task<Void, Never>?
    @State private var lastReadMessageId: UUID?
    @State private var userScrollTimer: Timer?
    
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
                            // Use ThinkingIndicator with enhanced progress info
                            ThinkingIndicator(progressInfo: progressInfo)
                                .padding(.horizontal, 4)
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
                    initializeScrollPosition(proxy: proxy)
                }
                .onChange(of: geometry.size.height) { _, newHeight in
                    scrollViewHeight = newHeight
                }
                .onPreferenceChange(ContentHeightPreferenceKey.self) { value in
                    let previousContentHeight = contentHeight
                    contentHeight = value
                    
                    // Only auto-scroll for keyboard appearance, not general content changes
                    // This prevents scrolling issues when reviewing history
                    let isKeyboardRelatedChange = abs(value - previousContentHeight) > 200
                    if hasInitiallyScrolled && isKeyboardRelatedChange && isNearBottom && !isScrollingProgrammatically {
                        scrollToBottomSmooth(proxy: proxy)
                    }
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
                    handleScrollPositionChange(-value)
                }
                .onChange(of: messages.count) { oldCount, newCount in
                    // Handle all message count increases (including initial load)
                    if newCount > oldCount {
                        handleMessageCountChange(oldCount: oldCount, newCount: newCount, proxy: proxy)
                    }
                }
                .onChange(of: messages.isEmpty) { _, isEmpty in
                    // Handle when messages array changes from empty to populated
                    if !isEmpty {
                        // Messages just loaded, scroll to bottom
                        scrollToBottomReliably(proxy: proxy)
                    }
                }
                .onChange(of: isLoading) { oldLoading, newLoading in
                    handleLoadingStateChange(oldLoading: oldLoading, newLoading: newLoading, proxy: proxy)
                }
                .onReceive(NotificationCenter.default.publisher(for: .scrollToBottom)) { _ in
                    scrollToBottomSmooth(proxy: proxy)
                }
            }
        }
    }
    
    // MARK: - Enhanced Scroll Management
    
    private func initializeScrollPosition(proxy: ScrollViewProxy) {
        // Load the last read message from UserDefaults
        loadLastReadMessage()
        
        // Determine initial scroll position
        if messages.isEmpty {
            hasInitiallyScrolled = true
            return
        }
        
        // If we have a saved last read message, try to scroll to it
        if let lastReadId = lastReadMessageId,
           messages.contains(where: { $0.id == lastReadId }) {
            scrollToSavedPosition(messageId: lastReadId, proxy: proxy)
        } else {
            // Default to scrolling to bottom
            scrollToBottomReliably(proxy: proxy)
        }
    }
    
    private func handleScrollPositionChange(_ newPosition: CGFloat) {
        // Cancel any pending debounce task
        scrollDebounceTask?.cancel()
        
        // Track user scrolling state
        if !isScrollingProgrammatically {
            isUserScrolling = true
            userScrollTimer?.invalidate()
            userScrollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                self.isUserScrolling = false
            }
        }
        
        // Debounce rapid scroll changes to prevent performance issues
        scrollDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms debounce
            
            await MainActor.run {
                guard !Task.isCancelled else { return }
                
                lastScrollPosition = newPosition
                updateNearBottomStatus()
                onScrollPositionChanged(newPosition)
                
                // Save scroll position periodically
                saveScrollPosition()
            }
        }
    }
    
    private func updateNearBottomStatus() {
        let threshold: CGFloat = 100
        let maxScroll = max(0, contentHeight - scrollViewHeight)
        let isCurrentlyNearBottom = lastScrollPosition >= maxScroll - threshold
        
        if isCurrentlyNearBottom != isNearBottom {
            isNearBottom = isCurrentlyNearBottom
        }
    }
    
    private func handleMessageCountChange(oldCount: Int, newCount: Int, proxy: ScrollViewProxy) {
        guard newCount > oldCount else { return }
        
        // Don't auto-scroll if user is actively scrolling or reviewing history
        guard !isScrollingProgrammatically else { return }
        
        let shouldScroll: Bool
        
        if oldCount == 0 {
            // Initial load - scroll to saved position or bottom
            shouldScroll = true
        } else if let lastMessage = messages.last {
            if lastMessage.sender == .user {
                // Always scroll for user messages (they just sent it)
                shouldScroll = true
            } else {
                // For assistant messages, only scroll if already near bottom
                // This allows users to review history without interruption
                shouldScroll = isNearBottom && !isUserScrolling
            }
        } else {
            shouldScroll = false
        }
        
        if shouldScroll {
            if oldCount == 0 {
                // Initial load - use saved position or go to bottom
                initializeScrollPosition(proxy: proxy)
            } else if let lastMessage = messages.last {
                scrollToMessage(lastMessage.id, proxy: proxy, animated: lastMessage.sender == .assistant)
            }
        }
        
        // Update last read message
        if let lastMessage = messages.last {
            lastReadMessageId = lastMessage.id
            saveLastReadMessage()
        }
    }
    
    private func handleLoadingStateChange(oldLoading: Bool, newLoading: Bool, proxy: ScrollViewProxy) {
        if !oldLoading && newLoading && isNearBottom {
            scrollToLoadingIndicator(proxy: proxy)
        }
    }
    
    private func scrollToMessage(_ messageId: UUID, proxy: ScrollViewProxy, animated: Bool = true) {
        isScrollingProgrammatically = true
        
        let action = {
            proxy.scrollTo(messageId, anchor: .bottom)
        }
        
        if animated {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                action()
            }
        } else {
            action()
        }
        
        // Reset programmatic flag after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + (animated ? 0.5 : 0.1)) {
            isScrollingProgrammatically = false
        }
    }
    
    private func scrollToSavedPosition(messageId: UUID, proxy: ScrollViewProxy) {
        // Scroll to saved message without animation to restore position
        proxy.scrollTo(messageId, anchor: .center)
        hasInitiallyScrolled = true
    }
    
    private func scrollToLoadingIndicator(proxy: ScrollViewProxy) {
        isScrollingProgrammatically = true
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            proxy.scrollTo("loading-indicator", anchor: .bottom)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isScrollingProgrammatically = false
        }
    }
    
    private func scrollToBottomSmooth(proxy: ScrollViewProxy) {
        guard let lastMessage = messages.last else { return }
        scrollToMessage(lastMessage.id, proxy: proxy, animated: true)
    }
    
    private func scrollToBottomReliably(proxy: ScrollViewProxy) {
        guard let lastMessage = messages.last else {
            hasInitiallyScrolled = true
            return
        }
        
        // Use a more reliable approach with proper timing
        isScrollingProgrammatically = true
        
        // Immediate scroll (no animation for reliability)
        proxy.scrollTo(lastMessage.id, anchor: .bottom)
        
        // Follow-up scroll after a short delay to handle render timing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            proxy.scrollTo(lastMessage.id, anchor: .bottom)
            self.hasInitiallyScrolled = true
            self.isScrollingProgrammatically = false
        }
    }
    
    // MARK: - Persistence
    
    private func loadLastReadMessage() {
        if let savedId = UserDefaults.standard.string(forKey: "lastReadMessageId") {
            lastReadMessageId = UUID(uuidString: savedId)
        }
    }
    
    private func saveLastReadMessage() {
        UserDefaults.standard.set(lastReadMessageId?.uuidString, forKey: "lastReadMessageId")
    }
    
    private func saveScrollPosition() {
        // Only save if we're not programmatically scrolling
        guard !isScrollingProgrammatically else { return }
        
        // Save the current message that's visible at the top
        if let visibleMessage = messages.last {
            lastReadMessageId = visibleMessage.id
            UserDefaults.standard.set(visibleMessage.id.uuidString, forKey: "lastReadMessageId")
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
