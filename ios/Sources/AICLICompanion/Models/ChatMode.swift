//
//  ChatMode.swift
//  AICLICompanion
//
//  Created by Assistant on 2025-09-04.
//

import Foundation
import SwiftUI

/// Represents different chat modes that control Claude's permissions
public enum ChatMode: String, CaseIterable, Codable {
    case normal
    case planning
    case code
    
    /// Display name for the mode
    public var displayName: String {
        switch self {
        case .normal:
            return "Normal"
        case .planning:
            return "Planning"
        case .code:
            return "Code"
        }
    }
    
    /// SF Symbol icon for the mode
    public var icon: String {
        switch self {
        case .normal:
            return "text.bubble"
        case .planning:
            return "doc.text"
        case .code:
            return "chevron.left.slash.chevron.right"
        }
    }
    
    /// Description of what the mode does
    public var description: String {
        switch self {
        case .normal:
            return "Full access to all operations"
        case .planning:
            return "Can only modify docs (*.md, *.txt, etc.)"
        case .code:
            return "Fast code generation mode"
        }
    }
    
    /// Short description for compact UI display
    public var shortDescription: String {
        switch self {
        case .normal:
            return "" // No badge for normal mode
        case .planning:
            return "📝 Docs Only"
        case .code:
            return "⚡ Fast Mode"
        }
    }
    
    /// Background color for the mode indicator
    public var backgroundColor: Color {
        switch self {
        case .normal:
            return Color.gray.opacity(0.1)
        case .planning:
            return Color.orange.opacity(0.2)
        case .code:
            return Color.blue.opacity(0.2)
        }
    }
    
    /// Foreground color for the mode indicator
    public var foregroundColor: Color {
        switch self {
        case .normal:
            return .primary
        case .planning:
            return .orange
        case .code:
            return .blue
        }
    }
    
    /// User-facing explanation when switching modes
    public var explanation: String {
        switch self {
        case .normal:
            return "Claude can read and modify any files"
        case .planning:
            return "Claude will only modify documentation files (*.md, *.txt, README, TODO, etc.) but can still read code"
        case .code:
            return "Faster responses with fewer permission prompts"
        }
    }
}

// MARK: - Visibility Control
@available(iOS 16.0, macOS 13.0, *)
extension ChatMode {
    /// Check if this mode should be visible in the app
    public var isVisibleInApp: Bool {
        switch self {
        case .normal:
            return FeatureFlags.showNormalMode
        case .planning:
            return FeatureFlags.showPlanningMode
        case .code:
            return FeatureFlags.showCodeMode
        }
    }
    
    /// Get only the modes that should be visible to users
    public static var visibleCases: [ChatMode] {
        return ChatMode.allCases.filter { $0.isVisibleInApp }
    }
}

// MARK: - UserDefaults Storage
extension ChatMode {
    private static let userDefaultsKey = "selectedChatMode"
    private static let perProjectPrefix = "chatMode_"
    
    /// Load the saved mode from UserDefaults (global fallback)
    public static func loadSavedMode() -> ChatMode {
        guard let rawValue = UserDefaults.standard.string(forKey: userDefaultsKey),
              let mode = ChatMode(rawValue: rawValue) else {
            return .normal
        }
        // If the saved mode is not visible, default to normal
        if #available(iOS 16.0, macOS 13.0, *) {
            if !mode.isVisibleInApp {
                return .normal
            }
        }
        return mode
    }
    
    /// Load the saved mode for a specific project
    public static func loadSavedMode(for projectPath: String) -> ChatMode {
        let key = "\(perProjectPrefix)\(projectPath.replacingOccurrences(of: "/", with: "_"))"
        
        // Try to load project-specific mode first
        if let rawValue = UserDefaults.standard.string(forKey: key),
           let mode = ChatMode(rawValue: rawValue) {
            // If the saved mode is not visible, default to normal
            if #available(iOS 16.0, macOS 13.0, *) {
                if !mode.isVisibleInApp {
                    return .normal
                }
            }
            return mode
        }
        
        // Fall back to global default or normal mode
        return loadSavedMode()
    }
    
    /// Save the mode to UserDefaults (global)
    public func save() {
        UserDefaults.standard.set(self.rawValue, forKey: ChatMode.userDefaultsKey)
    }
    
    /// Save the mode for a specific project
    public func save(for projectPath: String) {
        let key = "\(ChatMode.perProjectPrefix)\(projectPath.replacingOccurrences(of: "/", with: "_"))"
        UserDefaults.standard.set(self.rawValue, forKey: key)
        
        // Also update the global default for new projects
        save()
    }
    
    /// Clear saved mode for a project (useful when clearing chat)
    public static func clearSavedMode(for projectPath: String) {
        let key = "\(perProjectPrefix)\(projectPath.replacingOccurrences(of: "/", with: "_"))"
        UserDefaults.standard.removeObject(forKey: key)
    }
}
