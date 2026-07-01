import AppKit
import ApplicationServices

enum DeliveryResult {
    case pasted
    case copiedOnly
    case needsAccessibility

    var message: String {
        switch self {
        case .pasted: return "貼り付けました"
        case .copiedOnly: return "クリップボードにコピーしました"
        case .needsAccessibility: return "コピーしました(自動貼り付けにはアクセシビリティ権限が必要です)"
        }
    }
}

@MainActor
enum Paster {
    static func deliver(_ text: String, paste: Bool, keepInClipboard: Bool) -> DeliveryResult {
        let pasteboard = NSPasteboard.general
        let previous = keepInClipboard ? nil : pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard paste else { return .copiedOnly }
        guard AXIsProcessTrusted() else { return .needsAccessibility }

        // HUD は非アクティブ化パネルなので、最前面アプリにそのまま ⌘V が届く
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            sendCmdV()
            if let previous {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(previous, forType: .string)
                }
            }
        }
        return .pasted
    }

    private static func sendCmdV() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let vKeyCode: CGKeyCode = 9
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }
}
