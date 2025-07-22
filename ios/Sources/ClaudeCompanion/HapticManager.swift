#if canImport(UIKit)
import UIKit
#endif
import Foundation

class HapticManager {
    static let shared = HapticManager()

    private init() {}

    // MARK: - Impact Feedback

    func lightImpact() {
        #if canImport(UIKit)
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        #endif
    }

    func mediumImpact() {
        #if canImport(UIKit)
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        #endif
    }

    func heavyImpact() {
        #if canImport(UIKit)
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()
        #endif
    }

    // MARK: - Selection Feedback

    func selectionChanged() {
        #if canImport(UIKit)
        let selectionFeedback = UISelectionFeedbackGenerator()
        selectionFeedback.selectionChanged()
        #endif
    }

    // MARK: - Notification Feedback

    func success() {
        #if canImport(UIKit)
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.success)
        #endif
    }

    func error() {
        #if canImport(UIKit)
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.error)
        #endif
    }

    func warning() {
        #if canImport(UIKit)
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.warning)
        #endif
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
