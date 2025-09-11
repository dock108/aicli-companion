import Foundation
import CloudKit
import Combine
import SwiftUI

@available(iOS 16.0, macOS 13.0, *)
@MainActor
public class AutoReplySettingsStore: ObservableObject {
    public static let shared = AutoReplySettingsStore()
    
    // MARK: - Published Properties
    
    @Published public var settings: [UUID: AutoReplySettings] = [:]
    @Published public var isLoading: Bool = false
    @Published public var lastError: AutoReplyError?
    @Published public var syncStatus: AutoReplySyncStatus = .idle
    
    // MARK: - Private Properties
    
    private let container = CKContainer.default()
    private lazy var database = container.publicCloudDatabase
    private var cancellables = Set<AnyCancellable>()
    
    // Local storage keys
    private let localStorageKey = "AutoReplySettings"
    private let lastSyncKey = "AutoReplySettingsLastSync"
    
    // MARK: - Initialization
    
    private init() {
        loadLocalSettings()
        setupSyncTimer()
    }
    
    // MARK: - Public Methods
    
    /// Get settings for a specific project
    public func settings(for projectId: UUID) -> AutoReplySettings? {
        return settings[projectId]
    }
    
    /// Get or create settings for a project
    public func getOrCreateSettings(for projectId: UUID, projectName: String) -> AutoReplySettings {
        if let existing = settings[projectId] {
            return existing
        }
        
        let newSettings = AutoReplySettings(projectId: projectId, projectName: projectName)
        settings[projectId] = newSettings
        
        // Save immediately
        Task {
            await saveSettings(newSettings)
        }
        
        return newSettings
    }
    
    /// Update settings for a project
    public func updateSettings(_ newSettings: AutoReplySettings) {
        var updatedSettings = newSettings
        updatedSettings.lastModified = Date()
        updatedSettings.version += 1
        
        settings[newSettings.projectId] = updatedSettings
        
        // Save locally and sync
        saveLocalSettings()
        Task {
            await saveSettings(updatedSettings)
        }
    }
    
    /// Delete settings for a project
    public func deleteSettings(for projectId: UUID) {
        guard let settingsToDelete = settings[projectId] else { return }
        
        settings.removeValue(forKey: projectId)
        saveLocalSettings()
        
        Task {
            await deleteSettings(settingsToDelete)
        }
    }
    
    /// Get all project settings
    public func getAllSettings() -> [AutoReplySettings] {
        return Array(settings.values).sorted { $0.projectName < $1.projectName }
    }
    
    /// Sync with CloudKit
    public func syncWithCloudKit() async {
        guard syncStatus != .syncing else { return }
        
        await MainActor.run {
            syncStatus = .syncing
            isLoading = true
        }
        
        do {
            // Fetch remote settings
            let remoteSettings = try await fetchAllSettings()
            
            await MainActor.run {
                // Merge with local settings
                mergeSettings(remoteSettings)
                saveLocalSettings()
                
                syncStatus = .completed
                isLoading = false
                UserDefaults.standard.set(Date(), forKey: lastSyncKey)
            }
        } catch {
            await MainActor.run {
                lastError = error as? AutoReplyError ?? .syncFailed
                syncStatus = .failed
                isLoading = false
            }
        }
    }
    
    /// Import settings from JSON
    public func importSettings(_ data: Data) throws {
        let importedSettings = try JSONDecoder().decode([AutoReplySettings].self, from: data)
        
        for setting in importedSettings {
            settings[setting.projectId] = setting
        }
        
        saveLocalSettings()
        
        // Sync to CloudKit
        Task {
            for setting in importedSettings {
                await saveSettings(setting)
            }
        }
    }
    
    /// Export settings to JSON
    public func exportSettings() throws -> Data {
        let allSettings = getAllSettings()
        return try JSONEncoder().encode(allSettings)
    }
    
    /// Reset all settings
    public func resetAllSettings() {
        settings.removeAll()
        saveLocalSettings()
        
        Task {
            await deleteAllSettings()
        }
    }
    
    // MARK: - Private Methods
    
    private func loadLocalSettings() {
        guard let data = UserDefaults.standard.data(forKey: localStorageKey) else { return }
        
        do {
            let settingsArray = try JSONDecoder().decode([AutoReplySettings].self, from: data)
            self.settings = Dictionary(uniqueKeysWithValues: settingsArray.map { ($0.projectId, $0) })
        } catch {
            // Failed to load local settings
        }
    }
    
    private func saveLocalSettings() {
        do {
            let settingsArray = Array(settings.values)
            let data = try JSONEncoder().encode(settingsArray)
            UserDefaults.standard.set(data, forKey: localStorageKey)
        } catch {
            // Failed to save local settings
        }
    }
    
    private func setupSyncTimer() {
        // Auto-sync every 5 minutes if needed
        Timer.publish(every: 300, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task {
                    await self?.autoSyncIfNeeded()
                }
            }
            .store(in: &cancellables)
    }
    
    private func autoSyncIfNeeded() async {
        let lastSync = UserDefaults.standard.object(forKey: lastSyncKey) as? Date
        let needsSync = lastSync == nil || Date().timeIntervalSince(lastSync!) > 300 // 5 minutes
        
        if needsSync && syncStatus == .idle {
            await syncWithCloudKit()
        }
    }
    
    private func mergeSettings(_ remoteSettings: [AutoReplySettings]) {
        for remoteSetting in remoteSettings {
            if let localSetting = settings[remoteSetting.projectId] {
                // Keep the more recent version
                if remoteSetting.lastModified > localSetting.lastModified {
                    settings[remoteSetting.projectId] = remoteSetting
                }
            } else {
                // Add new remote setting
                settings[remoteSetting.projectId] = remoteSetting
            }
        }
    }
    
    // MARK: - CloudKit Operations
    
    private func saveSettings(_ settings: AutoReplySettings) async {
        do {
            let record = settings.toCKRecord()
            _ = try await database.save(record)
        } catch {
            await MainActor.run {
                lastError = .syncFailed
            }
        }
    }
    
    private func deleteSettings(_ settings: AutoReplySettings) async {
        do {
            let recordID = CKRecord.ID(recordName: settings.id.uuidString)
            _ = try await database.deleteRecord(withID: recordID)
        } catch {
            await MainActor.run {
                lastError = .syncFailed
            }
        }
    }
    
    private func fetchAllSettings() async throws -> [AutoReplySettings] {
        let query = CKQuery(recordType: "AutoReplySettings", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "lastModified", ascending: false)]
        
        let (matchResults, _) = try await database.records(matching: query)
        
        var settings: [AutoReplySettings] = []
        
        for (_, result) in matchResults {
            switch result {
            case .success(let record):
                if let setting = try? AutoReplySettings.from(ckRecord: record) {
                    settings.append(setting)
                }
            case .failure(_):
                // Failed to fetch setting - silently continue
                break
            }
        }
        
        return settings
    }
    
    private func deleteAllSettings() async {
        do {
            let query = CKQuery(recordType: "AutoReplySettings", predicate: NSPredicate(value: true))
            let (matchResults, _) = try await database.records(matching: query)
            
            let recordIDs = matchResults.compactMap { _, result -> CKRecord.ID? in
                switch result {
                case .success(let record):
                    return record.recordID
                case .failure:
                    return nil
                }
            }
            
            for recordID in recordIDs {
                try await database.deleteRecord(withID: recordID)
            }
        } catch {
            await MainActor.run {
                lastError = .syncFailed
            }
        }
    }
    
    // MARK: - CloudKit Account Status
    
    public func checkCloudKitStatus() async -> CKAccountStatus {
        do {
            return try await container.accountStatus()
        } catch {
            return .noAccount
        }
    }
    
    public func requestCloudKitPermissions() async -> Bool {
        do {
            let status = try await container.requestApplicationPermission(.userDiscoverability)
            return status == .granted
        } catch {
            return false
        }
    }
}

// MARK: - Supporting Types

@available(iOS 16.0, macOS 13.0, *)
public enum AutoReplySyncStatus: Equatable {
    case idle
    case syncing
    case completed
    case failed
    
    public var displayName: String {
        switch self {
        case .idle: return "Ready"
        case .syncing: return "Syncing..."
        case .completed: return "Synced"
        case .failed: return "Sync Failed"
        }
    }
    
    public var color: Color {
        switch self {
        case .idle: return .primary
        case .syncing: return .blue
        case .completed: return .green
        case .failed: return .red
        }
    }
}

// MARK: - Convenience Extensions

@available(iOS 16.0, macOS 13.0, *)
extension AutoReplySettingsStore {
    /// Quick check if auto-reply is enabled for a project
    public func isAutoReplyEnabled(for projectId: UUID) -> Bool {
        return settings[projectId]?.isEnabled ?? false
    }
    
    /// Get the current mode for a project
    public func getMode(for projectId: UUID) -> AutoReplyMode {
        return settings[projectId]?.mode ?? .smartStop
    }
    
    /// Get default settings template
    public func getDefaultSettings(for projectId: UUID, projectName: String) -> AutoReplySettings {
        var settings = AutoReplySettings(projectId: projectId, projectName: projectName)
        
        // Set sensible defaults
        settings.mode = .smartStop
        settings.useAI = true
        settings.minConfidence = 0.7
        settings.smartStopSettings.stopOnErrors = true
        settings.smartStopSettings.stopOnCompletion = true
        settings.smartStopSettings.maxLoopAttempts = 5
        settings.timeLimits.minutes = 30
        settings.messageLimits.maxMessages = 20
        settings.allowOverride = true
        settings.notifyOnStop = true
        settings.saveHistory = true
        settings.learningEnabled = true
        
        return settings
    }
    
    /// Create quick settings for common scenarios
    public func createQuickSettings(
        for projectId: UUID,
        projectName: String,
        scenario: QuickSettingsScenario
    ) -> AutoReplySettings {
        var settings = getDefaultSettings(for: projectId, projectName: projectName)
        
        switch scenario {
        case .quickTask:
            settings.mode = .messageBased
            settings.messageLimits.enabled = true
            settings.messageLimits.maxMessages = 10
            
        case .debugging:
            settings.mode = .smartStop
            settings.smartStopSettings.stuckDetectionSensitivity = 2
            settings.smartStopSettings.maxLoopAttempts = 10
            settings.minConfidence = 0.6
            
        case .longRunning:
            settings.mode = .hybrid
            settings.hybridSettings.enableTimeLimit = true
            settings.hybridSettings.enableMessageLimit = true
            settings.timeLimits.enabled = true
            settings.timeLimits.minutes = 120
            settings.messageLimits.enabled = true
            settings.messageLimits.maxMessages = 50
            
        case .untilDone:
            settings.mode = .untilCompletion
            settings.smartStopSettings.requireExplicitCompletion = true
            settings.timeLimits.enabled = true
            settings.timeLimits.minutes = 240 // 4 hour safety limit
        }
        
        return settings
    }
}

@available(iOS 16.0, macOS 13.0, *)
public enum QuickSettingsScenario: String, CaseIterable {
    case quickTask = "quick_task"
    case debugging = "debugging"
    case longRunning = "long_running"
    case untilDone = "until_done"
    
    public var displayName: String {
        switch self {
        case .quickTask: return "Quick Task"
        case .debugging: return "Debugging Session"
        case .longRunning: return "Long Running Task"
        case .untilDone: return "Until Complete"
        }
    }
    
    public var description: String {
        switch self {
        case .quickTask: return "Short task with message limit"
        case .debugging: return "Debug session with error tolerance"
        case .longRunning: return "Extended work with multiple limits"
        case .untilDone: return "Work until explicitly complete"
        }
    }
    
    public var icon: String {
        switch self {
        case .quickTask: return "bolt.fill"
        case .debugging: return "ant.fill"
        case .longRunning: return "hourglass"
        case .untilDone: return "flag.checkered"
        }
    }
}
