import Foundation
import Network

// MARK: - Link Cable Client (NWBrowser + NWConnection)

final class LinkCableClient {
    private weak var session: LinkCableSession?
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "gba.link.client", qos: .userInteractive)

    @Published var discoveredHosts: [DiscoveredHost] = []
    private var hostsUpdateHandler: (([DiscoveredHost]) -> Void)?

    init(session: LinkCableSession) {
        self.session = session
    }

    // MARK: - Bonjour Discovery

    func startBrowsing(onUpdate: (([DiscoveredHost]) -> Void)? = nil) {
        hostsUpdateHandler = onUpdate
        DispatchQueue.main.async { self.session?.status = .searching }

        let params = NWParameters()
        params.includePeerToPeer = true
        browser = NWBrowser(for: .bonjourWithTXTRecord(type: LinkConstants.serviceType, domain: nil), using: params)

        browser?.stateUpdateHandler = { [weak self] state in
            if case .failed(let err) = state {
                DispatchQueue.main.async {
                    self?.session?.status = .error(err.localizedDescription)
                }
            }
        }

        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            let hosts = results.compactMap { result -> DiscoveredHost? in
                guard case let .service(name, type, domain, _) = result.endpoint else { return nil }
                return DiscoveredHost(name: name, type: type, domain: domain, endpoint: result.endpoint)
            }
            DispatchQueue.main.async {
                self?.discoveredHosts = hosts
                self?.hostsUpdateHandler?(hosts)
            }
        }

        browser?.start(queue: queue)
    }

    func connectToDiscovered(_ host: DiscoveredHost) {
        browser?.cancel()
        browser = nil
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        DispatchQueue.main.async { self.session?.status = .connecting(host: host.name) }
        let conn = NWConnection(to: host.endpoint, using: params)
        startConnection(conn)
    }

    // MARK: - Manual IP Connection

    func connect(host ip: String, port: Int = LinkConstants.defaultPort) {
        browser?.cancel()
        browser = nil
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(ip),
            port: NWEndpoint.Port(integerLiteral: UInt16(port))
        )
        DispatchQueue.main.async { self.session?.status = .connecting(host: ip) }
        let conn = NWConnection(to: endpoint, using: .tcp)
        startConnection(conn)
    }

    private func startConnection(_ conn: NWConnection) {
        connection = conn
        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                let peer = self.peerName(from: conn)
                DispatchQueue.main.async {
                    self.session?.status = .connected(peer: peer)
                }
                self.send(.handshake(deviceName: self.deviceName()))
                self.receive()
            case .failed(let err):
                DispatchQueue.main.async {
                    self.session?.status = .error(err.localizedDescription)
                }
            case .cancelled:
                DispatchQueue.main.async {
                    self.session?.status = .disconnected
                }
            default: break
            }
        }
        conn.start(queue: queue)
    }

    // MARK: - Send

    func send(_ packet: LinkPacket) {
        guard let conn = connection, conn.state == .ready else { return }
        guard let data = try? JSONEncoder().encode(packet) else { return }
        let framed = frame(data)
        conn.send(content: framed, completion: .idempotent)
    }

    // MARK: - Receive (length-prefixed framing)

    private func receive() {
        connection?.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, error in
            guard let self, let data, error == nil else { return }
            let length = data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            self.receiveBody(length: Int(length))
        }
    }

    private func receiveBody(length: Int) {
        connection?.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] data, _, _, error in
            guard let self, let data, error == nil else { return }
            if let packet = try? JSONDecoder().decode(LinkPacket.self, from: data) {
                self.session?.receive(packet)
            }
            self.receive()
        }
    }

    // MARK: - Helpers

    func stop() {
        browser?.cancel()
        browser = nil
        connection?.cancel()
        connection = nil
    }

    private func frame(_ data: Data) -> Data {
        var length = UInt32(data.count).bigEndian
        var framed = Data(bytes: &length, count: 4)
        framed.append(data)
        return framed
    }

    private func peerName(from connection: NWConnection) -> String {
        if case let .hostPort(host, _) = connection.endpoint {
            return "\(host)"
        }
        return "Host"
    }

    private func deviceName() -> String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return Host.current().localizedName ?? "Device"
        #endif
    }
}

// MARK: - Discovered Host

struct DiscoveredHost: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let type: String
    let domain: String
    let endpoint: NWEndpoint

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
    static func == (lhs: DiscoveredHost, rhs: DiscoveredHost) -> Bool {
        lhs.name == rhs.name
    }
}
