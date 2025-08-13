//
//  MockNetworkMonitor.swift
//  AICLICompanionHostTests
//
//  Mock network monitor for unit testing without actual network operations
//

import Foundation
import Combine
@testable import AICLICompanionHost

@MainActor
class MockNetworkMonitor: ObservableObject {
    // MARK: - Published Properties
    @Published var isConnected: Bool = true
    @Published var localIP: String = "192.168.1.100"
    @Published var interfaceName: String = "en0"
    @Published var connectionType: String = "WiFi"

    // MARK: - Test Tracking Properties
    var startMonitoringCalled = false
    var stopMonitoringCalled = false
    var updateLocalIPCalled = false
    var updateLocalIPCallCount = 0

    // Test control properties
    var simulateNetworkFailure = false
    var customLocalIP: String?

    // MARK: - Singleton (matching real NetworkMonitor)
    static let shared = MockNetworkMonitor()

    // MARK: - Public Methods

    func startMonitoring() {
        startMonitoringCalled = true

        if simulateNetworkFailure {
            isConnected = false
            localIP = "127.0.0.1"
            connectionType = "None"
        } else {
            isConnected = true
            localIP = customLocalIP ?? "192.168.1.100"
            connectionType = "WiFi"
        }
    }

    func stopMonitoring() {
        stopMonitoringCalled = true
    }

    func updateLocalIP() {
        updateLocalIPCalled = true
        updateLocalIPCallCount += 1

        if simulateNetworkFailure {
            localIP = "127.0.0.1"
        } else {
            localIP = customLocalIP ?? "192.168.1.100"
        }
    }

    func getCurrentNetworkInfo() -> (ip: String, interface: String, type: String) {
        return (localIP, interfaceName, connectionType)
    }

    // MARK: - Test Helpers

    func simulateNetworkChange(connected: Bool, ip: String? = nil) {
        isConnected = connected

        if connected {
            localIP = ip ?? "192.168.1.100"
            connectionType = "WiFi"
            interfaceName = "en0"
        } else {
            localIP = "127.0.0.1"
            connectionType = "None"
            interfaceName = "lo0"
        }
    }

    func simulateIPChange(_ newIP: String) {
        localIP = newIP
    }

    func reset() {
        isConnected = true
        localIP = "192.168.1.100"
        interfaceName = "en0"
        connectionType = "WiFi"

        startMonitoringCalled = false
        stopMonitoringCalled = false
        updateLocalIPCalled = false
        updateLocalIPCallCount = 0

        simulateNetworkFailure = false
        customLocalIP = nil
    }
}