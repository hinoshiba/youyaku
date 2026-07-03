import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum DeliveryResult {
    case pasted
    case copiedOnly
    case needsAccessibility

    var message: String {
        switch self {
        case .pasted:
            return tr("貼り付けました", "Pasted")
        case .copiedOnly:
            return tr("クリップボードにコピーしました", "Copied to clipboard")
        case .needsAccessibility:
            return tr("コピーしました(自動貼り付けにはアクセシビリティ権限が必要です)",
                      "Copied (auto-paste requires Accessibility permission)")
        }
    }
}

@MainActor
enum Paster {
    private static var restoreWork: DispatchWorkItem?

    static func deliver(_ text: String, paste: Bool, keepInClipboard: Bool) -> DeliveryResult {
        let pasteboard = NSPasteboard.general

        // 復元用バックアップ。画像・ファイル・リッチテキストも失わないよう全タイプを複製する
        let backup: [NSPasteboardItem]? = keepInClipboard ? nil : backupItems(pasteboard)

        restoreWork?.cancel()
        restoreWork = nil

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let ourChangeCount = pasteboard.changeCount

        guard paste else { return .copiedOnly }

        // 貼り付け先が Youyaku 自身(メインウィンドウから開始した場合)なら自動貼り付けしない
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier {
            return .copiedOnly
        }
        // セキュア入力中(パスワード欄など)は合成キーイベントが黙って破棄されるため、
        // 成功と偽らずコピーのみにフォールバックする
        if IsSecureEventInputEnabled() {
            return .copiedOnly
        }
        guard AXIsProcessTrusted() else { return .needsAccessibility }

        // HUD は非アクティブ化パネルなので、最前面アプリにそのまま ⌘V が届く
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            sendCmdV()
            if let backup {
                let work = DispatchWorkItem {
                    let pb = NSPasteboard.general
                    // 貼り付け後にユーザーが別の内容をコピーしていたら上書きしない
                    guard pb.changeCount == ourChangeCount else { return }
                    pb.clearContents()
                    pb.writeObjects(backup)
                }
                restoreWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
            }
        }
        return .pasted
    }

    // クリップボードの全アイテム・全タイプを複製する(復元用)
    private static func backupItems(_ pasteboard: NSPasteboard) -> [NSPasteboardItem]? {
        guard let items = pasteboard.pasteboardItems, !items.isEmpty else { return nil }
        var copies: [NSPasteboardItem] = []
        for item in items {
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            if !copy.types.isEmpty {
                copies.append(copy)
            }
        }
        return copies.isEmpty ? nil : copies
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
