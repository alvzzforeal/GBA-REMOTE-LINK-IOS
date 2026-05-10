import Foundation
import Network

// MARK: - Link Cable Host (NWListener + Bonjour)

final class LinkCableHost {
    private weak var session: LinkCableSession?
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let queue = DispatchQueue(label: "gba.link.host", qos: .userInteractive)
    private var pingTimer: DispatchSourceTimer?

    init(session: LinkCableSession) {
        self.session = session
    }

    func start() {
        let port = NWEndpoint.Port(integerLiteral: UInt16(LinkConstants.defaultPort))
        let params = NWParameters.tcp
        params.includePeerToPeer = true

        do {
            listener = try NWListener(using: params, on: port)
        } catch {
            session?.status = .error("Cannot create listener: \(error.localizedDescription)")
            return
        }

        // Advertise via Bonjour so nearby devices can discover it
        listener?.service = NWListener.Service(
            name: UIDevice.current.name,
            type: LinkConstants.serviceType
        )

        listener?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    let port = self?.listener?.port?.rawValue ?? UInt16(LinkConstants.defaultPort)
                    self?.session?.status = .hosting(port: Int(port))
                    self?.startPingTimer()
                case .failed(let err):
                    self?.session?.status = .error(err.localizedDescription)
                default: break
                }
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }

        listener?.start(queue: queue)
    }

    private func accept(_ connection: NWConnection) {
        connections.append(connection)

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .ready:
                let peer = self.peerName(from: connection)
                DispatchQueue.main.async {
                    self.session?.status = .connected(peer: peer)
                }
                // Send handshake
                self.send(.handshake(deviceName: UIDevice.current.name), to: connection)
                self.receive(from: connection)
            case .failed, .cancelled:
                self.connections.removeAll { $0 === connection }
                if self.connections.isEmpty {
                    DispatchQueue.main.async {
                        self.session?.status = .hosting(port: LinkConstants.defaultPort)
                    }
                }
            default: break
            }
        }

        connection.start(queue: queue)
    }

    // MARK: - Send

    func broadcast(_ packet: LinkPacket) {
        for connection in connections {
            send(packet, to: connection)
        }
    }

    private func send(_ packet: LinkPacket, to connection: NWConnection) {
        guard let data = try? JSONEncoder().encode(packet) else { return }
        let framed = frame(data)
        connection.send(content: framed, completion: .idempotent)
    }

    // MARK: - Receive (length-prefixed framing)

    private func receive(from connection: NWConnection) {
        // Read 4-byte length prefix
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self, weak connection] data, _, _, error in
            guard let self, let connection, let data, error == nil else { return }
            let length = data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            self.receiveBody(length: Int(length), from: connection)
        }
    }

    private func receiveBody(length: Int, from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self, weak connection] data, _, _, error in
            guard let self, let connection, let data, error == nil else { return }
            if let packet = try? JSONDecoder().decode(LinkPacket.self, from: data) {
                self.session?.receive(packet)
            }
            self.receive(from: connection)
        }
    }

    // MARK: - Ping timer

    private func startPingTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in
            self?.broadcast(.ping())
        }
        timer.resume()
        pingTimer = timer
    }

    func stop() {
        pingTimer?.cancel()
        pingTimer = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
        listener?.cancel()
        listener = nil
    }

    // MARK: - Helpers

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
        return "Unknown"
    }
}

// MARK: - UIDevice (stub for non-UIKit targets)
#if canImport(UIKit)
import UIKit
#else
class UIDevice {
    static let current = UIDevice()
    var name: String { Host.current().localizedName ?? "Mac" }
}
#endif
