import AVFoundation
import AppKit
import ApplicationServices
import Speech

enum PermissionState {
    case granted
    case denied
    case notDetermined

    var label: String {
        switch self {
        case .granted: return tr("許可済み", "Granted")
        case .denied: return tr("未許可", "Denied")
        case .notDetermined: return tr("未設定", "Not Set")
        }
    }
}

@MainActor
enum Permissions {
    static var microphone: PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    static var speech: PermissionState {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    static var accessibility: Bool {
        AXIsProcessTrusted()
    }

    struct EnsureResult {
        var ok: Bool
        var message: String
    }

    /// マイクと音声認識の権限を(必要ならリクエストして)確認する
    static func ensureSpeechAndMic() async -> EnsureResult {
        let micGranted = await AVCaptureDevice.requestAccess(for: .audio)
        guard micGranted else {
            return EnsureResult(ok: false, message: tr("マイクへのアクセスが許可されていません。システム設定から許可してください。", "Microphone access is not allowed. Please allow it in System Settings."))
        }

        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else {
            return EnsureResult(ok: false, message: tr("音声認識が許可されていません。システム設定から許可してください。", "Speech recognition is not allowed. Please allow it in System Settings."))
        }
        return EnsureResult(ok: true, message: "")
    }

    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// アクセシビリティの TCC 登録をリセットする。
    /// ad-hoc 署名では再ビルドのたびに登録が古いバイナリに紐づいたまま残り、
    /// システム設定のトグルが ON でも実際には拒否される。許可し直す前に
    /// 古い登録を消しておくことで「許可したのに効かない」状態を自己修復する。
    static func resetAccessibilityRegistration() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", Bundle.main.bundleIdentifier ?? "com.hinoshiba.youyaku"]
        try? process.run()
        process.waitUntilExit()
    }

    static func openSystemSettings(pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openMicrophoneSettings() { openSystemSettings(pane: "Privacy_Microphone") }
    static func openSpeechSettings() { openSystemSettings(pane: "Privacy_SpeechRecognition") }
    static func openAccessibilitySettings() { openSystemSettings(pane: "Privacy_Accessibility") }
}
