import SwiftUI

struct AnimationConstants {
    
    // MARK: - Timing Constants
    
    static let fastAnimation: Double = 0.2
    static let standardAnimation: Double = 0.3
    static let slowAnimation: Double = 0.5
    static let verySlowAnimation: Double = 0.8
    
    // MARK: - Spring Animations
    
    static let springBouncy = Animation.spring(response: 0.6, dampingFraction: 0.8, blendDuration: 0)
    static let springSnappy = Animation.spring(response: 0.3, dampingFraction: 0.9, blendDuration: 0)
    static let springSmooth = Animation.spring(response: 0.4, dampingFraction: 1.0, blendDuration: 0)
    
    // MARK: - Easing Animations
    
    static let easeInOut = Animation.easeInOut(duration: standardAnimation)
    static let easeIn = Animation.easeIn(duration: standardAnimation)
    static let easeOut = Animation.easeOut(duration: standardAnimation)
    
    // MARK: - Context-Specific Animations
    
    static let messageAppear = Animation.easeOut(duration: 0.4)
    static let messageTyping = Animation.easeInOut(duration: 0.6).repeatForever(autoreverses: true)
    static let toolActivityPulse = Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true)
    static let buttonPress = Animation.easeInOut(duration: 0.1)
    static let sheetPresentation = Animation.easeInOut(duration: 0.4)
    static let tabSwitch = Animation.easeInOut(duration: 0.3)
    static let selectionToggle = Animation.spring(response: 0.4, dampingFraction: 0.8)
    static let workflowSuggestionSlide = Animation.easeOut(duration: 0.5)
    static let contextMenuAppear = Animation.spring(response: 0.3, dampingFraction: 0.7)
    
    // MARK: - Scale Factors
    
    static let buttonPressScale: CGFloat = 0.95
    static let cardHoverScale: CGFloat = 1.02
    static let toolActivityScale: CGFloat = 1.1
    
    // MARK: - Delays
    
    static let staggerDelay: Double = 0.1
    static let quickDelay: Double = 0.05
    static let mediumDelay: Double = 0.2
    
    // MARK: - Opacity Values
    
    static let hiddenOpacity: Double = 0.0
    static let dimOpacity: Double = 0.6
    static let fullOpacity: Double = 1.0
}

// MARK: - Animation View Modifiers

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? AnimationConstants.buttonPressScale : 1.0)
            .animation(AnimationConstants.buttonPress, value: configuration.isPressed)
    }
}

struct PulseEffect: ViewModifier {
    @State private var isPulsing = false
    let scale: CGFloat
    let opacity: Double
    
    init(scale: CGFloat = 1.1, opacity: Double = 0.7) {
        self.scale = scale
        self.opacity = opacity
    }
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? scale : 1.0)
            .opacity(isPulsing ? opacity : 1.0)
            .onAppear {
                withAnimation(AnimationConstants.toolActivityPulse) {
                    isPulsing.toggle()
                }
            }
    }
}

struct SlideInEffect: ViewModifier {
    @State private var isVisible = false
    let delay: Double
    let direction: Edge
    
    init(delay: Double = 0, from direction: Edge = .bottom) {
        self.delay = delay
        self.direction = direction
    }
    
    func body(content: Content) -> some View {
        content
            .offset(
                x: direction == .leading ? (isVisible ? 0 : -100) : (direction == .trailing ? (isVisible ? 0 : 100) : 0),
                y: direction == .top ? (isVisible ? 0 : -100) : (direction == .bottom ? (isVisible ? 0 : 100) : 0)
            )
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                withAnimation(AnimationConstants.easeOut.delay(delay)) {
                    isVisible = true
                }
            }
    }
}

struct FadeInEffect: ViewModifier {
    @State private var isVisible = false
    let delay: Double
    
    init(delay: Double = 0) {
        self.delay = delay
    }
    
    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                withAnimation(AnimationConstants.easeIn.delay(delay)) {
                    isVisible = true
                }
            }
    }
}

// MARK: - View Extensions

extension View {
    func scaleButtonStyle() -> some View {
        self.buttonStyle(ScaleButtonStyle())
    }
    
    func pulseEffect(scale: CGFloat = 1.1, opacity: Double = 0.7) -> some View {
        self.modifier(PulseEffect(scale: scale, opacity: opacity))
    }
    
    func slideIn(delay: Double = 0, from direction: Edge = .bottom) -> some View {
        self.modifier(SlideInEffect(delay: delay, from: direction))
    }
    
    func fadeIn(delay: Double = 0) -> some View {
        self.modifier(FadeInEffect(delay: delay))
    }
}