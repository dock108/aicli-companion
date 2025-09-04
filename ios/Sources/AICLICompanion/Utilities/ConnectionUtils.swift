//
//  ConnectionUtils.swift
//  AICLICompanion
//
//  Utility functions for connection management to avoid duplication
//

import Foundation

/// Utility functions for connection management
/// Eliminates duplicate connection checking logic across views
public enum ConnectionUtils {
    
    /// Check if there is a valid connection using SettingsManager
    /// - Parameter settings: The settings manager to check
    /// - Returns: True if connection settings are valid
    public static func checkConnection(with settings: SettingsManager) -> Bool {
        return settings.hasValidConnection()
    }
    
    /// Disconnect from server and clear settings
    /// - Parameter settings: The settings manager to update
    public static func disconnectFromServer(settings: SettingsManager) {
        settings.clearConnection()
    }
    
    /// Get connection status with additional details
    /// - Parameter settings: The settings manager to check
    /// - Returns: A tuple containing connection status and any error message
    public static func getConnectionStatus(with settings: SettingsManager) -> (isConnected: Bool, errorMessage: String?) {
        let connected = settings.hasValidConnection()
        
        if !connected {
            return (false, "Connection settings incomplete")
        }
        
        return (true, nil)
    }
    
    /// Validate connection settings without updating UI
    /// - Parameter settings: The settings manager to validate
    /// - Returns: True if connection settings are valid
    public static func validateConnectionSettings(with settings: SettingsManager) -> Bool {
        return settings.hasValidConnection()
    }
}