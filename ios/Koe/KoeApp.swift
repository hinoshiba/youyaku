import SwiftUI

@main
struct KoeApp: App {
    @StateObject private var app = AppModel.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .tint(Brand.primary)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var app: AppModel
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            DictateView(tab: $tab)
                .tabItem { Label(tr("音声入力", "Dictate"), systemImage: "mic.fill") }
                .tag(0)
            ModelsView()
                .tabItem { Label(tr("モデル", "Models"), systemImage: "shippingbox") }
                .tag(1)
            HistoryView()
                .tabItem { Label(tr("履歴", "History"), systemImage: "clock.arrow.circlepath") }
                .tag(2)
            SettingsView()
                .tabItem { Label(tr("設定", "Settings"), systemImage: "gearshape") }
                .tag(3)
        }
    }
}
