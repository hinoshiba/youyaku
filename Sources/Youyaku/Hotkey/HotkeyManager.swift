import AppKit
import Carbon.HIToolbox

// Carbon の RegisterEventHotKey によるグローバルショートカット。
// アクセシビリティ権限なしで動作する。
final class HotkeyManager {
    static let shared = HotkeyManager()

    var onHotkey: (() -> Void)?

    private(set) var current: KeyCombo?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerInstalled = false
    private var nextID: UInt32 = 1

    private init() {}

    /// 指定のショートカットを登録する。成功したら true。
    /// 競合などで失敗した場合は false を返し、直前の登録はそのまま維持する
    /// (動作していたショートカットを失わないため)。
    @discardableResult
    func register(_ combo: KeyCombo) -> Bool {
        installHandlerIfNeeded()

        // 既に同じ組み合わせが有効なら何もしない
        if current == combo, hotKeyRef != nil { return true }

        var ref: EventHotKeyRef?
        // 新旧が一瞬併存しても衝突しないよう、毎回異なる ID を使う
        let hotKeyID = EventHotKeyID(signature: OSType(0x5959_4B21), id: nextID) // 'YYK!'
        nextID &+= 1
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let newRef = ref else {
            return false // 既存の登録は維持
        }

        if let old = hotKeyRef {
            UnregisterEventHotKey(old)
        }
        hotKeyRef = newRef
        current = combo
        return true
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        current = nil
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            DispatchQueue.main.async {
                HotkeyManager.shared.onHotkey?()
            }
            return noErr
        }, 1, &spec, nil, nil)
        handlerInstalled = true
    }
}

extension KeyCombo {
    // NSEvent から KeyCombo を生成(レコーダー用)
    static func from(event: NSEvent) -> KeyCombo? {
        var mods: UInt32 = 0
        let flags = event.modifierFlags
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        let keyCode = UInt32(event.keyCode)
        // グローバルホットキーは誤爆防止のため修飾キー必須。
        // ただしファンクションキー(F1〜F20)は単独でも安全なので許可する。
        guard mods != 0 || isFunctionKey(keyCode) else { return nil }
        return KeyCombo(keyCode: keyCode, carbonModifiers: mods)
    }

    static func isFunctionKey(_ keyCode: UInt32) -> Bool {
        // F1〜F20 の keyCode
        let fKeys: Set<UInt32> = [
            122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, // F1-F12
            105, 107, 113, 106, 64, 79, 80, 90                       // F13-F20
        ]
        return fKeys.contains(keyCode)
    }
}
