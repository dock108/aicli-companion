//
//  NetworkMonitorTests.swift
//  AICLICompanionHostTests
//
//  Unit tests for NetworkMonitor
//

import XCTest
import Combine
@testable import AICLICompanionHost

@MainActor
final class NetworkMonitorTests: XCTestCase {
    var mockNetworkMonitor: MockNetworkMonitor!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        mockNetworkMonitor = MockNetworkMonitor()
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        mockNetworkMonitor.reset()
        cancellables.removeAll()
        mockNetworkMonitor = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testNetworkMonitorInitialState() throws {
        XCTAssertTrue(mockNetworkMonitor.isConnected)
        XCTAssertEqual(mockNetworkMonitor.localIP, "192.168.1.100")
        XCTAssertEqual(mockNetworkMonitor.interfaceName, "en0")
        XCTAssertEqual(mockNetworkMonitor.connectionType, "WiFi")
    }

    func testNetworkMonitorSingleton() throws {
        let monitor1 = MockNetworkMonitor.shared
        let monitor2 = MockNetworkMonitor.shared

        // Should be the same instance
        XCTAssertTrue(monitor1 === monitor2)
    }

    // MARK: - Monitoring Control Tests

    func testStartMonitoring() throws {
        mockNetworkMonitor.startMonitoring()

        XCTAssertTrue(mockNetworkMonitor.startMonitoringCalled)
        XCTAssertTrue(mockNetworkMonitor.isConnected)
        XCTAssertEqual(mockNetworkMonitor.localIP, "192.168.1.100")
        XCTAssertEqual(mockNetworkMonitor.connectionType, "WiFi")
    }

    func testStartMonitoringWithNetworkFailure() throws {
        mockNetworkMonitor.simulateNetworkFailure = true

        mockNetworkMonitor.startMonitoring()

        XCTAssertTrue(mockNetworkMonitor.startMonitoringCalled)
        XCTAssertFalse(mockNetworkMonitor.isConnected)
        XCTAssertEqual(mockNetworkMonitor.localIP, "127.0.0.1")
        XCTAssertEqual(mockNetworkMonitor.connectionType, "None")
    }

    func testStartMonitoringWithCustomIP() throws {
        mockNetworkMonitor.customLocalIP = "10.0.0.50"

        mockNetworkMonitor.startMonitoring()

        XCTAssertTrue(mockNetworkMonitor.startMonitoringCalled)
        XCTAssertTrue(mockNetworkMonitor.isConnected)
        XCTAssertEqual(mockNetworkMonitor.localIP, "10.0.0.50")
    }

    func testStopMonitoring() throws {
        mockNetworkMonitor.stopMonitoring()

        XCTAssertTrue(mockNetworkMonitor.stopMonitoringCalled)
    }

    // MARK: - IP Update Tests

    func testUpdateLocalIP() throws {
        mockNetworkMonitor.updateLocalIP()

        XCTAssertTrue(mockNetworkMonitor.updateLocalIPCalled)
        XCTAssertEqual(mockNetworkMonitor.updateLocalIPCallCount, 1)
        XCTAssertEqual(mockNetworkMonitor.localIP, "192.168.1.100")
    }

    func testUpdateLocalIPWithNetworkFailure() throws {
        mockNetworkMonitor.simulateNetworkFailure = true

        mockNetworkMonitor.updateLocalIP()

        XCTAssertTrue(mockNetworkMonitor.updateLocalIPCalled)
        XCTAssertEqual(mockNetworkMonitor.localIP, "127.0.0.1")
    }

    func testUpdateLocalIPWithCustomIP() throws {
        mockNetworkMonitor.customLocalIP = "172.16.0.10"

        mockNetworkMonitor.updateLocalIP()

        XCTAssertTrue(mockNetworkMonitor.updateLocalIPCalled)
        XCTAssertEqual(mockNetworkMonitor.localIP, "172.16.0.10")
    }

    func testUpdateLocalIPMultipleTimes() throws {
        mockNetworkMonitor.updateLocalIP()
        mockNetworkMonitor.updateLocalIP()
        mockNetworkMonitor.updateLocalIP()

        XCTAssertEqual(mockNetworkMonitor.updateLocalIPCallCount, 3)
    }

    // MARK: - Network Info Tests

    func testGetCurrentNetworkInfo() throws {
        let (ip, interface, type) = mockNetworkMonitor.getCurrentNetworkInfo()

        XCTAssertEqual(ip, "192.168.1.100")
        XCTAssertEqual(interface, "en0")
        XCTAssertEqual(type, "WiFi")
    }

    func testGetCurrentNetworkInfoAfterUpdate() throws {
        mockNetworkMonitor.localIP = "10.0.0.1"
        mockNetworkMonitor.interfaceName = "en1"
        mockNetworkMonitor.connectionType = "Ethernet"

        let (ip, interface, type) = mockNetworkMonitor.getCurrentNetworkInfo()

        XCTAssertEqual(ip, "10.0.0.1")
        XCTAssertEqual(interface, "en1")
        XCTAssertEqual(type, "Ethernet")
    }

    // MARK: - Network Change Simulation Tests

    func testSimulateNetworkChangeToDisconnected() throws {
        mockNetworkMonitor.simulateNetworkChange(connected: false)

        XCTAssertFalse(mockNetworkMonitor.isConnected)
        XCTAssertEqual(mockNetworkMonitor.localIP, "127.0.0.1")
        XCTAssertEqual(mockNetworkMonitor.connectionType, "None")
        XCTAssertEqual(mockNetworkMonitor.interfaceName, "lo0")
    }

    func testSimulateNetworkChangeToConnected() throws {
        // First disconnect
        mockNetworkMonitor.simulateNetworkChange(connected: false)
        XCTAssertFalse(mockNetworkMonitor.isConnected)

        // Then reconnect
        mockNetworkMonitor.simulateNetworkChange(connected: true)

        XCTAssertTrue(mockNetworkMonitor.isConnected)
        XCTAssertEqual(mockNetworkMonitor.localIP, "192.168.1.100")
        XCTAssertEqual(mockNetworkMonitor.connectionType, "WiFi")
        XCTAssertEqual(mockNetworkMonitor.interfaceName, "en0")
    }

    func testSimulateNetworkChangeWithCustomIP() throws {
        mockNetworkMonitor.simulateNetworkChange(connected: true, ip: "172.20.10.5")

        XCTAssertTrue(mockNetworkMonitor.isConnected)
        XCTAssertEqual(mockNetworkMonitor.localIP, "172.20.10.5")
    }

    func testSimulateIPChange() throws {
        let newIP = "192.168.50.100"

        mockNetworkMonitor.simulateIPChange(newIP)

        XCTAssertEqual(mockNetworkMonitor.localIP, newIP)
    }

    // MARK: - Published Properties Tests

    func testIsConnectedPublishedChanges() throws {
        let expectation = XCTestExpectation(description: "isConnected should publish changes")
        var receivedValues: [Bool] = []

        mockNetworkMonitor.$isConnected
            .sink { value in
                receivedValues.append(value)
                if receivedValues.count >= 2 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // Simulate network disconnection
        mockNetworkMonitor.simulateNetworkChange(connected: false)

        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(receivedValues.first, true)  // Initial state
        XCTAssertEqual(receivedValues.last, false)  // After disconnection
    }

    func testLocalIPPublishedChanges() throws {
        let expectation = XCTestExpectation(description: "localIP should publish changes")
        var receivedValues: [String] = []

        mockNetworkMonitor.$localIP
            .sink { value in
                receivedValues.append(value)
                if receivedValues.count >= 2 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // Change IP
        mockNetworkMonitor.simulateIPChange("10.0.0.1")

        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(receivedValues.first, "192.168.1.100")  // Initial IP
        XCTAssertEqual(receivedValues.last, "10.0.0.1")        // New IP
    }

    // MARK: - Reset Tests

    func testResetRestoresDefaultState() throws {
        // Change all properties
        mockNetworkMonitor.isConnected = false
        mockNetworkMonitor.localIP = "10.0.0.1"
        mockNetworkMonitor.interfaceName = "custom0"
        mockNetworkMonitor.connectionType = "Custom"
        mockNetworkMonitor.simulateNetworkFailure = true
        mockNetworkMonitor.customLocalIP = "172.16.0.1"

        // Trigger tracking flags
        mockNetworkMonitor.startMonitoring()
        mockNetworkMonitor.stopMonitoring()
        mockNetworkMonitor.updateLocalIP()

        // Reset
        mockNetworkMonitor.reset()

        // Verify default state restored
        XCTAssertTrue(mockNetworkMonitor.isConnected)
        XCTAssertEqual(mockNetworkMonitor.localIP, "192.168.1.100")
        XCTAssertEqual(mockNetworkMonitor.interfaceName, "en0")
        XCTAssertEqual(mockNetworkMonitor.connectionType, "WiFi")

        // Verify tracking flags cleared
        XCTAssertFalse(mockNetworkMonitor.startMonitoringCalled)
        XCTAssertFalse(mockNetworkMonitor.stopMonitoringCalled)
        XCTAssertFalse(mockNetworkMonitor.updateLocalIPCalled)
        XCTAssertEqual(mockNetworkMonitor.updateLocalIPCallCount, 0)

        // Verify control properties cleared
        XCTAssertFalse(mockNetworkMonitor.simulateNetworkFailure)
        XCTAssertNil(mockNetworkMonitor.customLocalIP)
    }

    // MARK: - Edge Cases

    func testMultipleNetworkChanges() throws {
        // Simulate rapid network changes
        mockNetworkMonitor.simulateNetworkChange(connected: false)
        mockNetworkMonitor.simulateNetworkChange(connected: true, ip: "192.168.1.1")
        mockNetworkMonitor.simulateNetworkChange(connected: false)
        mockNetworkMonitor.simulateNetworkChange(connected: true, ip: "10.0.0.1")

        // Final state should be connected with last IP
        XCTAssertTrue(mockNetworkMonitor.isConnected)
        XCTAssertEqual(mockNetworkMonitor.localIP, "10.0.0.1")
    }

    func testLocalIPWithVariousFormats() throws {
        // Test IPv4 addresses
        let ipv4Addresses = [
            "192.168.1.1",
            "10.0.0.1",
            "172.16.0.1",
            "127.0.0.1",
            "255.255.255.255",
            "0.0.0.0"
        ]

        for ip in ipv4Addresses {
            mockNetworkMonitor.simulateIPChange(ip)
            XCTAssertEqual(mockNetworkMonitor.localIP, ip)
        }
    }
}
