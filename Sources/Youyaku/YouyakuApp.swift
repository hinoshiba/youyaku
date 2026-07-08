import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    // 二重起動で自動終了する側のインスタンスか(終了時に設定を保存しない)
    private var isDuplicateInstance = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if SelfTest.runIfRequested() { return }
        if Snapshot.runIfRequested() { return }

        // 二重起動を防ぐ(メニューバーアイコンの重複防止)
        if let bundleID = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { $0 != NSRunningApplication.current }
            if !others.isEmpty {
                isDuplicateInstance = true
                others.first?.activate()
                NSApp.terminate(nil)
                return
            }
        }

        AppState.shared.bootstrap()
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
