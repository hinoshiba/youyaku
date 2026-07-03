import AppKit
import SwiftUI

enum MainTab: String, CaseIterable, Identifiable {
    case home
    case models
    case history
    case settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .home: return tr("ホーム", "Home")
        case .models: return tr("モデル", "Models")
        case .history: return tr("履歴", "History")
        case .settings: return tr("設定", "Settings")
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .models: return "shippingbox"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        }
    }
}

@MainActor
final class WindowManager: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = WindowManager()

    @Published var tab: MainTab = .home

    private var window: NSWindow?

    func show(tab: MainTab? = nil) {
        if let tab {
            self.tab = tab
        }
        NSApp.setActivationPolicy(.regular)
        if window == nil {
            buildWindow()
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildWindow() {
        let content = MainWindowView()
            .environmentObject(AppState.shared)
            .environmentObject(self)

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1060, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: 920, height: 600)
        w.center()
        w.delegate = self
        w.contentViewController = NSHostingController(rootView: content)
        window = w
    }

    func windowWillClose(_ notification: Notification) {
        // メインウィンドウを閉じたらメニューバー常駐に戻る
        NSApp.setActivationPolicy(.accessory)
    }
}
