//
//  KeychainManagerTests.swift
//  AICLICompanionHostTests
//
//  Unit tests for KeychainManager
//

import XCTest
@testable import AICLICompanionHost

final class KeychainManagerTests: XCTestCase {
    var mockKeychainManager: MockKeychainManager!

    override func setUp() {
        super.setUp()
        mockKeychainManager = MockKeychainManager()
    }

    override func tearDown() {
        mockKeychainManager.reset()
        mockKeychainManager = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testKeychainManagerSingleton() throws {
        let manager1 = MockKeychainManager.shared
        let manager2 = MockKeychainManager.shared

        // Should be the same instance
        XCTAssertTrue(manager1 === manager2)
    }

    // MARK: - Auth Token Tests

    func testSaveAuthToken() throws {
        let token = "test-auth-token-123"

        let success = mockKeychainManager.saveAuthToken(token)

        XCTAssertTrue(success)
        XCTAssertTrue(mockKeychainManager.saveAuthTokenCalled)
        XCTAssertEqual(mockKeychainManager.saveAuthTokenCallCount, 1)

        // Verify token was saved
        let loadedToken = mockKeychainManager.loadAuthToken()
        XCTAssertEqual(loadedToken, token)
    }

    func testSaveAuthTokenFailure() throws {
        mockKeychainManager.saveAuthTokenShouldFail = true

        let success = mockKeychainManager.saveAuthToken("token")

        XCTAssertFalse(success)
        XCTAssertTrue(mockKeychainManager.saveAuthTokenCalled)
    }

    func testLoadAuthTokenWhenExists() throws {
        // Pre-set a token
        mockKeychainManager.setAuthToken("existing-token")

        let token = mockKeychainManager.loadAuthToken()

        XCTAssertEqual(token, "existing-token")
        XCTAssertTrue(mockKeychainManager.loadAuthTokenCalled)
        XCTAssertEqual(mockKeychainManager.loadAuthTokenCallCount, 1)
    }

    func testLoadAuthTokenWhenNotExists() throws {
        let token = mockKeychainManager.loadAuthToken()

        XCTAssertNil(token)
        XCTAssertTrue(mockKeychainManager.loadAuthTokenCalled)
    }

    func testLoadAuthTokenReturnsNil() throws {
        // Set token but configure to return nil
        mockKeychainManager.setAuthToken("token")
        mockKeychainManager.loadAuthTokenShouldReturnNil = true

        let token = mockKeychainManager.loadAuthToken()

        XCTAssertNil(token)
        XCTAssertTrue(mockKeychainManager.loadAuthTokenCalled)
    }

    func testDeleteAuthToken() throws {
        // Save a token first
        mockKeychainManager.setAuthToken("token-to-delete")

        // Verify it exists
        XCTAssertNotNil(mockKeychainManager.loadAuthToken())

        // Delete it
        let success = mockKeychainManager.deleteAuthToken()

        XCTAssertTrue(success)
        XCTAssertTrue(mockKeychainManager.deleteAuthTokenCalled)
        XCTAssertEqual(mockKeychainManager.deleteAuthTokenCallCount, 1)

        // Verify it's deleted
        mockKeychainManager.loadAuthTokenCalled = false
        XCTAssertNil(mockKeychainManager.loadAuthToken())
    }

    func testDeleteAuthTokenWhenNotExists() throws {
        // Delete when no token exists
        let success = mockKeychainManager.deleteAuthToken()

        XCTAssertTrue(success) // Should still return success
        XCTAssertTrue(mockKeychainManager.deleteAuthTokenCalled)
    }

    // MARK: - Generic Key-Value Tests

    func testSaveAndLoadGenericKey() throws {
        let key = "test-key"
        let value = "test-value"

        let saveSuccess = mockKeychainManager.save(key: key, value: value)
        XCTAssertTrue(saveSuccess)

        let loadedValue = mockKeychainManager.load(key: key)
        XCTAssertEqual(loadedValue, value)
    }

    func testLoadNonExistentKey() throws {
        let value = mockKeychainManager.load(key: "non-existent")
        XCTAssertNil(value)
    }

    func testDeleteGenericKey() throws {
        let key = "key-to-delete"
        let value = "value"

        // Save first
        _ = mockKeychainManager.save(key: key, value: value)
        XCTAssertNotNil(mockKeychainManager.load(key: key))

        // Delete
        let success = mockKeychainManager.delete(key: key)
        XCTAssertTrue(success)

        // Verify deleted
        XCTAssertNil(mockKeychainManager.load(key: key))
    }

    func testDeleteNonExistentKey() throws {
        let success = mockKeychainManager.delete(key: "non-existent")
        XCTAssertTrue(success) // Should still return success
    }

    // MARK: - Multiple Keys Tests

    func testMultipleKeysStorage() throws {
        // Save multiple keys
        _ = mockKeychainManager.save(key: "key1", value: "value1")
        _ = mockKeychainManager.save(key: "key2", value: "value2")
        _ = mockKeychainManager.save(key: "key3", value: "value3")

        // Load them back
        XCTAssertEqual(mockKeychainManager.load(key: "key1"), "value1")
        XCTAssertEqual(mockKeychainManager.load(key: "key2"), "value2")
        XCTAssertEqual(mockKeychainManager.load(key: "key3"), "value3")

        // Delete one
        _ = mockKeychainManager.delete(key: "key2")

        // Verify others still exist
        XCTAssertEqual(mockKeychainManager.load(key: "key1"), "value1")
        XCTAssertNil(mockKeychainManager.load(key: "key2"))
        XCTAssertEqual(mockKeychainManager.load(key: "key3"), "value3")
    }

    func testOverwriteExistingKey() throws {
        let key = "overwrite-key"

        // Save initial value
        _ = mockKeychainManager.save(key: key, value: "initial")
        XCTAssertEqual(mockKeychainManager.load(key: key), "initial")

        // Overwrite with new value
        _ = mockKeychainManager.save(key: key, value: "updated")
        XCTAssertEqual(mockKeychainManager.load(key: key), "updated")
    }

    // MARK: - Test Helper Methods

    func testGetAllStoredData() throws {
        // Save some data
        _ = mockKeychainManager.save(key: "key1", value: "value1")
        _ = mockKeychainManager.save(key: "key2", value: "value2")
        mockKeychainManager.setAuthToken("auth-token")

        let allData = mockKeychainManager.getAllStoredData()

        XCTAssertEqual(allData.count, 3)
        XCTAssertEqual(allData["key1"] as? String, "value1")
        XCTAssertEqual(allData["key2"] as? String, "value2")
        XCTAssertEqual(allData["authToken"] as? String, "auth-token")
    }

    func testResetClearsAllData() throws {
        // Save some data
        mockKeychainManager.setAuthToken("token")
        _ = mockKeychainManager.save(key: "key1", value: "value1")
        _ = mockKeychainManager.save(key: "key2", value: "value2")

        // Set tracking flags
        _ = mockKeychainManager.saveAuthToken("test")
        _ = mockKeychainManager.loadAuthToken()
        _ = mockKeychainManager.deleteAuthToken()

        // Verify data exists
        XCTAssertFalse(mockKeychainManager.getAllStoredData().isEmpty)
        XCTAssertTrue(mockKeychainManager.saveAuthTokenCalled)
        XCTAssertTrue(mockKeychainManager.loadAuthTokenCalled)
        XCTAssertTrue(mockKeychainManager.deleteAuthTokenCalled)

        // Reset
        mockKeychainManager.reset()

        // Verify all cleared
        XCTAssertTrue(mockKeychainManager.getAllStoredData().isEmpty)
        XCTAssertFalse(mockKeychainManager.saveAuthTokenCalled)
        XCTAssertFalse(mockKeychainManager.loadAuthTokenCalled)
        XCTAssertFalse(mockKeychainManager.deleteAuthTokenCalled)
        XCTAssertEqual(mockKeychainManager.saveAuthTokenCallCount, 0)
        XCTAssertEqual(mockKeychainManager.loadAuthTokenCallCount, 0)
        XCTAssertEqual(mockKeychainManager.deleteAuthTokenCallCount, 0)
        XCTAssertFalse(mockKeychainManager.loadAuthTokenShouldReturnNil)
        XCTAssertFalse(mockKeychainManager.saveAuthTokenShouldFail)
    }

    // MARK: - Call Count Tests

    func testCallCountTracking() throws {
        // Multiple saves
        _ = mockKeychainManager.saveAuthToken("token1")
        _ = mockKeychainManager.saveAuthToken("token2")
        _ = mockKeychainManager.saveAuthToken("token3")
        XCTAssertEqual(mockKeychainManager.saveAuthTokenCallCount, 3)

        // Multiple loads
        _ = mockKeychainManager.loadAuthToken()
        _ = mockKeychainManager.loadAuthToken()
        XCTAssertEqual(mockKeychainManager.loadAuthTokenCallCount, 2)

        // Multiple deletes
        _ = mockKeychainManager.deleteAuthToken()
        _ = mockKeychainManager.deleteAuthToken()
        _ = mockKeychainManager.deleteAuthToken()
        _ = mockKeychainManager.deleteAuthToken()
        XCTAssertEqual(mockKeychainManager.deleteAuthTokenCallCount, 4)
    }
}
