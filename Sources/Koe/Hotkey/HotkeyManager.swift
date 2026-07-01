import AppKit
import Carbon.HIToolbox

// Carbon の RegisterEventHotKey によるグローバルショートカット。
// アクセシビリティ権限なしで動作する。
final class HotkeyManager {
    static let shared = HotkeyManager()

    var onHotkey: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerInstalled = false

    private init() {}

    func register(_ combo: KeyCombo) {
        unregister()
        installHandlerIfNeeded()

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4B4F_4521), id: 1) // 'KOE!'
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            hotKeyRef = ref
        }
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
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
        // グローバルホットキーは修飾キー必須(誤爆防止)
        guard mods != 0 else { return nil }
        return KeyCombo(keyCode: UInt32(event.keyCode), carbonModifiers: mods)
    }
}
