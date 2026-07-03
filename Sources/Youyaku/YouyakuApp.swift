import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if SelfTest.runIfRequested() { return }
        if Snapshot.runIfRequested() { return }

        // 二重起動を防ぐ(メニューバーアイコンの重複防止)
        if let bundleID = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { $0 != NSRunningApplication.current }
            if !others.isEmpty {
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
