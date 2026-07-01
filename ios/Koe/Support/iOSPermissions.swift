import AVFoundation
import Speech
import UIKit

enum PermissionState {
    case granted, denied, notDetermined

    var label: String {
        switch self {
        case .granted: return tr("許可済み", "Granted")
        case .denied: return tr("未許可", "Denied")
        case .notDetermined: return tr("未設定", "Not set")
        }
    }
}

@MainActor
enum Permissions {
    static var microphone: PermissionState {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return .granted
        case .undetermined: return .notDetermined
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

    struct EnsureResult {
        var ok: Bool
        var message: String
    }

    /// マイクと音声認識の権限を(必要ならリクエストして)確認する
    static func ensureSpeechAndMic() async -> EnsureResult {
        let micGranted = await AVAudioApplication.requestRecordPermission()
        guard micGranted else {
            return EnsureResult(ok: false, message: tr(
                "マイクへのアクセスが許可されていません。設定 > Koe から許可してください。",
                "Microphone access is not granted. Enable it in Settings > Koe."))
        }
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechStatus == .authorized else {
            return EnsureResult(ok: false, message: tr(
                "音声認識が許可されていません。設定 > Koe から許可してください。",
                "Speech recognition is not granted. Enable it in Settings > Koe."))
        }
        return EnsureResult(ok: true, message: "")
    }

    static func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
