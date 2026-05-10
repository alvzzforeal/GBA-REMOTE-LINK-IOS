import SwiftUI

struct ContentView: View {
    @EnvironmentObject var romLibrary: ROMLibrary
    @StateObject private var linkSession = LinkCableSession()

    var body: some View {
        TabView {
            ROMListView()
                .tabItem {
                    Label("Library", systemImage: "gamecontroller.fill")
                }
                .environmentObject(linkSession)

            MultiplayerView()
                .tabItem {
                    Label("Multiplayer", systemImage: "wifi")
                }
                .environmentObject(linkSession)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .accentColor(.green)
    }
}

struct SettingsView: View {
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("About")) {
                    LabeledContent("Version", value: "1.0.0")
                    LabeledContent("Emulator Core", value: "mGBA (stub)")
                }
                Section(header: Text("Instructions")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. Import ROMs via the Library tab.")
                        Text("2. Tap a ROM to start the emulator.")
                        Text("3. Use the Multiplayer tab to connect with nearby devices via Wi-Fi.")
                        Text("4. Host a session or join an existing one.")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
                }
                Section(header: Text("Legal")) {
                    Text("This app does not include any ROMs or BIOS files. You must supply your own legally obtained ROMs.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
