import SwiftUI

@main
struct GBALinkEmulatorApp: App {
    @StateObject private var romLibrary = ROMLibrary()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(romLibrary)
        }
    }
}
