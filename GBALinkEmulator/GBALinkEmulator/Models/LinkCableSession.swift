import Foundation
import Combine

// MARK: - Link Cable Packet

struct LinkPacket: Codable {
    enum Kind: String, Codable {
        case handshake
        case inputState
        case serialData   // GBA link-cable byte exchange
        case ping
        case pong
    }

    var kind: Kind
    var payload: Data
    var timestamp: TimeInterval = Date().timeIntervalSince1970

    static func handshake(deviceName: String) -> LinkPacket {
        let data = deviceName.data(using: .utf8) ?? Data()
        return LinkPacket(kind: .handshake, payload: data)
    }

    static func inputState(_ state: GBAInputState) -> LinkPacket {
        let data = (try? JSONEncoder().encode(state)) ?? Data()
        return LinkPacket(kind: .inputState, payload: data)
    }

    static func serialData(_ bytes: [UInt8]) -> LinkPacket {
        return LinkPacket(kind: .serialData, payload: Data(bytes))
    }

    static func ping() -> LinkPacket {
        LinkPacket(kind: .ping, payload: Data())
    }

    static func pong() -> LinkPacket {
        LinkPacket(kind: .pong, payload: Data())
    }
}

// MARK: - GBA Input State (shared over the link)

struct GBAInputState: Codable {
    var a: Bool = false
    var b: Bool = false
    var start: Bool = false
    var select: Bool = false
    var up: Bool = false
    var down: Bool = false
    var left: Bool = false
    var right: Bool = false
    var l: Bool = false
    var r: Bool = false

    /// Converts to GBA key mask (bit-inverted: 0 = pressed)
    var keyMask: UInt16 {
        var mask: UInt16 = 0x03FF
        if a      { mask &= ~(1 << 0) }
        if b      { mask &= ~(1 << 1) }
        if select { mask &= ~(1 << 2) }
        if start  { mask &= ~(1 << 3) }
        if right  { mask &= ~(1 << 4) }
        if left   { mask &= ~(1 << 5) }
        if up     { mask &= ~(1 << 6) }
        if down   { mask &= ~(1 << 7) }
        if r      { mask &= ~(1 << 8) }
        if l      { mask &= ~(1 << 9) }
        return mask
    }
}

// MARK: - Connection Status

enum LinkConnectionStatus: Equatable {
    case disconnected
    case hosting(port: Int)
    case searching
    case connecting(host: String)
    case connected(peer: String)
    case error(String)

    var description: String {
        switch self {
        case .disconnected:           return "Disconnected"
        case .hosting(let port):      return "Hosting on port \(port)"
        case .searching:              return "Searching for hosts..."
        case .connecting(let host):   return "Connecting to \(host)..."
        case .connected(let peer):    return "Connected to \(peer)"
        case .error(let msg):         return "Error: \(msg)"
        }
    }

    var isActive: Bool {
        if case .connected = self { return true }
        return false
    }

    var color: String {
        switch self {
        case .connected:  return "green"
        case .error:      return "red"
        case .hosting, .searching, .connecting: return "yellow"
        case .disconnected: return "gray"
        }
    }
}

// MARK: - Link Cable Session (shared ObservableObject)

class LinkCableSession: ObservableObject {
    @Published var status: LinkConnectionStatus = .disconnected
    @Published var peerName: String = ""
    @Published var latencyMs: Double = 0
    @Published var receivedPackets: [LinkPacket] = []
    @Published var remoteInputState: GBAInputState = GBAInputState()

    var onSerialData: (([UInt8]) -> Void)?

    private(set) var host: LinkCableHost?
    private(set) var client: LinkCableClient?

    func startHost() {
        stopAll()
        host = LinkCableHost(session: self)
        host?.start()
    }

    func startClient() {
        stopAll()
        client = LinkCableClient(session: self)
        client?.startBrowsing()
    }

    func connectToIP(_ ip: String, port: Int = LinkConstants.defaultPort) {
        stopAll()
        client = LinkCableClient(session: self)
        client?.connect(host: ip, port: port)
    }

    func sendInputState(_ state: GBAInputState) {
        let packet = LinkPacket.inputState(state)
        sendPacket(packet)
    }

    func sendSerialData(_ bytes: [UInt8]) {
        let packet = LinkPacket.serialData(bytes)
        sendPacket(packet)
    }

    func sendPacket(_ packet: LinkPacket) {
        host?.broadcast(packet)
        client?.send(packet)
    }

    func receive(_ packet: LinkPacket) {
        DispatchQueue.main.async {
            switch packet.kind {
            case .inputState:
                if let state = try? JSONDecoder().decode(GBAInputState.self, from: packet.payload) {
                    self.remoteInputState = state
                }
            case .serialData:
                let bytes = [UInt8](packet.payload)
                self.onSerialData?(bytes)
            case .ping:
                self.sendPacket(.pong())
            case .pong:
                let now = Date().timeIntervalSince1970
                self.latencyMs = (now - packet.timestamp) * 1000
            case .handshake:
                self.peerName = String(data: packet.payload, encoding: .utf8) ?? "Unknown"
            }
            self.receivedPackets.append(packet)
            if self.receivedPackets.count > 50 {
                self.receivedPackets.removeFirst()
            }
        }
    }

    func stopAll() {
        host?.stop()
        client?.stop()
        host = nil
        client = nil
        DispatchQueue.main.async {
            self.status = .disconnected
            self.peerName = ""
        }
    }
}

// MARK: - Constants

enum LinkConstants {
    static let defaultPort: Int = 12345
    static let serviceName  = "_gbalink._tcp"
    static let serviceType  = "_gbalink._tcp."
}
