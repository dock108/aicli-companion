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
    
    // MARK: - Enhanced Auto-Response System
    
    /// Enable/disable enhanced auto response system
    /// When false: auto response controls and logic are disabled
    /// When true: auto response system with 5 modes is available
    static let isAutoResponseEnabled: Bool = true
    
    /// Show/hide auto response UI controls in chat
    /// When false: auto response controls are hidden from chat view
    /// When true: auto response controls and status bar are visible
    static let showAutoResponseUI: Bool = true
    
    /// Enable/disable auto response settings interface
    /// When false: auto response settings are hidden from settings screens
    /// When true: comprehensive auto response settings are visible and functional
    static let enableAutoResponseSettings: Bool = true
    
    /// Enable/disable AI-powered responses
    /// When false: only template-based responses are used
    /// When true: OpenAI integration for intelligent responses is available
    static let enableAIResponses: Bool = false
    
    /// Show/hide training data collection features
    /// When false: training data collection is disabled
    /// When true: system learns from successful interactions
    static let enableTrainingDataCollection: Bool = true
    
    // MARK: - Workspace Mode Features
    
    /// Show Planning Validation tool in workspace mode
    /// When true: Planning validation tool is visible
    /// When false: Planning validation tool is hidden
    static let showPlanningValidation: Bool = false
    
    /// Show New Project tool in workspace mode
    /// When true: New Project tool is visible
    /// When false: New Project tool is hidden
    static let showProjectCreation: Bool = false
    
    /// Show Code Review tool in workspace mode
    /// When true: Code Review tool is visible
    /// When false: Code Review tool is hidden
    static let showCodeReview: Bool = false
    
    /// Show Refactor Assistant in workspace mode
    /// When true: Refactor Assistant is visible
    /// When false: Refactor Assistant is hidden
    static let showRefactorAssistant: Bool = false
    
    // MARK: - Chat Mode Features
    
    /// Show Code mode in chat mode selector
    /// When true: Code mode is available in chat
    /// When false: Code mode is hidden from selector
    static let showCodeMode: Bool = false
    
    /// Show Planning mode in chat mode selector
    /// When true: Planning mode is available in chat
    /// When false: Planning mode is hidden from selector
    static let showPlanningMode: Bool = true
    
    /// Show Normal mode in chat mode selector
    /// When true: Normal mode is available in chat
    /// When false: Normal mode is hidden from selector
    static let showNormalMode: Bool = true
    
    // MARK: - CloudKit & Sync Features
    
    /// Enable/disable CloudKit conversation sync
    /// When false: conversations are stored locally only
    /// When true: conversations sync across all user devices via iCloud
    static let enableCloudKitSync: Bool = true
    
    /// Enable/disable CloudKit settings sync
    /// When false: settings are stored locally only
    /// When true: auto-response and app settings sync via iCloud
    static let enableCloudKitSettingsSync: Bool = true
    
    /// Show/hide sync status indicators
    /// When false: sync status is hidden from UI
    /// When true: sync indicators and status are visible
    static let showSyncStatusUI: Bool = true
    
    // MARK: - UI Features
    
    /// Enable/disable attachment functionality in chat
    /// When true: Attachment button and picker are available
    /// When false: Attachment feature is completely hidden
    static let enableAttachments: Bool = false
    
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
    
    /// Check if auto response system should be active
    static var shouldUseAutoResponse: Bool {
        return isAutoResponseEnabled && enableAutoResponseSettings
    }
    
    /// Check if CloudKit sync should be active
    static var shouldUseCloudKitSync: Bool {
        return enableCloudKitSync
    }
    
    /// Check if AI responses should be available
    static var shouldUseAIResponses: Bool {
        return isAutoResponseEnabled && enableAIResponses
    }
}

// MARK: - Feature Flag Extensions

@available(iOS 16.0, macOS 13.0, *)
extension FeatureFlags {
    /// Get a summary of current feature flag states
    static var summary: String {
        return """
        FeatureFlags Summary:
        
        Chat Modes:
        - Normal Mode: \(showNormalMode ? "✅" : "❌")
        - Planning Mode: \(showPlanningMode ? "✅" : "❌")
        - Code Mode: \(showCodeMode ? "✅" : "❌")
        
        Enhanced Auto-Response System:
        - Auto Response Enabled: \(isAutoResponseEnabled ? "✅" : "❌")
        - Auto Response UI: \(showAutoResponseUI ? "✅" : "❌")
        - Auto Response Settings: \(enableAutoResponseSettings ? "✅" : "❌")
        - AI Responses: \(enableAIResponses ? "✅" : "❌")
        - Training Data Collection: \(enableTrainingDataCollection ? "✅" : "❌")
        
        CloudKit & Sync:
        - CloudKit Conversation Sync: \(enableCloudKitSync ? "✅" : "❌")
        - CloudKit Settings Sync: \(enableCloudKitSettingsSync ? "✅" : "❌")
        - Sync Status UI: \(showSyncStatusUI ? "✅" : "❌")
        
        Workspace Tools:
        - New Project: \(showProjectCreation ? "✅" : "❌")
        - Planning Validation: \(showPlanningValidation ? "✅" : "❌")
        - Code Review: \(showCodeReview ? "✅" : "❌")
        - Refactor Assistant: \(showRefactorAssistant ? "✅" : "❌")
        
        UI Features:
        - Attachments: \(enableAttachments ? "✅" : "❌")
        
        System Features:
        - Queue System: \(isQueueSystemEnabled ? "✅" : "❌")
        - Queue UI: \(showQueueUI ? "✅" : "❌")
        - Queue Processing: \(enableQueueProcessing ? "✅" : "❌")
        - Experimental: \(enableExperimentalFeatures ? "✅" : "❌")
        """
    }
}
