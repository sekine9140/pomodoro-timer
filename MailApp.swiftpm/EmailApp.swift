import SwiftUI

@main
struct MailApp: App {
    @StateObject private var store = MailStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            InboxView()
                .tabItem {
                    Label("受信トレイ", systemImage: "tray.and.arrow.down")
                }
            SettingsView()
                .tabItem {
                    Label("設定", systemImage: "gear")
                }
        }
    }
}
