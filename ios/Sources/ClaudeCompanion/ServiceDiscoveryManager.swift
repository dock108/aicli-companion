import Foundation
import Network
import Combine

class ServiceDiscoveryManager: NSObject, ObservableObject {
    @Published var discoveredServers: [DiscoveredClaudeServer] = []
    @Published var isScanning = false
    @Published var discoveryError: String?

    private var serviceBrowser: NetServiceBrowser?
    private var discoveredServices: [NetService] = []
    private var serviceResolvers: [NetService] = []
    private var cancellables = Set<AnyCancellable>()

    // Service discovery parameters
    private let serviceType = "_claudecode._tcp."
    private let domain = "local."
    private let discoveryTimeout: TimeInterval = 10.0
    private var discoveryTimer: Timer?

    override init() {
        super.init()
        setupServiceBrowser()
    }

    deinit {
        stopDiscovery()
    }

    // MARK: - Public API

    func startDiscovery() {
        guard !isScanning else { return }

        DispatchQueue.main.async {
            self.isScanning = true
            self.discoveryError = nil
            self.discoveredServers.removeAll()
        }

        discoveredServices.removeAll()
        serviceResolvers.removeAll()

        serviceBrowser?.searchForServices(ofType: serviceType, inDomain: domain)

        // Set timeout for discovery
        discoveryTimer?.invalidate()
        discoveryTimer = Timer.scheduledTimer(withTimeInterval: discoveryTimeout, repeats: false) { [weak self] _ in
            self?.stopDiscovery()
        }

        print("🔍 Starting Bonjour discovery for Claude Code servers...")
    }

    func stopDiscovery() {
        guard isScanning else { return }

        discoveryTimer?.invalidate()
        discoveryTimer = nil

        serviceBrowser?.stop()

        // Stop all service resolvers
        serviceResolvers.forEach { service in
            service.stop()
            service.delegate = nil
        }
        serviceResolvers.removeAll()

        DispatchQueue.main.async {
            self.isScanning = false
        }

        print("🔍 Stopped Bonjour discovery")
    }

    func refreshDiscovery() {
        stopDiscovery()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.startDiscovery()
        }
    }

    // MARK: - Private Setup

    private func setupServiceBrowser() {
        serviceBrowser = NetServiceBrowser()
        serviceBrowser?.delegate = self
    }

    private func resolveService(_ service: NetService) {
        service.delegate = self
        serviceResolvers.append(service)
        service.resolve(withTimeout: 5.0)
    }

    private func createDiscoveredServer(from service: NetService) -> DiscoveredClaudeServer? {
        guard let hostName = service.hostName,
              service.port > 0 else {
            return nil
        }

        // Parse TXT record data
        let txtData = parseTXTRecord(service.txtRecordData())

        return DiscoveredClaudeServer(
            name: service.name,
            hostName: hostName,
            port: service.port,
            isSecure: txtData["tls"] == "enabled",
            requiresAuth: txtData["auth"] == "required",
            version: txtData["version"] ?? "unknown",
            features: (txtData["features"] ?? "").components(separatedBy: ","),
            protocol: txtData["protocol"] ?? (txtData["tls"] == "enabled" ? "wss" : "ws"),
            netService: service
        )
    }

    private func parseTXTRecord(_ data: Data?) -> [String: String] {
        guard let data = data else { return [:] }

        var result: [String: String] = [:]

        // Parse TXT record format
        var offset = 0
        while offset < data.count {
            let length = Int(data[offset])
            offset += 1

            guard offset + length <= data.count else { break }

            let recordData = data.subdata(in: offset..<(offset + length))
            if let recordString = String(data: recordData, encoding: .utf8) {
                let components = recordString.components(separatedBy: "=")
                if components.count == 2 {
                    result[components[0]] = components[1]
                } else if components.count == 1 {
                    result[components[0]] = ""
                }
            }

            offset += length
        }

        return result
    }
}

// MARK: - NetServiceBrowserDelegate

extension ServiceDiscoveryManager: NetServiceBrowserDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        print("🔍 Found service: \(service.name) at \(service.domain)")

        discoveredServices.append(service)
        resolveService(service)

        if !moreComing {
            print("🔍 No more services coming")
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        print("🔍 Removed service: \(service.name)")

        discoveredServices.removeAll { $0 == service }

        DispatchQueue.main.async {
            self.discoveredServers.removeAll { server in
                server.netService == service
            }
        }
    }

    func netServiceBrowserWillSearch(_ browser: NetServiceBrowser) {
        print("🔍 Browser will start searching")
    }

    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        print("🔍 Browser stopped searching")
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        let errorCode = errorDict[NetService.errorCode] ?? NSNumber(value: -1)
        let errorMessage = "Service discovery failed with error code: \(errorCode)"

        print("🔍 Browser search failed: \(errorMessage)")

        DispatchQueue.main.async {
            self.discoveryError = errorMessage
            self.isScanning = false
        }
    }
}

// MARK: - NetServiceDelegate

extension ServiceDiscoveryManager: NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        print("🔍 Resolved service: \(sender.name) -> \(sender.hostName ?? "unknown"):\(sender.port)")

        if let server = createDiscoveredServer(from: sender) {
            DispatchQueue.main.async {
                // Avoid duplicates
                if !self.discoveredServers.contains(where: { $0.hostName == server.hostName && $0.port == server.port }) {
                    self.discoveredServers.append(server)
                    self.discoveredServers.sort { $0.name < $1.name }
                }
            }
        }

        // Clean up resolver
        sender.delegate = nil
        serviceResolvers.removeAll { $0 == sender }
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        let errorCode = errorDict[NetService.errorCode] ?? NSNumber(value: -1)
        print("🔍 Failed to resolve service \(sender.name): error code \(errorCode)")

        // Clean up resolver
        sender.delegate = nil
        serviceResolvers.removeAll { $0 == sender }
    }
}

// MARK: - Supporting Types

struct DiscoveredClaudeServer: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let hostName: String
    let port: Int
    let isSecure: Bool
    let requiresAuth: Bool
    let version: String
    let features: [String]
    let protocol: String
    let netService: NetService

    var displayName: String {
        return name.isEmpty ? "Claude Code Server" : name
    }

    var address: String {
        // Remove trailing dot from hostname if present
        let cleanHostName = hostName.hasSuffix(".") ? String(hostName.dropLast()) : hostName
        return cleanHostName
    }

    var url: URL? {
        let scheme = isSecure ? "https" : "http"
        return URL(string: "\(scheme)://\(address):\(port)")
    }

    var webSocketURL: URL? {
        let scheme = isSecure ? "wss" : "ws"
        return URL(string: "\(scheme)://\(address):\(port)/ws")
    }

    var connectionInfo: String {
        var info = [String]()

        if isSecure {
            info.append("🔒 Secure")
        }

        if requiresAuth {
            info.append("🔐 Auth Required")
        }

        if !version.isEmpty && version != "unknown" {
            info.append("v\(version)")
        }

        return info.joined(separator: " • ")
    }

    static func == (lhs: DiscoveredClaudeServer, rhs: DiscoveredClaudeServer) -> Bool {
        return lhs.hostName == rhs.hostName && lhs.port == rhs.port
    }
}

// MARK: - Manual Server Configuration

struct ManualServerConfiguration {
    let address: String
    let port: Int
    let isSecure: Bool
    let authToken: String?

    var url: URL? {
        let scheme = isSecure ? "https" : "http"
        return URL(string: "\(scheme)://\(address):\(port)")
    }

    var webSocketURL: URL? {
        let scheme = isSecure ? "wss" : "ws"
        return URL(string: "\(scheme)://\(address):\(port)/ws")
    }

    func toServerConnection() -> ServerConnection {
        return ServerConnection(
            address: address,
            port: port,
            authToken: authToken,
            isSecure: isSecure
        )
    }
}

// MARK: - Network Validation

extension ServiceDiscoveryManager {
    func validateServer(_ server: DiscoveredClaudeServer, completion: @escaping (Result<ServerConnection, ClaudeCompanionError>) -> Void) {
        guard let url = server.url else {
            completion(.failure(.invalidResponse))
            return
        }

        var request = URLRequest(url: url.appendingPathComponent("/health"))
        request.httpMethod = "GET"
        request.timeoutInterval = 5.0

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(.networkError(error)))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(.invalidResponse))
                return
            }

            if httpResponse.statusCode == 200 {
                let connection = ServerConnection(
                    address: server.address,
                    port: server.port,
                    authToken: nil, // Will be set later if required
                    isSecure: server.isSecure
                )
                completion(.success(connection))
            } else {
                completion(.failure(.connectionFailed("HTTP \(httpResponse.statusCode)")))
            }
        }.resume()
    }

    func validateManualConfiguration(_ config: ManualServerConfiguration, completion: @escaping (Result<ServerConnection, ClaudeCompanionError>) -> Void) {
        guard let url = config.url else {
            completion(.failure(.invalidResponse))
            return
        }

        var request = URLRequest(url: url.appendingPathComponent("/health"))
        request.httpMethod = "GET"
        request.timeoutInterval = 5.0

        if let token = config.authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(.networkError(error)))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(.invalidResponse))
                return
            }

            switch httpResponse.statusCode {
            case 200:
                completion(.success(config.toServerConnection()))
            case 401:
                completion(.failure(.authenticationFailed))
            default:
                completion(.failure(.connectionFailed("HTTP \(httpResponse.statusCode)")))
            }
        }.resume()
    }
}
