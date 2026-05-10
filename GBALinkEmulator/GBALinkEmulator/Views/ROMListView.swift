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
        NavigationView {
            ZStack {
                // Background
                Color(red: 0.06, green: 0.05, blue: 0.09)
                    .ignoresSafeArea()

                Group {
                    if romLibrary.roms.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 0) {
                            // Search bar
                            searchBar
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                                .padding(.bottom, 12)

                            if viewMode == .grid {
                                romGrid
                            } else {
                                romList
                            }
                        }
                    }
                }
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
                    HStack(spacing: 8) {
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
                                    .fill(LinearGradient(colors: [.purple, .indigo],
                                                        startPoint: .topLeading, endPoint: .bottomTrailing))
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
            .alert("Import Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Unknown error")
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

            TextField("Search ROMs...", text: $searchText)
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

    private var romGrid: some View {
        GeometryReader { geo in
            let columns = geo.size.width > 500 ? 4 : 3
            let spacing: CGFloat = 12
            let padding: CGFloat = 16
            let itemW = (geo.size.width - padding * 2 - spacing * CGFloat(columns - 1)) / CGFloat(columns)

            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(itemW), spacing: spacing), count: columns),
                    spacing: spacing
                ) {
                    ForEach(filteredROMs) { rom in
                        ROMGridCell(rom: rom)
                            .onTapGesture { launchROM(rom) }
                            .contextMenu {
                                Button(role: .destructive) { romLibrary.deleteROM(rom) }
                                    label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                }
                .padding(.horizontal, padding)
                .padding(.bottom, 24)
            }
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
                                label: { Label("Delete", systemImage: "trash") }
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
                Text("No ROMs Yet")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("Import your .gba files from\nthe Files app to get started.")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
            }

            Button(action: { showFilePicker = true }) {
                Label("Import ROM", systemImage: "plus")
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
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
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
        // Search for cover in app bundle / documents: "<GameName>.png" or "<GameName>.jpg"
        let candidates = [rom.displayName, rom.fileName.replacingOccurrences(of: ".gba", with: "")]
        for name in candidates {
            // Bundle
            if let img = UIImage(named: name) { coverImage = img; return }
            // Documents/Covers folder
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
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
        for name in candidates {
            if let img = UIImage(named: name) { coverImage = img; return }
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            for ext in ["png", "jpg", "jpeg"] {
                let url = docs.appendingPathComponent("Covers/\(name).\(ext)")
                if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                    coverImage = img; return
                }
            }
        }
    }
}

// MARK: - GBA Cartridge Icon (default, when no cover found)

struct GBACartridgeIcon: View {
    /// Pass nil to fill parent automatically
    let size: CGFloat?

    var body: some View {
        let s = size ?? 48
        ZStack {
            // Cartridge body
            RoundedRectangle(cornerRadius: s * 0.12)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.9), Color(white: 0.72)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(width: s * 0.72, height: s * 0.9)

            // Label sticker
            RoundedRectangle(cornerRadius: s * 0.06)
                .fill(
                    LinearGradient(
                        colors: [Color.purple.opacity(0.85), Color.indigo.opacity(0.85)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(width: s * 0.56, height: s * 0.44)
                .offset(y: -s * 0.06)

            // GBA text on label
            Text("GBA")
                .font(.system(size: s * 0.14, weight: .black, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .kerning(1)
                .offset(y: -s * 0.06)

            // Bottom connector notch
            RoundedRectangle(cornerRadius: s * 0.04)
                .fill(Color(white: 0.55))
                .frame(width: s * 0.48, height: s * 0.1)
                .offset(y: s * 0.42)
        }
    }
}

// MARK: - Game palette helper (deterministic color per game name)

private func gamePalette(for name: String) -> [Color] {
    let palettes: [[Color]] = [
        [Color(red: 0.5, green: 0.1, blue: 0.8), Color(red: 0.2, green: 0.05, blue: 0.5)],
        [Color(red: 0.1, green: 0.6, blue: 0.9), Color(red: 0.05, green: 0.3, blue: 0.6)],
        [Color(red: 0.9, green: 0.3, blue: 0.1), Color(red: 0.6, green: 0.1, blue: 0.05)],
        [Color(red: 0.1, green: 0.75, blue: 0.4), Color(red: 0.05, green: 0.4, blue: 0.2)],
        [Color(red: 0.85, green: 0.6, blue: 0.0), Color(red: 0.5, green: 0.3, blue: 0.0)],
        [Color(red: 0.7, green: 0.1, blue: 0.5), Color(red: 0.4, green: 0.05, blue: 0.3)],
    ]
    let idx = abs(name.hashValue) % palettes.count
    return palettes[idx]
}
