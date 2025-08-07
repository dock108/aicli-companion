//
//  NetworkMonitor.swift
//  ClaudeCompanionHost
//
//  Monitors network interfaces and provides local IP addresses
//

import Foundation
import Network

@MainActor
class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    // MARK: - Published Properties
    @Published var isConnected = false
    @Published var connectionType: NWInterface.InterfaceType?
    @Published var localIP = "127.0.0.1"
    @Published var availableInterfaces: [NetworkInterface] = []
    @Published var currentInterface: NetworkInterface?

    // MARK: - Private Properties
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    private var timer: Timer?

    // MARK: - Initialization
    private init() {
        setupMonitor()
    }

    // MARK: - Public Methods
    func startMonitoring() {
        monitor.start(queue: queue)
        startIPUpdateTimer()
    }

    func stopMonitoring() {
        monitor.cancel()
        stopIPUpdateTimer()
    }

    func refreshInterfaces() {
        updateLocalIP()
        updateAvailableInterfaces()
    }

    // MARK: - Private Methods
    private func setupMonitor() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.updatePath(path)
            }
        }
    }

    private func updatePath(_ path: NWPath) {
        isConnected = path.status == .satisfied

        // Determine connection type
        if path.usesInterfaceType(.wifi) {
            connectionType = .wifi
        } else if path.usesInterfaceType(.wiredEthernet) {
            connectionType = .wiredEthernet
        } else if path.usesInterfaceType(.cellular) {
            connectionType = .cellular
        } else {
            connectionType = nil
        }

        // Update IP when connection changes
        updateLocalIP()
        updateAvailableInterfaces()
    }

    private func startIPUpdateTimer() {
        stopIPUpdateTimer()

        timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshInterfaces()
            }
        }
    }

    private func stopIPUpdateTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updateLocalIP() {
        // Get all network interfaces
        let interfaces = getNetworkInterfaces()

        // Prefer Wi-Fi, then Ethernet, then any other
        if let wifiInterface = interfaces.first(where: { $0.name.starts(with: "en") && $0.isWireless }) {
            localIP = wifiInterface.address
            currentInterface = wifiInterface
        } else if let ethernetInterface = interfaces.first(where: { $0.name.starts(with: "en") && !$0.isWireless }) {
            localIP = ethernetInterface.address
            currentInterface = ethernetInterface
        } else if let anyInterface = interfaces.first {
            localIP = anyInterface.address
            currentInterface = anyInterface
        } else {
            localIP = "127.0.0.1"
            currentInterface = nil
        }
    }

    private func updateAvailableInterfaces() {
        availableInterfaces = getNetworkInterfaces()
    }

    private func getNetworkInterfaces() -> [NetworkInterface] {
        var interfaces: [NetworkInterface] = []

        // Get list of all interfaces
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return interfaces }
        guard let firstAddr = ifaddr else { return interfaces }

        // Iterate through interfaces
        for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ifptr.pointee

            // Check for IPv4 interface
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                // Get interface name
                let name = String(cString: interface.ifa_name)

                // Skip loopback
                if name == "lo0" { continue }

                // Get IP address
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                           &hostname, socklen_t(hostname.count),
                           nil, 0, NI_NUMERICHOST)

                let address = String(cString: hostname)

                // Determine if wireless
                let isWireless = name.starts(with: "en") && isWiFiInterface(name)

                // Determine display name
                let displayName = getInterfaceDisplayName(name, isWireless: isWireless)

                let networkInterface = NetworkInterface(
                    name: name,
                    displayName: displayName,
                    address: address,
                    isWireless: isWireless
                )

                interfaces.append(networkInterface)
            }
        }

        freeifaddrs(ifaddr)
        return interfaces
    }

    private func isWiFiInterface(_ name: String) -> Bool {
        // On macOS, Wi-Fi is typically en0 or en1
        // This is a simplified check - could be enhanced
        return name == "en0" || name == "en1"
    }

    private func getInterfaceDisplayName(_ name: String, isWireless: Bool) -> String {
        switch name {
        case "en0":
            return isWireless ? "Wi-Fi" : "Ethernet 1"
        case "en1":
            return isWireless ? "Wi-Fi 2" : "Ethernet 2"
        case let name where name.starts(with: "en"):
            let number = String(name.dropFirst(2))
            return isWireless ? "Wi-Fi \(number)" : "Ethernet \(number)"
        case let name where name.starts(with: "bridge"):
            return "Bridge"
        case let name where name.starts(with: "awdl"):
            return "AWDL"
        default:
            return name.uppercased()
        }
    }
}

// MARK: - Supporting Types
struct NetworkInterface: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let displayName: String
    let address: String
    let isWireless: Bool

    var icon: String {
        isWireless ? "wifi" : "cable.connector"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(address)
    }

    static func == (lhs: NetworkInterface, rhs: NetworkInterface) -> Bool {
        lhs.name == rhs.name && lhs.address == rhs.address
    }
}
