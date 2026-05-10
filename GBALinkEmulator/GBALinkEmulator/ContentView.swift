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
        .accentColor(.purple)
        .preferredColorScheme(.dark)
    }
}

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.06, green: 0.05, blue: 0.09).ignoresSafeArea()

                List {
                    Section(header: Text("About").foregroundColor(.white.opacity(0.45))) {
                        settingsRow("Version", value: "1.0.0", icon: "info.circle", color: .blue)
                        settingsRow("Emulator Core", value: "mGBA", icon: "cpu", color: .purple)
                    }
                    .listRowBackground(Color.white.opacity(0.06))

                    Section(header: Text("ROM Covers").foregroundColor(.white.opacity(0.45))) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("To add box art, place image files in the **Covers** folder inside the app's Documents directory.")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.55))
                            Text("Name each file to match the ROM filename (e.g. `Pokemon Ruby.png`).")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.55))
                        }
                        .padding(.vertical, 6)
                    }
                    .listRowBackground(Color.white.opacity(0.06))

                    Section(header: Text("Instructions").foregroundColor(.white.opacity(0.45))) {
                        VStack(alignment: .leading, spacing: 10) {
                            instructionRow("1", "Import ROMs via the Library tab.")
                            instructionRow("2", "Tap a ROM to launch the emulator.")
                            instructionRow("3", "Use the Multiplayer tab to connect via Wi-Fi.")
                            instructionRow("4", "Host a session or join an existing one.")
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Color.white.opacity(0.06))

                    Section(header: Text("Legal").foregroundColor(.white.opacity(0.45))) {
                        Text("This app does not include any ROMs or BIOS files. You must supply your own legally obtained ROMs.")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .listRowBackground(Color.white.opacity(0.06))
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
        .preferredColorScheme(.dark)
    }

    private func settingsRow(_ label: String, value: String, icon: String, color: Color) -> some View {
        HStack {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(color.opacity(0.2))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(color)
            }
            Text(label).foregroundColor(.white)
            Spacer()
            Text(value)
                .foregroundColor(.white.opacity(0.4))
                .font(.system(size: 14))
        }
    }

    private func instructionRow(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.25))
                    .frame(width: 20, height: 20)
                Text(number)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.purple)
            }
            Text(text)
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
        }
    }
}
