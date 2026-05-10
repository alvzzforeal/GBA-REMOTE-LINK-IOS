import SwiftUI
import CoreGraphics

// MARK: - Emulator View

struct EmulatorView: View {
    let rom: ROMFile
    @EnvironmentObject var linkSession: LinkCableSession
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel: EmulatorViewModel
    @State private var showLinkStatus = false

    init(rom: ROMFile) {
        self.rom = rom
        _viewModel = StateObject(wrappedValue: EmulatorViewModel())
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    screenArea(in: geo)
                    Spacer()
                    VirtualControlsView(
                        inputState: $viewModel.inputState,
                        onInputChanged: { state in
                            viewModel.applyInput(state)
                            // Broadcast input over link cable
                            linkSession.sendInputState(state)
                        }
                    )
                }
            }
        }
        .statusBar(hidden: true)
        .onAppear {
            viewModel.start(rom: rom, linkSession: linkSession)
        }
        .onDisappear {
            viewModel.stop()
        }
        .overlay(alignment: .top) {
            if showLinkStatus {
                linkStatusBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.leading, 16)

            Spacer()

            Text(rom.displayName)
                .font(.caption.bold())
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(1)

            Spacer()

            // Link status indicator
            Button(action: { withAnimation { showLinkStatus.toggle() } }) {
                Circle()
                    .fill(linkStatusColor)
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
            }
            .padding(.trailing, 16)
        }
        .frame(height: 44)
        .background(Color.black)
    }

    // MARK: - Screen

    private func screenArea(in geo: GeometryProxy) -> some View {
        let maxW = geo.size.width
        let maxH = geo.size.height - 44 - 160
        let scale = min(maxW / 240, maxH / 160)
        let screenW = 240 * scale
        let screenH = 160 * scale

        return ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.black)
                .frame(width: screenW + 8, height: screenH + 8)

            if let image = viewModel.currentFrame {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: screenW, height: screenH)
            } else {
                BootScreen()
                    .frame(width: screenW, height: screenH)
            }
        }
    }

    // MARK: - Link Status Banner

    private var linkStatusBanner: some View {
        VStack {
            Spacer().frame(height: 44)
            HStack {
                Image(systemName: "wifi")
                Text(linkSession.status.description)
                    .font(.caption.bold())
                if linkSession.status.isActive {
                    Spacer()
                    Text(String(format: "%.0f ms", linkSession.latencyMs))
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
    }

    private var linkStatusColor: Color {
        switch linkSession.status {
        case .connected:   return .green
        case .error:       return .red
        case .disconnected: return .gray
        default:           return .yellow
        }
    }
}

// MARK: - Boot Screen (shown before ROM loads)

struct BootScreen: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Color(red: 0.1, green: 0.08, blue: 0.15)

            VStack(spacing: 8) {
                Image(systemName: "gamecontroller.fill")
                    .font(.largeTitle)
                    .foregroundColor(.purple.opacity(0.8))
                    .scaleEffect(pulse ? 1.05 : 0.95)
                    .animation(.easeInOut(duration: 0.8).repeatForever(), value: pulse)

                Text("GBA Link")
                    .font(.headline.bold())
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .onAppear { pulse = true }
    }
}

// MARK: - Emulator View Model

@MainActor
final class EmulatorViewModel: ObservableObject {
    @Published var currentFrame: CGImage?
    @Published var inputState = GBAInputState()

    private let core = GBAEmulatorCore()
    private weak var linkSession: LinkCableSession?

    func start(rom: ROMFile, linkSession: LinkCableSession) {
        self.linkSession = linkSession

        core.frameCallback = { [weak self] image in
            self?.currentFrame = image
        }

        // Receive remote serial data from link cable
        linkSession.onSerialData = { [weak self] bytes in
            // Pass bytes to emulator core's serial/link interface
            // core->linkSerialReceive(bytes)
            print("[Link] Received \(bytes.count) serial bytes")
        }

        guard let url = rom.resolveURL() else { return }
        do {
            try core.loadROM(at: url)
            core.reset()
            core.startDisplayLink()
        } catch {
            print("[EmulatorVM] ROM load error: \(error)")
        }
    }

    func applyInput(_ state: GBAInputState) {
        core.setKeys(state.keyMask)
    }

    func stop() {
        core.stop()
        linkSession?.onSerialData = nil
    }
}
