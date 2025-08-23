import SwiftUI
import AICLICompanion

@main
@available(iOS 17.0, macOS 14.0, *)
struct AppMain: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AICLICompanion.AppDelegate.self) var appDelegate
    #endif
    
    // Use shared instances directly - don't force initialization
    // Services will be created only when first accessed by views
    private var aicliService: AICLICompanion.AICLIService {
        AICLICompanion.AICLIService.shared
    }
    
    private var settingsManager: AICLICompanion.SettingsManager {
        AICLICompanion.SettingsManager.shared
    }
    
    private var pushNotificationService: AICLICompanion.PushNotificationService {
        AICLICompanion.PushNotificationService.shared
    }
    
    init() {
        AICLICompanion.PerformanceLogger.shared.logAppEvent("AppMain init started")
        print("🚀 AppMain init started")
        
        // Pre-warm keyboard to prevent 12s freeze on first tap
        #if os(iOS)
        // Schedule keyboard pre-warming for after window creation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Create an actual UITextField and briefly make it first responder
            let textField = UITextField(frame: .zero)
            
            // Get the key window using the modern approach
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                window.addSubview(textField)
                textField.alpha = 0 // Make it invisible
                textField.becomeFirstResponder()
                
                // Immediately resign and remove
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    textField.resignFirstResponder()
                    textField.removeFromSuperview()
                    print("⌨️ Keyboard system pre-warmed successfully")
                }
            } else {
                print("⌨️ Failed to pre-warm keyboard - no window available")
            }
        }
        #endif
        
        // Heavy service initialization will happen lazily when first accessed
        print("🚀 AppMain init completed quickly")
        AICLICompanion.PerformanceLogger.shared.logAppEvent("AppMain init completed")
    }
    
    var body: some Scene {
        WindowGroup {
            AICLICompanion.AdaptiveContentView()
                .environmentObject(aicliService)
                .environmentObject(settingsManager)
                .environmentObject(pushNotificationService)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    // Clear badge count when app becomes active
                    #if os(iOS)
                    UIApplication.shared.applicationIconBadgeNumber = 0
                    #endif
                    // Also reset the notification service's badge tracking
                    AICLICompanion.PushNotificationService.shared.resetBadgeCount()
                    print("📱 App became active - cleared badge count")
                    
                    // Don't process pending notifications here - already handled in AppDelegate
                    // This prevents duplicate processing and improves performance
                }
        }
    }
}