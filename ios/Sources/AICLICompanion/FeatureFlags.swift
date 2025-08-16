import Foundation

/// Centralized feature flags for toggling functionality
/// This allows disabling features without removing code
@available(iOS 16.0, macOS 13.0, *)
struct FeatureFlags {
    // MARK: - Queue System Features
    
    /// Enable/disable the message queue system
    /// When false: messages are sent immediately or blocked if waiting for response
    /// When true: messages are queued when waiting for response
    static let isQueueSystemEnabled: Bool = false
    
    /// Show/hide queue-related UI elements
    /// When false: queue indicators, counts, and status are hidden
    /// When true: queue UI elements are visible
    static let showQueueUI: Bool = false
    
    /// Enable/disable queue processing logic
    /// When false: queue processing functions are bypassed
    /// When true: queue processing runs normally
    static let enableQueueProcessing: Bool = false
    
    // MARK: - Auto Mode Features
    
    /// Enable/disable auto response mode
    /// When false: auto response controls and logic are disabled
    /// When true: auto response mode is available
    static let isAutoModeEnabled: Bool = false
    
    /// Show/hide auto mode UI controls
    /// When false: auto response controls are hidden from chat view
    /// When true: auto response controls are visible
    static let showAutoModeUI: Bool = false
    
    /// Enable/disable auto mode settings
    /// When false: auto mode settings are hidden from settings screens
    /// When true: auto mode settings are visible and functional
    static let enableAutoModeSettings: Bool = false
    
    // MARK: - Development Features
    
    /// Enable/disable debug logging for feature flags
    /// When true: logs when features are disabled by flags
    /// When false: no feature flag debug logging
    static let debugFeatureFlags: Bool = true
    
    /// Enable/disable all experimental features
    /// Master switch for any experimental or beta features
    static let enableExperimentalFeatures: Bool = false
    
    // MARK: - Helper Functions
    
    /// Log when a feature is disabled by feature flag
    static func logFeatureDisabled(_ featureName: String, reason: String = "Feature flag disabled") {
        if debugFeatureFlags {
            print("🚫 FeatureFlag: \(featureName) disabled - \(reason)")
        }
    }
    
    /// Check if queue system should be active
    static var shouldUseQueueSystem: Bool {
        return isQueueSystemEnabled && enableQueueProcessing
    }
    
    /// Check if auto mode should be active
    static var shouldUseAutoMode: Bool {
        return isAutoModeEnabled && enableAutoModeSettings
    }
}

// MARK: - Feature Flag Extensions

@available(iOS 16.0, macOS 13.0, *)
extension FeatureFlags {
    /// Get a summary of current feature flag states
    static var summary: String {
        return """
        FeatureFlags Summary:
        - Queue System: \(isQueueSystemEnabled ? "✅" : "❌")
        - Queue UI: \(showQueueUI ? "✅" : "❌")
        - Queue Processing: \(enableQueueProcessing ? "✅" : "❌")
        - Auto Mode: \(isAutoModeEnabled ? "✅" : "❌")
        - Auto Mode UI: \(showAutoModeUI ? "✅" : "❌")
        - Auto Mode Settings: \(enableAutoModeSettings ? "✅" : "❌")
        - Experimental: \(enableExperimentalFeatures ? "✅" : "❌")
        """
    }
}
