//
//  SettingsDocument.swift
//  AICLICompanionHost
//
//  Document wrapper for exporting settings
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Settings Document
struct SettingsDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    @MainActor private let settingsData: Data

    @MainActor
    init(settingsManager: SettingsManager) {
        // Export settings data at initialization time on the main actor
        self.settingsData = settingsManager.exportSettings() ?? Data()
    }

    init(configuration: ReadConfiguration) throws {
        // This is export-only, so we don't support reading
        self.settingsData = Data()
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    nonisolated func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: settingsData)
    }
}
