import SwiftUI
import UIKit
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
            let safeInsets = geo.safeAreaInsets
            // Dynamic Island detection: iPhone 14 Pro+, 15, 17 have top safe area >= 59pt
            let hasDynamicIsland = safeInsets.top >= 59

            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.04, green: 0.04, blue: 0.08),
                             Color(red: 0.08, green: 0.06, blue: 0.12)],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar(hasDynamicIsland: hasDynamicIsland)
                        .padding(.top, hasDynamicIsland ? 16 : 4)

                    Spacer(minLength: 6)

                    screenArea(in: geo, safeInsets: safeInsets)

                    Spacer(minLength: 6)

                    VirtualControlsView(
                        inputState: $viewModel.inputState,
                        screenSize: geo.size,
                        onInputChanged: { [self] state in
                            viewModel.applyInput(state)
                            linkSession.sendInputState(state)
                        }
                    )
                    .padding(.bottom, max(safeInsets.bottom, CGFloat(8)))
                }
            }
        }
        .statusBar(hidden: true)
        .ignoresSafeArea(edges: .bottom)
        .onAppear { viewModel.start(rom: rom, linkSession: linkSession) }
        .onDisappear { viewModel.stop() }
        .overlay(alignment: .top) {
            if showLinkStatus {
                linkStatusBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
    }

    // MARK: - Top Bar

    private func topBar(hasDynamicIsland: Bool) -> some View {
        HStack(spacing: 12) {
            Button(action: { dismiss() }) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 36, height: 36)
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .padding(.leading, 16)

            Spacer()

            VStack(spacing: 1) {
                Text(rom.displayName)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text("GAME BOY ADVANCE")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
                    .kerning(1.5)
            }

            Spacer()

            Button(action: { withAnimation(.spring(response: 0.3)) { showLinkStatus.toggle() } }) {
                ZStack {
                    Circle()
                        .fill(linkStatusColor.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Circle()
                        .fill(linkStatusColor)
                        .frame(width: 9, height: 9)
                }
            }
            .padding(.trailing, 16)
        }
        .frame(height: 44)
    }

    // MARK: - Screen Area

    private func screenArea(in geo: GeometryProxy, safeInsets: EdgeInsets) -> some View {
        let controlsH = controlsHeight(for: geo.size)
        let topBarH: CGFloat = 68
        let verticalPadding: CGFloat = 32
        let reservedH = topBarH + controlsH + safeInsets.bottom + verticalPadding

        let availableW = geo.size.width - 32
        let availableH = geo.size.height - reservedH

        // GBA native: 240x160 (3:2)
        let scaleByW = availableW / 240
        let scaleByH = availableH / 160
        let scale = min(scaleByW, scaleByH, 3.8)
        let screenW = 240 * scale
        let screenH = 160 * scale

        return ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(red: 0.06, green: 0.05, blue: 0.09))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.14), Color.white.opacity(0.03)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
                .frame(width: screenW + 22, height: screenH + 22)
                .shadow(color: Color.purple.opacity(0.18), radius: 24, x: 0, y: 0)
                .shadow(color: .black.opacity(0.7), radius: 18, x: 0, y: 10)

            ZStack {
                Color.black
                if let image = viewModel.currentFrame {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: screenW, height: screenH)
                } else {
                    BootScreen(gameName: rom.displayName)
                        .frame(width: screenW, height: screenH)
                }
            }
            .frame(width: screenW, height: screenH)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                ScanlineOverlay()
                    .frame(width: screenW, height: screenH)
                    .allowsHitTesting(false)
            )
        }
    }

    private func controlsHeight(for size: CGSize) -> CGFloat {
        let scale = min(size.width / 390, 1.5)
        return 180 * scale
    }

    // MARK: - Link Status Banner

    private var linkStatusBanner: some View {
        VStack {
            Spacer().frame(height: 100)
            HStack(spacing: 8) {
                Image(systemName: "wifi")
                    .foregroundColor(linkStatusColor)
                Text(linkSession.status.description)
                    .font(.caption.bold())
                    .foregroundColor(.white)
                if linkSession.status.isActive {
                    Spacer()
                    Text(String(format: "%.0f ms", linkSession.latencyMs))
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.3), radius: 8)
            .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
    }

    private var linkStatusColor: Color {
        switch linkSession.status {
        case .connected:    return .green
        case .error:        return .red
        case .disconnected: return .gray
        default:            return .yellow
        }
    }
}

// MARK: - Scanline Overlay

struct ScanlineOverlay: View {
    var body: some View {
        Canvas { ctx, size in
            let lineSpacing: CGFloat = 3
            var y: CGFloat = 0
            while y < size.height {
                ctx.fill(
                    Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                    with: .color(.black.opacity(0.09))
                )
                y += lineSpacing
            }
        }
    }
}

// MARK: - Boot Screen

struct BootScreen: View {
    let gameName: String
    @State private var pulse = false
    @State private var glow = false

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.05, blue: 0.1)

            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(glow ? 0.3 : 0.1))
                        .frame(width: 72, height: 72)
                        .blur(radius: 14)
                        .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: glow)

                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(
                            LinearGradient(colors: [.purple, .indigo],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .scaleEffect(pulse ? 1.07 : 0.95)
                        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
                }

                Text(gameName)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.75))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)

                HStack(spacing: 5) {
                    ForEach(0..<3) { i in
                        Circle()
                            .fill(Color.white.opacity(pulse ? 0.85 : 0.2))
                            .frame(width: 4, height: 4)
                            .animation(.easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.18), value: pulse)
                    }
                }
            }
        }
        .onAppear { pulse = true; glow = true }
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
        core.frameCallback = { [weak self] image in self?.currentFrame = image }
        linkSession.onSerialData = { bytes in
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

    func applyInput(_ state: GBAInputState) { core.setKeys(state.keyMask) }

    func stop() {
        core.stop()
        linkSession?.onSerialData = nil
    }
}
