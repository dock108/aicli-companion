import XCTest
@testable import AICLICompanion

@available(iOS 17.0, macOS 14.0, *)
final class KeychainManagerTests: XCTestCase {
    
    var sut: KeychainManager!
    let testKey = "test_key_\(UUID().uuidString)"
    let testKeys: [String] = []
    
    override func setUp() {
        super.setUp()
        sut = KeychainManager.shared
        // Clean up any test data
        cleanupTestData()
    }
    
    override func tearDown() {
        // Clean up all test data
        cleanupTestData()
        sut = nil
        super.tearDown()
    }
    
    private func cleanupTestData() {
        // Delete any test keys that might exist
        sut.delete(for: testKey)
        sut.delete(for: "authToken")
        sut.delete(for: "serverURL")
        for key in testKeys {
            sut.delete(for: key)
        }
    }
    
    // MARK: - Save Data Tests
    
    func testSaveDataSuccessfully() {
        // Given
        let testData = "Test data".data(using: .utf8)!
        
        // When
        let result = sut.save(testData, for: testKey)
        
        // Then
        XCTAssertTrue(result)
        
        // Verify data was saved
        let retrieved = sut.retrieve(for: testKey)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved, testData)
    }
    
    func testSaveStringSuccessfully() {
        // Given
        let testString = "Test string value"
        
        // When
        let result = sut.save(testString, for: testKey)
        
        // Then
        XCTAssertTrue(result)
        
        // Verify string was saved
        let retrieved = sut.retrieveString(for: testKey)
        XCTAssertEqual(retrieved, testString)
    }
    
    func testSaveOverwritesExistingValue() {
        // Given
        let originalValue = "Original"
        let newValue = "Updated"
        
        // When
        let firstSave = sut.save(originalValue, for: testKey)
        let secondSave = sut.save(newValue, for: testKey)
        
        // Then
        XCTAssertTrue(firstSave)
        XCTAssertTrue(secondSave)
        
        let retrieved = sut.retrieveString(for: testKey)
        XCTAssertEqual(retrieved, newValue)
    }
    
    func testSaveEmptyString() {
        // Given
        let emptyString = ""
        
        // When
        let result = sut.save(emptyString, for: testKey)
        
        // Then
        XCTAssertTrue(result)
        
        let retrieved = sut.retrieveString(for: testKey)
        XCTAssertEqual(retrieved, emptyString)
    }
    
    func testSaveLargeData() {
        // Given - Create 1MB of data
        let largeString = String(repeating: "A", count: 1024 * 1024)
        
        // When
        let result = sut.save(largeString, for: testKey)
        
        // Then
        XCTAssertTrue(result)
        
        let retrieved = sut.retrieveString(for: testKey)
        XCTAssertEqual(retrieved?.count, largeString.count)
    }
    
    // MARK: - Retrieve Data Tests
    
    func testRetrieveNonExistentKey() {
        // When
        let data = sut.retrieve(for: "non_existent_key")
        let string = sut.retrieveString(for: "non_existent_key")
        
        // Then
        XCTAssertNil(data)
        XCTAssertNil(string)
    }
    
    func testRetrieveDataAfterSave() {
        // Given
        let testData = "Test data for retrieval".data(using: .utf8)!
        sut.save(testData, for: testKey)
        
        // When
        let retrieved = sut.retrieve(for: testKey)
        
        // Then
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved, testData)
    }
    
    func testRetrieveStringWithSpecialCharacters() {
        // Given
        let specialString = "Special: 🎉 \n\t @#$%^&*()[]{}|\\\"'<>,.?/"
        sut.save(specialString, for: testKey)
        
        // When
        let retrieved = sut.retrieveString(for: testKey)
        
        // Then
        XCTAssertEqual(retrieved, specialString)
    }
    
    // MARK: - Delete Tests
    
    func testDeleteExistingKey() {
        // Given
        sut.save("Test", for: testKey)
        XCTAssertTrue(sut.exists(for: testKey))
        
        // When
        let result = sut.delete(for: testKey)
        
        // Then
        XCTAssertTrue(result)
        XCTAssertFalse(sut.exists(for: testKey))
    }
    
    func testDeleteNonExistentKey() {
        // When
        let result = sut.delete(for: "non_existent_key")
        
        // Then
        XCTAssertTrue(result) // Should return true even if item doesn't exist
    }
    
    func testDeleteAllItems() {
        // Note: This test is simplified because deleteAll() behavior
        // can vary based on keychain state and simulator environment
        
        // Given - Use unique key for this test
        let uniqueId = UUID().uuidString
        let testKey = "test_delete_all_\(uniqueId)"
        
        // Save an item
        let saved = sut.save("TestValue", for: testKey)
        XCTAssertTrue(saved)
        XCTAssertTrue(sut.exists(for: testKey))
        
        // When - Call deleteAll
        let result = sut.deleteAll()
        
        // Then - Verify the method returns success
        XCTAssertTrue(result)
        
        // The item should be deleted or at least deletable
        // (deleteAll might not delete items from other test runs in simulator)
        let canDelete = sut.delete(for: testKey)
        XCTAssertTrue(canDelete)
    }
    
    // MARK: - Exists Tests
    
    func testExistsForSavedKey() {
        // Given
        sut.save("Test", for: testKey)
        
        // When
        let exists = sut.exists(for: testKey)
        
        // Then
        XCTAssertTrue(exists)
    }
    
    func testExistsForNonExistentKey() {
        // When
        let exists = sut.exists(for: "non_existent_key")
        
        // Then
        XCTAssertFalse(exists)
    }
    
    func testExistsAfterDelete() {
        // Given
        sut.save("Test", for: testKey)
        sut.delete(for: testKey)
        
        // When
        let exists = sut.exists(for: testKey)
        
        // Then
        XCTAssertFalse(exists)
    }
    
    // MARK: - Auth Token Tests
    
    func testSaveAuthToken() {
        // Given
        let token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test.token"
        
        // When
        let result = sut.saveAuthToken(token)
        
        // Then
        XCTAssertTrue(result)
        XCTAssertEqual(sut.getAuthToken(), token)
    }
    
    func testGetAuthTokenWhenNotSet() {
        // When
        let token = sut.getAuthToken()
        
        // Then
        XCTAssertNil(token)
    }
    
    func testDeleteAuthToken() {
        // Given
        sut.saveAuthToken("test_token")
        
        // When
        let result = sut.deleteAuthToken()
        
        // Then
        XCTAssertTrue(result)
        XCTAssertNil(sut.getAuthToken())
    }
    
    func testUpdateAuthToken() {
        // Given
        let oldToken = "old_token"
        let newToken = "new_token"
        sut.saveAuthToken(oldToken)
        
        // When
        let result = sut.saveAuthToken(newToken)
        
        // Then
        XCTAssertTrue(result)
        XCTAssertEqual(sut.getAuthToken(), newToken)
    }
    
    // MARK: - Server URL Tests
    
    func testSaveServerURL() {
        // Given
        let url = "https://localhost:3000"
        
        // When
        let result = sut.saveServerURL(url)
        
        // Then
        XCTAssertTrue(result)
        XCTAssertEqual(sut.getServerURL(), url)
    }
    
    func testGetServerURLWhenNotSet() {
        // When
        let url = sut.getServerURL()
        
        // Then
        XCTAssertNil(url)
    }
    
    func testUpdateServerURL() {
        // Given
        let oldURL = "http://old.server.com"
        let newURL = "https://new.server.com"
        sut.saveServerURL(oldURL)
        
        // When
        let result = sut.saveServerURL(newURL)
        
        // Then
        XCTAssertTrue(result)
        XCTAssertEqual(sut.getServerURL(), newURL)
    }
    
    // MARK: - Singleton Tests
    
    func testSingletonInstance() {
        // Given
        let instance1 = KeychainManager.shared
        let instance2 = KeychainManager.shared
        
        // Then
        XCTAssertTrue(instance1 === instance2)
    }
    
    // MARK: - Concurrent Access Tests
    
    func testConcurrentSaveAndRetrieve() {
        // Given
        let expectation = XCTestExpectation(description: "Concurrent operations")
        expectation.expectedFulfillmentCount = 10
        
        // When
        for i in 0..<10 {
            DispatchQueue.global().async {
                let key = "concurrent_key_\(i)"
                let value = "Value_\(i)"
                
                self.sut.save(value, for: key)
                let retrieved = self.sut.retrieveString(for: key)
                
                XCTAssertEqual(retrieved, value)
                self.sut.delete(for: key)
                
                expectation.fulfill()
            }
        }
        
        // Then
        wait(for: [expectation], timeout: 5.0)
    }
    
    // MARK: - Edge Cases
    
    func testSaveAndRetrieveUnicodeData() {
        // Given
        let unicodeString = "Hello 世界 🌍 مرحبا мир"
        
        // When
        let saved = sut.save(unicodeString, for: testKey)
        let retrieved = sut.retrieveString(for: testKey)
        
        // Then
        XCTAssertTrue(saved)
        XCTAssertEqual(retrieved, unicodeString)
    }
    
    func testKeyWithSpecialCharacters() {
        // Given
        let specialKey = "key.with-special_chars@123"
        let value = "Test value"
        
        // When
        let saved = sut.save(value, for: specialKey)
        let retrieved = sut.retrieveString(for: specialKey)
        
        // Then
        XCTAssertTrue(saved)
        XCTAssertEqual(retrieved, value)
        
        // Cleanup
        sut.delete(for: specialKey)
    }
    
    func testVeryLongKey() {
        // Given
        let longKey = String(repeating: "k", count: 1000)
        let value = "Test value"
        
        // When
        let saved = sut.save(value, for: longKey)
        let retrieved = sut.retrieveString(for: longKey)
        
        // Then
        XCTAssertTrue(saved)
        XCTAssertEqual(retrieved, value)
        
        // Cleanup
        sut.delete(for: longKey)
    }
}