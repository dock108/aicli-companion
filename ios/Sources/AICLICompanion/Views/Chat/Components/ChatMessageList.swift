import SwiftUI

@available(iOS 16.0, macOS 13.0, *)
struct ChatMessageList: View {
    let messages: [Message]
    let isLoading: Bool
    let progressInfo: ProgressInfo?
    let isIPad: Bool
    let horizontalSizeClass: UserInterfaceSizeClass?
    let colorScheme: ColorScheme
    let projectPath: String? // Add project path for project-specific storage
    
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
    @State private var wasAtBottomBeforeNavigation: Bool = true
    
    // Callbacks
    let onScrollPositionChanged: (CGFloat) -> Void
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
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
                .padding(.horizontal, isIPad && horizontalSizeClass == .regular ? 20 : 16)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(
                    GeometryReader { contentGeometry in
                        Color.clear
                            .preference(key: ContentHeightPreferenceKey.self, value: contentGeometry.size.height)
                            .preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: contentGeometry.frame(in: .named("scroll")).minY
                            )
                    }
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .preference(
                            key: ScrollViewSizePreferenceKey.self,
                            value: geometry.size.height
                        )
                }
            )
            .onAppear {
                initializeScrollPosition(proxy: proxy)
            }
            .onDisappear {
                // Save scroll position when navigating away
                saveScrollPosition()
            }
            .onPreferenceChange(ScrollViewSizePreferenceKey.self) { value in
                scrollViewHeight = value
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
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                // Use positive value for scroll position
                let scrollPosition = max(0, -value)
                handleScrollPositionChange(scrollPosition)
            }
            .onChange(of: messages.count) { oldCount, newCount in
                // Handle all message count increases (including initial load)
                if newCount > oldCount {
                    handleMessageCountChange(oldCount: oldCount, newCount: newCount, proxy: proxy)
                }
            }
            .onChange(of: messages.isEmpty) { wasEmpty, isEmpty in
                // Handle when messages array changes
                if wasEmpty && !isEmpty {
                    // Messages just loaded from empty state, use proper initialization
                    initializeScrollPosition(proxy: proxy)
                } else if !wasEmpty && isEmpty {
                    // Messages were cleared (e.g., session cleared)
                    hasInitiallyScrolled = false
                    lastReadMessageId = nil
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
    
    // MARK: - Enhanced Scroll Management
    
    private func initializeScrollPosition(proxy: ScrollViewProxy) {
        // Load the last read message from UserDefaults
        loadLastReadMessage()
        
        // Determine initial scroll position
        if messages.isEmpty {
            hasInitiallyScrolled = true
            return
        }
        
        // Check if we should restore to a saved position or go to bottom
        if wasAtBottomBeforeNavigation {
            // User was at bottom, scroll to bottom
            scrollToBottomReliably(proxy: proxy)
        } else if let lastReadId = lastReadMessageId,
                  messages.contains(where: { $0.id == lastReadId }) {
            // User was not at bottom, restore their position
            scrollToSavedPosition(messageId: lastReadId, proxy: proxy)
        } else {
            // No saved position, default to bottom for new conversations
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
        
        // Don't auto-scroll if user is actively scrolling
        guard !isUserScrolling else { return }
        
        let shouldScroll: Bool
        
        if oldCount == 0 {
            // Initial load - use saved position logic
            initializeScrollPosition(proxy: proxy)
            return
        }
        
        // For incremental message additions
        if let lastMessage = messages.last {
            if lastMessage.sender == .user {
                // Always scroll for user messages (they just sent it)
                shouldScroll = true
            } else {
                // For assistant messages, only scroll if user was near bottom
                // This preserves scroll position when reviewing history
                shouldScroll = isNearBottom && !isScrollingProgrammatically
            }
        } else {
            shouldScroll = false
        }
        
        if shouldScroll {
            if let lastMessage = messages.last {
                scrollToMessage(lastMessage.id, proxy: proxy, animated: true)
            }
        }
        
        // Save current scroll state
        saveScrollPosition()
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
        // Scroll to saved message without animation to restore position instantly
        isScrollingProgrammatically = true
        proxy.scrollTo(messageId, anchor: .center)
        hasInitiallyScrolled = true
        
        // Reset flag after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.isScrollingProgrammatically = false
        }
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
    
    private var scrollPositionKey: String {
        guard let projectPath = projectPath else { return "lastReadMessageId" }
        // Create a safe key from project path
        let safeKey = projectPath.replacingOccurrences(of: "/", with: "_")
        return "scrollPosition_\(safeKey)"
    }
    
    private var wasAtBottomKey: String {
        guard let projectPath = projectPath else { return "wasAtBottom" }
        let safeKey = projectPath.replacingOccurrences(of: "/", with: "_")
        return "wasAtBottom_\(safeKey)"
    }
    
    private func loadLastReadMessage() {
        // Load project-specific scroll position
        if let savedId = UserDefaults.standard.string(forKey: scrollPositionKey) {
            lastReadMessageId = UUID(uuidString: savedId)
        }
        
        // Load whether user was at bottom
        wasAtBottomBeforeNavigation = UserDefaults.standard.bool(forKey: wasAtBottomKey)
        
        // Default to true if not set (for new conversations)
        if !UserDefaults.standard.dictionaryRepresentation().keys.contains(wasAtBottomKey) {
            wasAtBottomBeforeNavigation = true
        }
    }
    
    private func saveLastReadMessage() {
        // Save project-specific scroll position
        UserDefaults.standard.set(lastReadMessageId?.uuidString, forKey: scrollPositionKey)
        
        // Save whether user is at bottom
        UserDefaults.standard.set(isNearBottom, forKey: wasAtBottomKey)
    }
    
    private func saveScrollPosition() {
        // Only save if we're not programmatically scrolling
        guard !isScrollingProgrammatically else { return }
        
        // Find the message that's currently visible in the middle of the screen
        // This provides better restoration than using the last message
        let midPoint = lastScrollPosition + (scrollViewHeight / 2)
        let messageHeight: CGFloat = 80 // Approximate message height
        let visibleIndex = Int(midPoint / messageHeight)
        
        if visibleIndex >= 0 && visibleIndex < messages.count {
            let visibleMessage = messages[visibleIndex]
            lastReadMessageId = visibleMessage.id
            UserDefaults.standard.set(visibleMessage.id.uuidString, forKey: scrollPositionKey)
        }
        
        // Always save whether user is at bottom
        UserDefaults.standard.set(isNearBottom, forKey: wasAtBottomKey)
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

struct ScrollViewSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
