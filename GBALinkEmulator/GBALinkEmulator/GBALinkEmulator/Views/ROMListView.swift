import SwiftUI
import UniformTypeIdentifiers

// MARK: - ROM List View

struct ROMListView: View {
    @EnvironmentObject var romLibrary: ROMLibrary
    @EnvironmentObject var linkSession: LinkCableSession

    @State private var showFilePicker = false
    @State private var selectedROM: ROMFile?
    @State private var showEmulator = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var searchText = ""
    @State private var viewMode: ViewMode = .grid

    enum ViewMode { case grid, list }

    private var filteredROMs: [ROMFile] {
        guard !searchText.isEmpty else { return romLibrary.roms }
        return romLibrary.roms.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack {
                    Color(red: 0.06, green: 0.05, blue: 0.09)
                        .ignoresSafeArea()

                    if romLibrary.roms.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 0) {
                            searchBar
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                                .padding(.bottom, 12)

                            if viewMode == .grid {
                                romGrid(in: geo)
                            } else {
                                romList
                            }
                        }
                    }
                }
                // Fill the entire available area
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(
                                LinearGradient(colors: [.purple, .indigo],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                        Text("GBA Library")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 10) {
                        if !romLibrary.roms.isEmpty {
                            Button(action: {
                                withAnimation(.spring(response: 0.3)) {
                                    viewMode = viewMode == .grid ? .list : .grid
                                }
                            }) {
                                Image(systemName: viewMode == .grid ? "list.bullet" : "square.grid.2x2")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }

                        Button(action: { showFilePicker = true }) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(colors: [.purple, .indigo],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                                    )
                                    .frame(width: 30, height: 30)
                                Image(systemName: "plus")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [gbaUTType],
                allowsMultipleSelection: false
            ) { handleImport($0) }
            .fullScreenCover(isPresented: $showEmulator) {
                if let rom = selectedROM {
                    EmulatorView(rom: rom).environmentObject(linkSession)
                }
            }
            .alert("Erro ao Importar", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Erro desconhecido")
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.white.opacity(0.4))
                .font(.system(size: 14))

            TextField("Buscar ROMs...", text: $searchText)
                .font(.system(size: 15, design: .rounded))
                .foregroundColor(.white)
                .tint(.purple)

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.35))
                        .font(.system(size: 14))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // MARK: - Grid View
    // Uses GeometryReader to measure actual width, avoiding fixed sizes that clip on Pro Max.

    private func romGrid(in geo: GeometryProxy) -> some View {
        let columns = geo.size.width > 500 ? 4 : 3
        let spacing: CGFloat  = 12
        let hPadding: CGFloat = 16
        let itemW = (geo.size.width - hPadding * 2 - spacing * CGFloat(columns - 1)) / CGFloat(columns)

        return ScrollView {
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(itemW), spacing: spacing), count: columns),
                spacing: spacing
            ) {
                ForEach(filteredROMs) { rom in
                    ROMGridCell(rom: rom)
                        .onTapGesture { launchROM(rom) }
                        .contextMenu {
                            Button(role: .destructive) { romLibrary.deleteROM(rom) }
                                label: { Label("Apagar", systemImage: "trash") }
                        }
                }
            }
            .padding(.horizontal, hPadding)
            .padding(.bottom, 24)
        }
    }

    // MARK: - List View

    private var romList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(filteredROMs) { rom in
                    ROMListRow(rom: rom)
                        .onTapGesture { launchROM(rom) }
                        .contextMenu {
                            Button(role: .destructive) { romLibrary.deleteROM(rom) }
                                label: { Label("Apagar", systemImage: "trash") }
                        }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.12))
                    .frame(width: 120, height: 120)
                    .blur(radius: 20)
                GBACartridgeIcon(size: 72)
            }

            VStack(spacing: 10) {
                Text("Nenhuma ROM")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("Importe seus arquivos .gba\npelo app Files para começar.")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
            }

            Button(action: { showFilePicker = true }) {
                Label("Importar ROM", systemImage: "plus")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 36)
                    .padding(.vertical, 15)
                    .background(
                        LinearGradient(colors: [.purple, .indigo],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    .shadow(color: .purple.opacity(0.45), radius: 12, x: 0, y: 4)
            }

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Helpers

    private func launchROM(_ rom: ROMFile) {
        selectedROM = rom
        showEmulator = true
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do { _ = try romLibrary.importROM(from: url) }
            catch { errorMessage = error.localizedDescription; showError = true }
        case .failure(let error):
            errorMessage = error.localizedDescription; showError = true
        }
    }

    private var gbaUTType: UTType { UTType(filenameExtension: "gba") ?? .data }
}

// MARK: - ROM Grid Cell

struct ROMGridCell: View {
    let rom: ROMFile
    @State private var coverImage: UIImage? = nil

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: gamePalette(for: rom.displayName),
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .aspectRatio(1.0, contentMode: .fit)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 3)

                if let cover = coverImage {
                    Image(uiImage: cover)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    GBACartridgeIcon(size: nil)
                }
            }
            .onAppear { loadCover() }

            Text(rom.displayName)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private func loadCover() {
        let candidates = [rom.displayName, rom.fileName.replacingOccurrences(of: ".gba", with: "")]
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        for name in candidates {
            if let img = UIImage(named: name) { coverImage = img; return }
            for ext in ["png", "jpg", "jpeg"] {
                let url = docs.appendingPathComponent("Covers/\(name).\(ext)")
                if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                    coverImage = img; return
                }
            }
        }
    }
}

// MARK: - ROM List Row

struct ROMListRow: View {
    let rom: ROMFile
    @State private var coverImage: UIImage? = nil

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: gamePalette(for: rom.displayName),
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)

                if let cover = coverImage {
                    Image(uiImage: cover)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    GBACartridgeIcon(size: 28)
                }
            }
            .onAppear { loadCover() }

            VStack(alignment: .leading, spacing: 4) {
                Text(rom.displayName)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(rom.formattedSize)
                    Text("·")
                    Text(rom.importedAt.formatted(date: .abbreviated, time: .omitted))
                }
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.4))
            }

            Spacer()

            Image(systemName: "play.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.3))
                .padding(.trailing, 4)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func loadCover() {
        let candidates = [rom.displayName, rom.fileName.replacingOccurrences(of: ".gba", with: "")]
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        for name in candidates {
            if let img = UIImage(named: name) { coverImage = img; return }
            for ext in ["png", "jpg", "jpeg"] {
                let url = docs.appendingPathComponent("Covers/\(name).\(ext)")
                if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                    coverImage = img; return
                }
            }
        }
    }
}

// MARK: - GBA Cartridge Icon

struct GBACartridgeIcon: View {
    let size: CGFloat?

    var body: some View {
        let s = size ?? 48
        ZStack {
            RoundedRectangle(cornerRadius: s * 0.12)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.90), Color(white: 0.72)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(width: s * 0.72, height: s * 0.90)

            RoundedRectangle(cornerRadius: s * 0.06)
                .fill(
                    LinearGradient(
                        colors: [Color.purple.opacity(0.85), Color.indigo.opacity(0.85)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(width: s * 0.56, height: s * 0.44)
                .offset(y: -s * 0.06)

            Text("GBA")
                .font(.system(size: s * 0.14, weight: .black, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .kerning(1)
                .offset(y: -s * 0.06)

            RoundedRectangle(cornerRadius: s * 0.04)
                .fill(Color(white: 0.55))
                .frame(width: s * 0.48, height: s * 0.10)
                .offset(y: s * 0.42)
        }
    }
}

// MARK: - Game palette helper (deterministic colour per title)

private func gamePalette(for name: String) -> [Color] {
    let palettes: [[Color]] = [
        [Color(red: 0.50, green: 0.10, blue: 0.80), Color(red: 0.20, green: 0.05, blue: 0.50)],
        [Color(red: 0.10, green: 0.60, blue: 0.90), Color(red: 0.05, green: 0.30, blue: 0.60)],
        [Color(red: 0.90, green: 0.30, blue: 0.10), Color(red: 0.60, green: 0.10, blue: 0.05)],
        [Color(red: 0.10, green: 0.75, blue: 0.40), Color(red: 0.05, green: 0.40, blue: 0.20)],
        [Color(red: 0.85, green: 0.60, blue: 0.00), Color(red: 0.50, green: 0.30, blue: 0.00)],
        [Color(red: 0.70, green: 0.10, blue: 0.50), Color(red: 0.40, green: 0.05, blue: 0.30)],
    ]
    let idx = abs(name.hashValue) % palettes.count
    return palettes[idx]
}
