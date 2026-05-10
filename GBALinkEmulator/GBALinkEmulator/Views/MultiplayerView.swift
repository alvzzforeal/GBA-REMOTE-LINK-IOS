import SwiftUI
import Network

// MARK: - Multiplayer View

struct MultiplayerView: View {
    @EnvironmentObject var linkSession: LinkCableSession
    @State private var mode: MultiplayerMode = .idle
    @State private var manualIP = ""
    @State private var manualPort = "\(LinkConstants.defaultPort)"
    @State private var discoveredHosts: [DiscoveredHost] = []
    @State private var showIPSheet = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    statusCard
                    modeButtons

                    switch mode {
                    case .hosting:
                        hostingCard
                    case .joining:
                        joiningCard
                    case .idle:
                        idlePrompt
                    }
                }
                .padding()
            }
            .navigationTitle("Link Cable")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if mode != .idle {
                        Button("Disconnect") {
                            stopAll()
                        }
                        .foregroundColor(.red)
                    }
                }
            }
        }
        .sheet(isPresented: $showIPSheet) {
            IPConnectionSheet(ip: $manualIP, port: $manualPort) { ip, port in
                linkSession.connectToIP(ip, port: port)
                mode = .joining
                showIPSheet = false
            }
        }
    }

    // MARK: - Status Card

    private var statusCard: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .stroke(statusColor.opacity(0.4), lineWidth: 4)
                        .scaleEffect(linkSession.status.isActive ? 1.4 : 1)
                        .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true),
                                   value: linkSession.status.isActive)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(linkSession.status.description)
                    .font(.headline)
                if !linkSession.peerName.isEmpty {
                    Text("Peer: \(linkSession.peerName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if linkSession.status.isActive {
                    Text(String(format: "Latency: %.0f ms", linkSession.latencyMs))
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }

            Spacer()
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Mode Buttons

    private var modeButtons: some View {
        HStack(spacing: 12) {
            ModeButton(
                icon: "antenna.radiowaves.left.and.right",
                title: "Host",
                subtitle: "Create session",
                isSelected: mode == .hosting,
                color: .blue
            ) {
                stopAll()
                mode = .hosting
                linkSession.startHost()
            }

            ModeButton(
                icon: "wifi",
                title: "Join",
                subtitle: "Find session",
                isSelected: mode == .joining,
                color: .green
            ) {
                stopAll()
                mode = .joining
                startBrowsing()
            }
        }
    }

    // MARK: - Hosting Card

    private var hostingCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Hosting", systemImage: "antenna.radiowaves.left.and.right")
                .font(.headline)
                .foregroundColor(.blue)

            if case .hosting(let port) = linkSession.status {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your session is visible on the local network.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    HStack {
                        Text("Port")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(port)")
                            .monospaced()
                            .bold()
                    }

                    HStack {
                        Text("Service")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(LinkConstants.serviceName)
                            .monospaced()
                            .font(.caption)
                    }
                }
            }

            Text("Waiting for a player to join...")
                .font(.caption)
                .foregroundColor(.secondary)
                .italic()
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Joining Card

    private var joiningCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Looking for hosts", systemImage: "wifi")
                .font(.headline)
                .foregroundColor(.green)

            if discoveredHosts.isEmpty {
                HStack {
                    ProgressView()
                    Text("Scanning local network...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.leading, 8)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Discovered Hosts")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)

                    ForEach(discoveredHosts) { host in
                        HostRow(host: host) {
                            linkSession.client?.connectToDiscovered(host)
                        }
                    }
                }
            }

            Divider()

            Button(action: { showIPSheet = true }) {
                Label("Connect by IP", systemImage: "network")
                    .font(.subheadline.bold())
                    .foregroundColor(.blue)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Idle Prompt

    private var idlePrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "cable.connector.horizontal")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Choose Host or Join to start a Link Cable session.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 32)
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch linkSession.status {
        case .connected:    return .green
        case .error:        return .red
        case .disconnected: return .gray
        default:            return .yellow
        }
    }

    private func startBrowsing() {
        discoveredHosts = []
        linkSession.startClient()

        // Poll discovered hosts from the client every second
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if self.mode != .joining {
                timer.invalidate()
                return
            }
            if let hosts = self.linkSession.client?.discoveredHosts {
                self.discoveredHosts = hosts
            }
        }
    }

    private func stopAll() {
        linkSession.stopAll()
        discoveredHosts = []
        mode = .idle
    }
}

// MARK: - Multiplayer Mode

enum MultiplayerMode: Equatable {
    case idle, hosting, joining
}

// MARK: - Mode Button

struct ModeButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : color)
                Text(title)
                    .font(.headline)
                    .foregroundColor(isSelected ? .white : .primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(isSelected ? color : Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}

// MARK: - Host Row

struct HostRow: View {
    let host: DiscoveredHost
    let onConnect: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "gamecontroller.fill")
                .foregroundColor(.green)
            Text(host.name)
                .font(.subheadline)
            Spacer()
            Button("Connect", action: onConnect)
                .font(.caption.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.green)
                .foregroundColor(.white)
                .clipShape(Capsule())
        }
        .padding(.vertical, 4)
    }
}

// MARK: - IP Connection Sheet

struct IPConnectionSheet: View {
    @Binding var ip: String
    @Binding var port: String
    var onConnect: (String, Int) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Host Address")) {
                    TextField("IP Address (e.g. 192.168.1.10)", text: $ip)
                        .keyboardType(.decimalPad)
                        .autocorrectionDisabled()

                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)
                }

                Section {
                    Button("Connect") {
                        let portNum = Int(port) ?? LinkConstants.defaultPort
                        onConnect(ip.trimmingCharacters(in: .whitespaces), portNum)
                    }
                    .disabled(ip.isEmpty)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .foregroundColor(.blue)
                }
            }
            .navigationTitle("Connect by IP")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
