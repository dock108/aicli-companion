//
//  DateFormatterUtility.swift
//  AICLICompanion
//
//  Centralized date formatter utility to avoid duplication
//

import Foundation

/// Centralized utility for common date formatters to avoid duplication across the codebase
public enum DateFormatterUtility {
    
    // MARK: - Common Formatters
    
    /// Short date and time formatter (e.g., "12/25/23, 2:30 PM")
    /// Used for: message timestamps, sync status display
    public static let shortDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
    
    /// Full date and medium time formatter (e.g., "Monday, December 25, 2023 at 2:30:45 PM")
    /// Used for: export files, detailed logging
    public static let exportFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .medium
        return formatter
    }()
    
    /// Time only formatter (e.g., "2:30 PM")
    /// Used for: inline time display where date is contextually known
    public static let timeOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
    
    /// ISO 8601 formatter for API communication and precise timestamps
    /// Used for: server communication, CloudKit sync timestamps
    public static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        return formatter
    }()
    
    /// Relative date formatter (e.g., "2 minutes ago", "Yesterday")
    /// Used for: human-readable relative timestamps
    public static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
    
    // MARK: - Convenience Methods
    
    /// Format date for message display (short date/time)
    public static func formatForMessage(_ date: Date) -> String {
        return shortDateTime.string(from: date)
    }
    
    /// Format date for export files
    public static func formatForExport(_ date: Date) -> String {
        return exportFormatter.string(from: date)
    }
    
    /// Format date as time only
    public static func formatTimeOnly(_ date: Date) -> String {
        return timeOnly.string(from: date)
    }
    
    /// Format date as relative time if recent, otherwise short format
    public static func formatSmart(_ date: Date) -> String {
        let timeInterval = abs(date.timeIntervalSinceNow)
        
        // Use relative format for dates within last 7 days
        if timeInterval < 7 * 24 * 60 * 60 {
            return relative.localizedString(for: date, relativeTo: Date())
        } else {
            return shortDateTime.string(from: date)
        }
    }
}