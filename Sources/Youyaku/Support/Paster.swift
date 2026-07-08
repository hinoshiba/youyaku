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
            return tr("クリップボードにコピーしました(自動貼り付けは行われませんでした)",
                      "Copied to clipboard (auto-paste was not performed)")
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
            }
        }
        return .pasted
    }

    // パスワードマネージャ等が付ける「秘匿内容」マーカー(nspasteboard.org 規約)
    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    // クリップボードの全アイテム・全タイプを複製する(復元用)
    private static func backupItems(_ pasteboard: NSPasteboard) -> [NSPasteboardItem]? {
        guard let items = pasteboard.pasteboardItems, !items.isEmpty else { return nil }
        // 秘匿マーカー付き(パスワードマネージャ由来)は復元しない。
        // 遅延復元でパスワードがクリップボードに蘇り、意図せず貼られる事故を防ぐ
        if items.contains(where: { $0.types.contains(concealedType) }) {
            return nil
        }
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
        // "v" のキーコードは配列依存(Dvorak 等では 9 ではない)。
        // 現在のレイアウトから解決し、失敗時のみ US 配列の 9 にフォールバックする
        let vKeyCode: CGKeyCode = keyCode(for: "v") ?? 9
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }

    // 現在のキーボードレイアウトで指定の文字を入力するキーコードを全走査で探す
    private static func keyCode(for character: Character) -> CGKeyCode? {
        guard let sourceRef = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPointer = TISGetInputSourceProperty(sourceRef, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPointer).takeUnretainedValue() as Data
        return layoutData.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> CGKeyCode? in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return nil
            }
            for code in 0..<CGKeyCode(128) {
                var deadKeyState: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(
                    layout, code, UInt16(kUCKeyActionDisplay), 0,
                    UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                    &deadKeyState, chars.count, &length, &chars
                )
                if status == noErr, length == 1,
                   let scalar = Unicode.Scalar(chars[0]),
                   Character(scalar) == character {
                    return code
                }
            }
            return nil
        }
    }
}
