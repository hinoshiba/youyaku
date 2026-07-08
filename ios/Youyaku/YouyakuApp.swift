import SwiftUI
import UIKit

@main
struct YouyakuApp: App {
    @StateObject private var app = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .tint(Brand.primary)
                .onChange(of: scenePhase) { _, newPhase in
                    // バックグラウンドでは録音の確定と整形の中断を行う
                    // (Metal 推論はバックグラウンドで実行できずクラッシュするため)
                    if newPhase == .background {
                        app.enteredBackground()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(
                    for: UIApplication.didReceiveMemoryWarningNotification
                )) { _ in
                    // メモリ警告時は整形を中断してからロード済みモデルを解放し、強制終了を避ける
                    app.handleMemoryWarning()
                }
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
