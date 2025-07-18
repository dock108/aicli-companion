import UIKit

class HapticManager {
    static let shared = HapticManager()
    
    private init() {}
    
    // MARK: - Impact Feedback
    
    func lightImpact() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    func mediumImpact() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }
    
    func heavyImpact() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()
    }
    
    // MARK: - Selection Feedback
    
    func selectionChanged() {
        let selectionFeedback = UISelectionFeedbackGenerator()
        selectionFeedback.selectionChanged()
    }
    
    // MARK: - Notification Feedback
    
    func success() {
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.success)
    }
    
    func error() {
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.error)
    }
    
    func warning() {
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.warning)
    }
    
    // MARK: - Context-Specific Haptics
    
    func messageSent() {
        lightImpact()
    }
    
    func messageReceived() {
        selectionChanged()
    }
    
    func toolStarted() {
        mediumImpact()
    }
    
    func toolCompleted() {
        success()
    }
    
    func toolFailed() {
        error()
    }
    
    func buttonTap() {
        lightImpact()
    }
    
    func contextMenuOpen() {
        mediumImpact()
    }
    
    func workflowSuggestionTap() {
        selectionChanged()
    }
    
    func fileSelected() {
        lightImpact()
    }
    
    func conversationSwitch() {
        mediumImpact()
    }
    
    func bulkActionComplete() {
        success()
    }
}