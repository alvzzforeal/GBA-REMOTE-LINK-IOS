import Foundation
import SwiftUI

// MARK: - ROM File Model

struct ROMFile: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var fileName: String
    var fileSize: Int64
    var importedAt: Date
    var bookmarkData: Data?

    var displayName: String {
        fileName.replacingOccurrences(of: ".gba", with: "", options: .caseInsensitive)
    }

    var formattedSize: String {
        let mb = Double(fileSize) / (1024 * 1024)
        return String(format: "%.2f MB", mb)
    }

    func resolveURL() -> URL? {
        guard let data = bookmarkData else { return nil }
        var stale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: .withoutUI,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
    }
}

// MARK: - ROM Library

class ROMLibrary: ObservableObject {
    @Published var roms: [ROMFile] = []

    private let storageKey = "gba_rom_library"
    private let romsDirectory: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        romsDirectory = docs.appendingPathComponent("ROMs", isDirectory: true)
        try? FileManager.default.createDirectory(at: romsDirectory, withIntermediateDirectories: true)
        loadLibrary()
    }

    // MARK: - Import ROM from file picker

    func importROM(from sourceURL: URL) throws -> ROMFile {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }

        let fileName = sourceURL.lastPathComponent
        guard fileName.lowercased().hasSuffix(".gba") else {
            throw ROMError.invalidFormat
        }

        let destURL = romsDirectory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destURL)

        let attrs = try FileManager.default.attributesOfItem(atPath: destURL.path)
        let size = attrs[.size] as? Int64 ?? 0

        let bookmarkData = try destURL.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        let rom = ROMFile(
            name: fileName,
            fileName: fileName,
            fileSize: size,
            importedAt: Date(),
            bookmarkData: bookmarkData
        )

        DispatchQueue.main.async {
            self.roms.append(rom)
            self.saveLibrary()
        }
        return rom
    }

    func deleteROM(_ rom: ROMFile) {
        if let url = rom.resolveURL() {
            try? FileManager.default.removeItem(at: url)
        }
        roms.removeAll { $0.id == rom.id }
        saveLibrary()
    }

    // MARK: - Persistence

    private func saveLibrary() {
        if let data = try? JSONEncoder().encode(roms) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadLibrary() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ROMFile].self, from: data) else { return }
        roms = decoded
    }
}

// MARK: - Errors

enum ROMError: LocalizedError {
    case invalidFormat
    case fileNotFound
    case loadFailed

    var errorDescription: String? {
        switch self {
        case .invalidFormat: return "Invalid file format. Only .gba files are supported."
        case .fileNotFound:  return "ROM file not found."
        case .loadFailed:    return "Failed to load ROM."
        }
    }
}
