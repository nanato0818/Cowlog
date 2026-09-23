import SwiftUI

@main
struct CowlogApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("優先一覧", systemImage: "list.bullet.clipboard") }
            OverviewMapView()
                .tabItem { Label("地図", systemImage: "map") }
            SettingsView()
                .tabItem { Label("接続設定", systemImage: "gearshape") }
        }
    }
}
