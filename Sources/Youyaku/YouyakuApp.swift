import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    // 二重起動で自動終了する側のインスタンスか(終了時に設定を保存しない)
    private var isDuplicateInstance = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if SelfTest.runIfRequested() { return }
        if Snapshot.runIfRequested() { return }

        // 二重起動を防ぐ(メニューバーアイコンの重複防止)。
        // ただしバンドルがディスクから消えている既存インスタンスは、再ビルドや
        // 入れ替えで実体を失った「ゴースト」。TCC の検証に失敗して録音を開始できない
        // (ショートカットを押しても HUD が出ない)ため、退かずにこちらが引き継ぐ
        if let bundleID = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { $0 != NSRunningApplication.current }
            let ghosts = others.filter { other in
                guard let url = other.bundleURL else { return true }
                return !FileManager.default.fileExists(atPath: url.path)
            }
            if let live = others.first(where: { !ghosts.contains($0) }) {
                isDuplicateInstance = true
                live.activate()
                NSApp.terminate(nil)
                return
            }
            if !ghosts.isEmpty {
                // ゴーストが完全に消えてから起動を続ける(ゴーストが保持している
                // グローバルショートカットの登録と競合しないように)
                Task { @MainActor in
                    await Self.terminate(ghosts: ghosts)
                    AppState.shared.bootstrap()
                }
                return
            }
        }

        AppState.shared.bootstrap()
    }

    // 通常終了を要求し、1 秒応じなければ強制終了する(最長 2.5 秒待つ)。
    // 設定・履歴は変更のたびに保存されているため、強制終了でもデータは失われない
    private static func terminate(ghosts: [NSRunningApplication]) async {
        ghosts.forEach { $0.terminate() }
        for step in 0..<25 {
            if ghosts.allSatisfy(\.isTerminated) { return }
            if step == 10 {
                ghosts.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            WindowManager.shared.show()
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 二重起動側が保存すると、稼働中インスタンスの設定を古い内容で上書きしてしまう
        guard !isDuplicateInstance else { return }
        AppState.shared.settings.saveNow()
        LlamaEngine.shared.unloadSync()
    }
}

@main
struct YouyakuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var app = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(app)
        } label: {
            MenuBarLabel()
                .environmentObject(app)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabel: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        Image(systemName: iconName)
    }

    private var iconName: String {
        switch app.phase {
        case .recording: return "waveform.badge.mic"
        case .refining: return "waveform.badge.magnifyingglass"
        default: return "waveform"
        }
    }
}
