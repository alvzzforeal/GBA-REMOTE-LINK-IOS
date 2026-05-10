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
            let hasDynamicIsland = safeInsets.top >= 51   // DI = 59pt, notch = 44-51pt

            ZStack {
                // Background
                Color(red: 0.04, green: 0.04, blue: 0.08)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Top bar — sits below notch/DI
                    topBar
                        .padding(.top, safeInsets.top + (hasDynamicIsland ? 8 : 2))
                        .padding(.bottom, 4)

                    // GBA screen — grows to fill remaining space
                    screenArea(in: geo, safeInsets: safeInsets)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)

                    // Virtual controls — bottom section
                    VirtualControlsView(
                        inputState: $viewModel.inputState,
                        screenSize: geo.size,
                        onInputChanged: { state in
                            viewModel.applyInput(state)
                            linkSession.sendInputState(state)
                        }
                    )
                    // Respect home indicator / bottom safe area
                    .padding(.bottom, max(safeInsets.bottom, 8))
                }
            }
        }
        .statusBar(hidden: true)
        .ignoresSafeArea(edges: .all)   // We manage all insets manually above
        .onAppear  { viewModel.start(rom: rom, linkSession: linkSession) }
        .onDisappear { viewModel.stop() }
        .alert("Cannot Load ROM", isPresented: Binding(
            get: { viewModel.loadError != nil },
            set: { if !$0 { viewModel.loadError = nil } }
        )) {
            Button("Go Back") { dismiss() }
        } message: {
            Text(viewModel.loadError ?? "")
        }
        .overlay(alignment: .top) {
            if showLinkStatus {
                linkStatusBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
                    .padding(.top, 100)
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Button(action: { dismiss() }) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 38, height: 38)
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .padding(.leading, 16)

            Spacer()

            VStack(spacing: 2) {
                Text(rom.displayName)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text("GAME BOY ADVANCE")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                    .kerning(1.5)
            }

            Spacer()

            Button(action: {
                withAnimation(.spring(response: 0.3)) { showLinkStatus.toggle() }
            }) {
                ZStack {
                    Circle()
                        .fill(linkStatusColor.opacity(0.15))
                        .frame(width: 38, height: 38)
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
    // Maintains exact 240:160 (3:2) GBA aspect ratio.
    // Fills available vertical space without overflowing into controls or top bar.

    private func screenArea(in geo: GeometryProxy, safeInsets: EdgeInsets) -> some View {
        GeometryReader { screenGeo in
            let availW = screenGeo.size.width
            let availH = screenGeo.size.height

            // Scale to fit 240×160 within available area, preserving ratio
            let scaleW = availW / 240.0
            let scaleH = availH / 160.0
            let scale  = min(scaleW, scaleH)
            let screenW = (240.0 * scale).rounded()
            let screenH = (160.0 * scale).rounded()

            ZStack {
                // Outer bezel / glow
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(red: 0.06, green: 0.05, blue: 0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.15), Color.white.opacity(0.03)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .frame(width: screenW + 20, height: screenH + 20)
                    .shadow(color: Color.purple.opacity(0.20), radius: 28)
                    .shadow(color: .black.opacity(0.65), radius: 18, x: 0, y: 10)

                // Screen content
                ZStack {
                    Color.black

                    if let image = viewModel.currentFrame {
                        // Real frame from emulator (or stub demo)
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .interpolation(.none)   // pixel-perfect, no blurring
                            .frame(width: screenW, height: screenH)
                    } else {
                        // Show boot screen until first frame arrives
                        BootScreen(gameName: rom.displayName)
                            .frame(width: screenW, height: screenH)
                    }
                }
                .frame(width: screenW, height: screenH)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    // Scanline overlay (subtle CRT effect)
                    ScanlineOverlay()
                        .frame(width: screenW, height: screenH)
                        .allowsHitTesting(false)
                )

                // STUB WARNING BADGE — shown when mGBA is not linked
                if viewModel.isStub {
                    VStack {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.yellow)
                            Text("DEMO MODE – mGBA não integrado")
                                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                .foregroundColor(.yellow)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.72))
                        .clipShape(Capsule())
                        .padding(.top, 6)

                        Spacer()
                    }
                    .frame(width: screenW, height: screenH)
                    .allowsHitTesting(false)
                }
            }
            // Centre the screen within the available space
            .frame(width: availW, height: availH)
        }
    }

    // MARK: - Link Status Banner

    private var linkStatusBanner: some View {
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
        .padding(.horizontal, 40)
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
            let spacing: CGFloat = 3
            var y: CGFloat = 0
            while y < size.height {
                ctx.fill(
                    Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                    with: .color(.black.opacity(0.09))
                )
                y += spacing
            }
        }
    }
}

// MARK: - Boot Screen
// Shown until the first frame arrives from the emulator.

struct BootScreen: View {
    let gameName: String
    @State private var pulse = false
    @State private var glow  = false

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.05, blue: 0.10)

            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(glow ? 0.30 : 0.10))
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
                    .padding(.horizontal, 12)

                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(Color.white.opacity(pulse ? 0.85 : 0.20))
                            .frame(width: 4, height: 4)
                            .animation(.easeInOut(duration: 0.5)
                                .repeatForever()
                                .delay(Double(i) * 0.18),
                                value: pulse)
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
    @Published var loadError: String?
    @Published var isStub = false

    private let core = GBAEmulatorCore()
    private weak var linkSession: LinkCableSession?

    func start(rom: ROMFile, linkSession: LinkCableSession) {
        self.linkSession = linkSession

        // Wire frame callback — this is what puts pixels on screen
        core.frameCallback = { [weak self] image in
            self?.currentFrame = image
        }

        linkSession.onSerialData = { bytes in
            print("[Link] Received \(bytes.count) serial bytes")
        }

        guard let url = rom.resolveURL() else {
            loadError = "ROM não encontrada. Reimporte o arquivo via Files app.\n(resolveURL() retornou nil para \(rom.fileName))"
            print("[EmulatorVM] resolveURL() returned nil for \(rom.fileName)")
            return
        }

        do {
            try core.loadROM(at: url)
            isStub = core.isStub
            core.reset()
            core.startDisplayLink()
            print("[EmulatorVM] Display link started | stub=\(core.isStub)")
        } catch {
            loadError = "Falha ao carregar ROM:\n\(error.localizedDescription)"
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
