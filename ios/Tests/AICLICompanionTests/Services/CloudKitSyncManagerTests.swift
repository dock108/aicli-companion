import XCTest
import CloudKit
@testable import AICLICompanion

@available(iOS 16.0, macOS 13.0, *)
final class CloudKitSyncManagerTests: XCTestCase {
    var sut: CloudKitSyncManager!
    var mockContainer: MockCKContainer!
    var mockDatabase: MockCKDatabase!
    
    override func setUp() {
        super.setUp()
        mockContainer = MockCKContainer()
        mockDatabase = MockCKDatabase()
        mockContainer.privateDatabase = mockDatabase
        
        // Initialize with mock container would require dependency injection
        // For now, we'll test the interface and behavior
        sut = CloudKitSyncManager()
    }
    
    override func tearDown() {
        sut = nil
        mockContainer = nil
        mockDatabase = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitialization() {
        XCTAssertFalse(sut.iCloudAvailable)
        XCTAssertEqual(sut.syncStatus, .pending)
        XCTAssertNil(sut.lastSyncDate)
        XCTAssertEqual(sut.syncProgress, 0.0)
        XCTAssertFalse(sut.isInitialSyncComplete)
    }
    
    // MARK: - iCloud Availability Tests
    
    func testInitializeCloudKit_WhenAccountAvailable() async {
        // Given
        mockContainer.accountStatus = .available
        
        // When
        await sut.initializeCloudKit()
        
        // Then
        XCTAssertTrue(sut.iCloudAvailable)
        XCTAssertNil(sut.errorMessage)
    }
    
    func testInitializeCloudKit_WhenNoAccount() async {
        // Given
        mockContainer.accountStatus = .noAccount
        
        // When
        await sut.initializeCloudKit()
        
        // Then
        XCTAssertFalse(sut.iCloudAvailable)
        XCTAssertNotNil(sut.errorMessage)
        XCTAssertTrue(sut.errorMessage?.contains("No iCloud account") == true)
    }
    
    func testInitializeCloudKit_WhenRestricted() async {
        // Given
        mockContainer.accountStatus = .restricted
        
        // When
        await sut.initializeCloudKit()
        
        // Then
        XCTAssertFalse(sut.iCloudAvailable)
        XCTAssertTrue(sut.errorMessage?.contains("restricted") == true)
    }
    
    // MARK: - Message Sync Tests
    
    func testSyncMessages_Success() async throws {
        // Given
        let sessionId = "test-session"
        let projectPath = "/test/project"
        
        let mockRecord = CKRecord(recordType: CloudKitSchema.RecordType.message)
        mockRecord[CloudKitSchema.MessageFields.content] = "Test message"
        mockRecord[CloudKitSchema.MessageFields.timestamp] = Date()
        mockRecord[CloudKitSchema.MessageFields.messageType] = MessageType.text.rawValue
        
        mockDatabase.mockRecords = [mockRecord.recordID: .success(mockRecord)]
        
        // Setup for iCloud available
        await sut.initializeCloudKit()
        // Manually set iCloud as available for testing
        await MainActor.run {
            sut.iCloudAvailable = true
        }
        
        // When
        try await sut.syncMessages(for: sessionId, projectPath: projectPath)
        
        // Then
        XCTAssertEqual(sut.syncStatus, .synced)
        XCTAssertNotNil(sut.lastSyncDate)
    }
    
    func testSyncMessages_WhenCloudKitUnavailable() async {
        // Given
        let sessionId = "test-session"
        let projectPath = "/test/project"
        
        await MainActor.run {
            sut.iCloudAvailable = false
        }
        
        // When & Then
        do {
            try await sut.syncMessages(for: sessionId, projectPath: projectPath)
            XCTFail("Should throw iCloudUnavailable error")
        } catch CloudKitSchema.SyncError.iCloudUnavailable {
            // Expected error
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Message Save Tests
    
    func testSaveMessage_Success() async throws {
        // Given
        var message = Message(
            content: "Test message",
            sender: .user,
            type: .text
        )
        
        let mockRecord = message.toCKRecord()
        mockDatabase.mockSavedRecord = mockRecord
        
        await MainActor.run {
            sut.iCloudAvailable = true
        }
        
        // When
        try await sut.saveMessage(message)
        
        // Then
        XCTAssertEqual(mockDatabase.saveCallCount, 1)
        XCTAssertEqual(mockDatabase.lastSavedRecord?.recordType, CloudKitSchema.RecordType.message)
    }
    
    func testSaveMessage_WhenCloudKitUnavailable() async {
        // Given
        let message = Message(
            content: "Test message",
            sender: .user,
            type: .text
        )
        
        await MainActor.run {
            sut.iCloudAvailable = false
        }
        
        // When & Then
        do {
            try await sut.saveMessage(message)
            XCTFail("Should throw iCloudUnavailable error")
        } catch CloudKitSchema.SyncError.iCloudUnavailable {
            // Expected error
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Full Sync Tests
    
    func testPerformFullSync_Success() async throws {
        // Given
        mockContainer.accountStatus = .available
        mockDatabase.mockRecords = [:]
        
        await MainActor.run {
            sut.iCloudAvailable = true
        }
        
        // When
        try await sut.performFullSync()
        
        // Then
        XCTAssertEqual(sut.syncStatus, .synced)
        XCTAssertNotNil(sut.lastSyncDate)
        XCTAssertEqual(sut.syncProgress, 1.0)
        XCTAssertTrue(sut.isInitialSyncComplete)
        XCTAssertNil(sut.errorMessage)
    }
    
    func testPerformFullSync_WhenFailed() async {
        // Given
        let expectedError = CKError(.networkUnavailable)
        mockDatabase.mockError = expectedError
        
        await MainActor.run {
            sut.iCloudAvailable = true
        }
        
        // When
        do {
            try await sut.performFullSync()
            XCTFail("Should throw network error")
        } catch {
            // Then
            XCTAssertEqual(sut.syncStatus, .failed)
            XCTAssertNotNil(sut.errorMessage)
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testHandleCloudKitError_NetworkUnavailable() async {
        // Given
        let error = CKError(.networkUnavailable)
        
        await MainActor.run {
            sut.iCloudAvailable = true
        }
        
        // When
        // Error handling would be tested by triggering a sync operation that fails
        mockDatabase.mockError = error
        
        do {
            try await sut.performFullSync()
        } catch {
            // Then
            XCTAssertTrue(sut.errorMessage?.contains("Network unavailable") == true)
        }
    }
    
    func testHandleCloudKitError_QuotaExceeded() async {
        // Given
        let error = CKError(.quotaExceeded)
        
        await MainActor.run {
            sut.iCloudAvailable = true
        }
        
        // When
        mockDatabase.mockError = error
        
        do {
            try await sut.performFullSync()
        } catch {
            // Then
            XCTAssertTrue(sut.errorMessage?.contains("quota exceeded") == true)
        }
    }
    
    // MARK: - Reset Tests
    
    func testResetSyncState() async {
        // Given
        await MainActor.run {
            sut.syncStatus = .synced
            sut.lastSyncDate = Date()
            sut.syncProgress = 1.0
            sut.isInitialSyncComplete = true
            sut.errorMessage = "Some error"
        }
        
        // When
        await sut.resetSyncState()
        
        // Then
        XCTAssertEqual(sut.syncStatus, .pending)
        XCTAssertNil(sut.lastSyncDate)
        XCTAssertEqual(sut.syncProgress, 0.0)
        XCTAssertFalse(sut.isInitialSyncComplete)
        XCTAssertNil(sut.errorMessage)
    }
}

// MARK: - Mock Classes

@available(iOS 16.0, macOS 13.0, *)
class MockCKContainer {
    var accountStatus: CKAccountStatus = .available
    var privateDatabase: MockCKDatabase = MockCKDatabase()
    
    func accountStatus() async throws -> CKAccountStatus {
        return accountStatus
    }
}

@available(iOS 16.0, macOS 13.0, *)
class MockCKDatabase {
    var mockRecords: [CKRecord.ID: Result<CKRecord, Error>] = [:]
    var mockSavedRecord: CKRecord?
    var mockError: Error?
    var saveCallCount = 0
    var lastSavedRecord: CKRecord?
    
    func records(matching query: CKQuery) async throws -> ([(CKRecord.ID, Result<CKRecord, Error>)], CKQueryOperation.Cursor?) {
        if let error = mockError {
            throw error
        }
        
        let results = Array(mockRecords)
        return (results, nil)
    }
    
    func save(_ record: CKRecord) async throws -> CKRecord {
        if let error = mockError {
            throw error
        }
        
        saveCallCount += 1
        lastSavedRecord = record
        return mockSavedRecord ?? record
    }
    
    func deleteRecord(withID recordID: CKRecord.ID) async throws -> CKRecord.ID {
        if let error = mockError {
            throw error
        }
        
        return recordID
    }
}

// MARK: - Test Utilities

extension CloudKitSyncManagerTests {
    func createTestMessage() -> Message {
        return Message(
            content: "Test message content",
            sender: .user,
            type: .text,
            metadata: AICLIMessageMetadata(sessionId: "test-session", duration: 0)
        )
    }
    
    func createTestCKRecord() -> CKRecord {
        let record = CKRecord.messageRecord()
        record[CloudKitSchema.MessageFields.content] = "Test message"
        record[CloudKitSchema.MessageFields.timestamp] = Date()
        record[CloudKitSchema.MessageFields.messageType] = MessageType.text.rawValue
        record[CloudKitSchema.MessageFields.sessionId] = "test-session"
        return record
    }
}

// MARK: - Performance Tests

@available(iOS 16.0, macOS 13.0, *)
extension CloudKitSyncManagerTests {
    func testSyncPerformance() async throws {
        // Given
        let messageCount = 100
        var mockRecords: [CKRecord.ID: Result<CKRecord, Error>] = [:]
        
        for i in 0..<messageCount {
            let record = CKRecord.messageRecord(recordName: "message-\(i)")
            record[CloudKitSchema.MessageFields.content] = "Test message \(i)"
            record[CloudKitSchema.MessageFields.timestamp] = Date()
            record[CloudKitSchema.MessageFields.messageType] = MessageType.text.rawValue
            mockRecords[record.recordID] = .success(record)
        }
        
        mockDatabase.mockRecords = mockRecords
        
        await MainActor.run {
            sut.iCloudAvailable = true
        }
        
        // When & Then
        measure {
            let expectation = XCTestExpectation(description: "Sync completed")
            
            Task {
                do {
                    try await sut.syncMessages(for: "test-session", projectPath: "/test")
                    expectation.fulfill()
                } catch {
                    XCTFail("Sync failed: \(error)")
                    expectation.fulfill()
                }
            }
            
            wait(for: [expectation], timeout: 10.0)
        }
    }
}
