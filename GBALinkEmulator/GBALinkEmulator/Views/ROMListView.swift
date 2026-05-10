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

    var body: some View {
        NavigationView {
            Group {
                if romLibrary.roms.isEmpty {
                    emptyState
                } else {
                    romList
                }
            }
            .navigationTitle("GBA Library")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showFilePicker = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.green)
                    }
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [gbaUTType],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .fullScreenCover(isPresented: $showEmulator) {
                if let rom = selectedROM {
                    EmulatorView(rom: rom)
                        .environmentObject(linkSession)
                }
            }
            .alert("Import Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 24) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 72))
                .foregroundColor(.green.opacity(0.7))

            VStack(spacing: 8) {
                Text("No ROMs Yet")
                    .font(.title2.bold())
                Text("Import your .gba ROM files from the Files app.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button(action: { showFilePicker = true }) {
                Label("Import ROM", systemImage: "plus")
                    .font(.headline)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - ROM List

    private var romList: some View {
        List {
            ForEach(romLibrary.roms) { rom in
                ROMRowView(rom: rom)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedROM = rom
                        showEmulator = true
                    }
            }
            .onDelete { offsets in
                offsets.forEach { romLibrary.deleteROM(romLibrary.roms[$0]) }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Import Handler

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                _ = try romLibrary.importROM(from: url)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    // MARK: - GBA UTType

    private var gbaUTType: UTType {
        UTType(filenameExtension: "gba") ?? .data
    }
}

// MARK: - ROM Row

struct ROMRowView: View {
    let rom: ROMFile

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [.green.opacity(0.8), .teal.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                Image(systemName: "cartridge.fill")
                    .font(.title3)
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(rom.displayName)
                    .font(.headline)
                    .lineLimit(1)
                HStack {
                    Text(rom.formattedSize)
                    Text("·")
                    Text(rom.importedAt.formatted(date: .abbreviated, time: .omitted))
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding(.vertical, 4)
    }
}
