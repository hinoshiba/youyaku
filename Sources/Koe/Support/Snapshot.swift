import AppKit
import SwiftUI

// UI 検証用: `Koe --snapshot <dir>` で各画面をオフスクリーンレンダリングして PNG 出力する
@MainActor
enum Snapshot {
    static func runIfRequested() -> Bool {
        guard let index = CommandLine.arguments.firstIndex(of: "--snapshot"),
              CommandLine.arguments.count > index + 1 else { return false }
        let dir = CommandLine.arguments[index + 1]
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        Task { @MainActor in
            await run(dir: dir)
            NSApp.terminate(nil)
        }
        return true
    }

    private static func run(dir: String) async {
        let app = AppState.shared
        let wm = WindowManager.shared

        for (name, tab) in [
            ("main_home", MainTab.home),
            ("main_models", .models),
            ("main_history", .history),
            ("main_settings", .settings),
        ] {
            wm.tab = tab
            let view = MainWindowView()
                .environmentObject(app)
                .environmentObject(wm)
            await snap(AnyView(view), size: NSSize(width: 1060, height: 700), path: "\(dir)/\(name).png")
        }

        app.transcript = "えーっと、このプロジェクトのログイン画面なんだけど、あの、パスワードリセットのメールがなんか届かないっていうバグを直してほしいんだよね"
        app.speech.setPartialForPreview(app.transcript)
        app.phase = .recording
        await snap(AnyView(HUDView().environmentObject(app)), size: NSSize(width: 660, height: 320), path: "\(dir)/hud_recording.png")

        app.refined = """
        ログイン画面でパスワードリセットのメールが届かない不具合を修正してください。

        - 対象: ログイン画面のパスワードリセット機能
        - 現象: リセットメールが送信されない、または届かない
        - 期待する動作: リセット申請後、メールが確実に送信される
        """
        app.phase = .result
        await snap(AnyView(HUDView().environmentObject(app)), size: NSSize(width: 660, height: 320), path: "\(dir)/hud_result.png")
        app.phase = .idle

        let menuView = VStack(spacing: 0) {
            MenuBarView().environmentObject(app)
            Spacer(minLength: 0)
        }
        .background(.regularMaterial)
        await snap(AnyView(menuView), size: NSSize(width: 340, height: 330), path: "\(dir)/menubar.png")
    }

    private static func snap(_ view: AnyView, size: NSSize, path: String) async {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.appearance = NSAppearance(named: .darkAqua)

        // SwiftUI の非同期レイアウトを待つ
        try? await Task.sleep(nanoseconds: 900_000_000)
        host.layoutSubtreeIfNeeded()

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
        window.orderOut(nil)
    }
}
