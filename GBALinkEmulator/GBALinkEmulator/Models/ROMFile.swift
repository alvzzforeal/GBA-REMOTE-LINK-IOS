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

    // Detected game title from ROM header (optional)
    var detectedTitle: String?

    /// Display-friendly title: use detected title from ROM header if available,
    /// otherwise clean up the filename.
    var displayName: String {
        if let title = detectedTitle, !title.isEmpty {
            return title
        }
        return fileName
            .replacingOccurrences(of: ".gba", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .capitalized
    }

    var formattedSize: String {
        let mb = Double(fileSize) / (1024 * 1024)
        if mb >= 1 { return String(format: "%.1f MB", mb) }
        let kb = Double(fileSize) / 1024
        return String(format: "%.0f KB", kb)
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

// MARK: - ROM Header Parser
// GBA ROM header: bytes 0xA0–0xAB = 12-byte ASCII game title (zero-padded)

struct GBAROMHeader {
    let title: String        // 12 chars max
    let gameCode: String     // 4 chars (e.g. "AXVE" for Pokémon Ruby)
    let makerCode: String    // 2 chars

    static func parse(from url: URL) -> GBAROMHeader? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }

        // Read first 192 bytes (0xC0) to cover header
        fh.seek(toFileOffset: 0xA0)
        let data = fh.readData(ofLength: 18)
        guard data.count >= 18 else { return nil }

        let titleBytes = data.subdata(in: 0..<12)
        let codeBytes  = data.subdata(in: 12..<16)
        let makerBytes = data.subdata(in: 16..<18)

        func asciiString(from d: Data) -> String {
            String(bytes: d.filter { $0 != 0 }, encoding: .ascii)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        let title = asciiString(from: titleBytes)
        let code  = asciiString(from: codeBytes)
        let maker = asciiString(from: makerBytes)
        guard !title.isEmpty else { return nil }
        return GBAROMHeader(title: title, gameCode: code, makerCode: maker)
    }
}

// MARK: - ROM Library

class ROMLibrary: ObservableObject {
    @Published var roms: [ROMFile] = []

    private let storageKey = "gba_rom_library_v2"
    private let romsDirectory: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        romsDirectory = docs.appendingPathComponent("ROMs", isDirectory: true)
        try? FileManager.default.createDirectory(at: romsDirectory, withIntermediateDirectories: true)
        // Also create Covers directory for user-supplied art
        let coversDir = docs.appendingPathComponent("Covers", isDirectory: true)
        try? FileManager.default.createDirectory(at: coversDir, withIntermediateDirectories: true)
        loadLibrary()
    }

    // MARK: - Import

    func importROM(from sourceURL: URL) throws -> ROMFile {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }

        let fileName = sourceURL.lastPathComponent
        guard fileName.lowercased().hasSuffix(".gba") else { throw ROMError.invalidFormat }

        let destURL = romsDirectory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destURL)

        let attrs = try FileManager.default.attributesOfItem(atPath: destURL.path)
        let size = attrs[.size] as? Int64 ?? 0

        // Parse game title from ROM header
        let header = GBAROMHeader.parse(from: destURL)
        let detectedTitle: String? = header.map { h in
            // Prefer human-readable title from header; fall back to nil
            h.title.isEmpty ? nil : h.title.localizedCapitalized
        } ?? nil

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
            bookmarkData: bookmarkData,
            detectedTitle: detectedTitle
        )

        DispatchQueue.main.async {
            self.roms.append(rom)
            self.saveLibrary()
        }
        return rom
    }

    func deleteROM(_ rom: ROMFile) {
        if let url = rom.resolveURL() { try? FileManager.default.removeItem(at: url) }
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
    case invalidFormat, fileNotFound, loadFailed

    var errorDescription: String? {
        switch self {
        case .invalidFormat: return "Invalid file format. Only .gba files are supported."
        case .fileNotFound:  return "ROM file not found."
        case .loadFailed:    return "Failed to load ROM."
        }
    }
}
