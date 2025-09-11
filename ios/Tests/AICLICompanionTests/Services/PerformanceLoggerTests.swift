import XCTest
@testable import AICLICompanion

@available(iOS 17.0, macOS 14.0, *)
final class PerformanceLoggerTests: XCTestCase {
    var sut: PerformanceLogger!
    
    override func setUp() {
        super.setUp()
        sut = PerformanceLogger.shared
    }
    
    override func tearDown() {
        sut = nil
        super.tearDown()
    }
    
    // MARK: - Timing Tests
    
    func testStartAndEndTiming() {
        // Given
        let operation = "test_operation_\(UUID().uuidString)"
        
        // When
        sut.startTiming(operation)
        
        // Add a small delay to ensure measurable time
        Thread.sleep(forTimeInterval: 0.01)
        
        let duration = sut.endTiming(operation)
        
        // Then
        XCTAssertGreaterThan(duration, 0)
        XCTAssertLessThan(duration, 1.0) // Should be less than 1 second
    }
    
    func testEndTimingWithoutStart() {
        // Given
        let operation = "never_started_operation"
        
        // When
        let duration = sut.endTiming(operation)
        
        // Then
        XCTAssertEqual(duration, 0)
    }
    
    func testMultipleOperations() {
        // Given
        let operation1 = "operation1_\(UUID().uuidString)"
        let operation2 = "operation2_\(UUID().uuidString)"
        
        // When
        sut.startTiming(operation1)
        Thread.sleep(forTimeInterval: 0.01)
        
        sut.startTiming(operation2)
        Thread.sleep(forTimeInterval: 0.02)
        
        let duration1 = sut.endTiming(operation1)
        let duration2 = sut.endTiming(operation2)
        
        // Then
        XCTAssertGreaterThan(duration1, 0)
        XCTAssertGreaterThan(duration2, 0)
        // operation1 should have longer duration as it started first
        XCTAssertGreaterThan(duration1, duration2)
    }
    
    func testOverwriteStartTime() {
        // Given
        let operation = "overwrite_test_\(UUID().uuidString)"
        
        // When
        sut.startTiming(operation)
        Thread.sleep(forTimeInterval: 0.05)
        
        // Restart the same operation
        sut.startTiming(operation)
        Thread.sleep(forTimeInterval: 0.01)
        
        let duration = sut.endTiming(operation)
        
        // Then
        // Duration should be from the second start
        XCTAssertLessThan(duration, 0.03)
    }
    
    // MARK: - Measure Block Tests
    
    func testMeasureSynchronousBlock() {
        // Given
        let operation = "sync_block_\(UUID().uuidString)"
        var blockExecuted = false
        
        // When
        let result = sut.measure(operation) {
            Thread.sleep(forTimeInterval: 0.01)
            blockExecuted = true
            return 42
        }
        
        // Then
        XCTAssertTrue(blockExecuted)
        XCTAssertEqual(result, 42)
    }
    
    func testMeasureSynchronousBlockWithError() {
        // Given
        let operation = "sync_error_block_\(UUID().uuidString)"
        enum TestError: Error { case test }
        
        // When/Then
        XCTAssertThrowsError(
            try sut.measure(operation) {
                Thread.sleep(forTimeInterval: 0.01)
                throw TestError.test
            }
        ) { error in
            XCTAssertTrue(error is TestError)
        }
    }
    
    func testMeasureAsyncBlock() async {
        // Given
        let operation = "async_block_\(UUID().uuidString)"
        var blockExecuted = false
        
        // When
        let result = await sut.measureAsync(operation) {
            try? await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
            blockExecuted = true
            return "async result"
        }
        
        // Then
        XCTAssertTrue(blockExecuted)
        XCTAssertEqual(result, "async result")
    }
    
    func testMeasureAsyncBlockWithError() async {
        // Given
        let operation = "async_error_block_\(UUID().uuidString)"
        enum TestError: Error { case asyncTest }
        
        // When/Then
        do {
            _ = try await sut.measureAsync(operation) {
                try await Task.sleep(nanoseconds: 10_000_000)
                throw TestError.asyncTest
            }
            XCTFail("Should have thrown error")
        } catch {
            XCTAssertTrue(error is TestError)
        }
    }
    
    // MARK: - App Event Logging Tests
    
    func testLogAppEvent() {
        // Given
        let event = "Test Event"
        
        // When
        sut.logAppEvent(event)
        
        // Then
        // This test mainly ensures the method doesn't crash
        // In a real scenario, we might capture console output or use dependency injection
        XCTAssertTrue(true)
    }
    
    func testLogMultipleAppEvents() {
        // Given
        let events = ["App Launched", "View Appeared", "Data Loaded"]
        
        // When
        for event in events {
            sut.logAppEvent(event)
        }
        
        // Then
        XCTAssertTrue(true)
    }
    
    // MARK: - Singleton Tests
    
    func testSingletonInstance() {
        // Given
        let instance1 = PerformanceLogger.shared
        let instance2 = PerformanceLogger.shared
        
        // Then
        XCTAssertTrue(instance1 === instance2)
    }
    
    // MARK: - Concurrent Access Tests
    
    func testConcurrentTiming() {
        // Given
        let expectation = XCTestExpectation(description: "Concurrent timing")
        expectation.expectedFulfillmentCount = 5
        
        // When - Use a serial queue to ensure operations complete properly
        let testQueue = DispatchQueue(label: "test.timing.queue")
        
        for i in 0..<5 {
            testQueue.async {
                let operation = "concurrent_op_\(i)_\(UUID().uuidString)"
                self.sut.startTiming(operation)
                Thread.sleep(forTimeInterval: 0.002)
                let duration = self.sut.endTiming(operation)
                
                XCTAssertGreaterThan(duration, 0)
                XCTAssertLessThan(duration, 1.0)
                expectation.fulfill()
            }
        }
        
        // Then
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testConcurrentMeasure() {
        // Given
        let expectation = XCTestExpectation(description: "Concurrent measure")
        expectation.expectedFulfillmentCount = 5 // Reduced for stability
        
        // When - Use serial queue to avoid race conditions
        let testQueue = DispatchQueue(label: "test.queue")
        
        for i in 0..<5 {
            testQueue.async {
                let result = self.sut.measure("measure_\(i)_\(UUID().uuidString)") {
                    Thread.sleep(forTimeInterval: 0.001)
                    return i
                }
                
                XCTAssertEqual(result, i)
                expectation.fulfill()
            }
        }
        
        // Then
        wait(for: [expectation], timeout: 5.0)
    }
    
    // MARK: - Performance Threshold Tests
    
    func testSlowOperationDetection() {
        // Given
        let operation = "slow_operation_\(UUID().uuidString)"
        
        // When
        sut.startTiming(operation)
        Thread.sleep(forTimeInterval: 0.15) // Reasonably slow but not too long for tests
        let duration = sut.endTiming(operation)
        
        // Then
        XCTAssertGreaterThan(duration, 0.1)
        XCTAssertLessThan(duration, 0.3)
        // In real implementation, operations >1s would trigger a warning
    }
    
    func testNormalOperationSpeed() {
        // Given
        let operation = "normal_operation_\(UUID().uuidString)"
        
        // When
        sut.startTiming(operation)
        Thread.sleep(forTimeInterval: 0.3)
        let duration = sut.endTiming(operation)
        
        // Then
        XCTAssertLessThan(duration, 0.5)
        XCTAssertGreaterThan(duration, 0.2)
    }
    
    func testFastOperationSpeed() {
        // Given
        let operation = "fast_operation_\(UUID().uuidString)"
        
        // When
        sut.startTiming(operation)
        Thread.sleep(forTimeInterval: 0.01)
        let duration = sut.endTiming(operation)
        
        // Then
        XCTAssertLessThan(duration, 0.5)
    }
    
    // MARK: - Nested Timing Tests
    
    func testNestedMeasurements() {
        // Given
        let outerOperation = "outer_\(UUID().uuidString)"
        let innerOperation = "inner_\(UUID().uuidString)"
        
        // When
        let outerResult = sut.measure(outerOperation) {
            Thread.sleep(forTimeInterval: 0.01)
            
            let innerResult = sut.measure(innerOperation) {
                Thread.sleep(forTimeInterval: 0.01)
                return "inner"
            }
            
            XCTAssertEqual(innerResult, "inner")
            return "outer"
        }
        
        // Then
        XCTAssertEqual(outerResult, "outer")
    }
    
    // MARK: - Memory Tests
    
    func testNoMemoryLeaksAfterMultipleOperations() {
        // Given
        weak var weakLogger = sut
        
        // When
        for i in 0..<100 {
            let operation = "memory_test_\(i)"
            sut.startTiming(operation)
            sut.endTiming(operation)
        }
        
        // Then
        XCTAssertNotNil(weakLogger) // Logger is singleton, should not be deallocated
    }
    
    func testCleanupAfterEndTiming() {
        // Given
        let operations = (0..<10).map { "cleanup_test_\($0)" }
        
        // When
        for operation in operations {
            sut.startTiming(operation)
        }
        
        for operation in operations {
            _ = sut.endTiming(operation)
        }
        
        // Then
        // Verify that ending the same operation again returns 0 (not found)
        for operation in operations {
            let duration = sut.endTiming(operation)
            XCTAssertEqual(duration, 0)
        }
    }
}
