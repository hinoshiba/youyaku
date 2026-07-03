import AppKit
import SwiftUI

// 前面アプリを非アクティブ化しないキー入力可能パネル
final class HUDPanel: NSPanel {
    var onKeyDown: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true { return }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        let escEvent = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: windowNumber, context: nil, characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53
        )
        if let escEvent, onKeyDown?(escEvent) == true { return }
        super.cancelOperation(sender)
    }
}

@MainActor
final class HUDController {
    private weak var appState: AppState?
    private var panel: HUDPanel?

    private let size = NSSize(width: 660, height: 320)

    init(appState: AppState) {
        self.appState = appState
    }

    func show() {
        if panel == nil {
            build()
        }
        position()
        panel?.alphaValue = 0
        panel?.orderFrontRegardless()
        panel?.makeKey()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel?.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    private func build() {
        guard let appState else { return }
        let p = HUDPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.onKeyDown = { [weak appState] event in
            appState?.handleHUDKey(event) ?? false
        }

        let host = NSHostingView(rootView: HUDView().environmentObject(appState))
        host.frame = NSRect(origin: .zero, size: size)
        p.contentView = host
        panel = p
    }

    private func position() {
        guard let panel else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }
        let x = frame.midX - size.width / 2
        let y = frame.minY + frame.height * 0.16
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }
}
