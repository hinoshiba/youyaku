import Foundation

// アプリの表示言語モード(設定で切替)
enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case japanese
    case english

    var id: String { rawValue }

    var label: String {
        switch self {
        case .japanese: return "日本語"
        case .english: return "English"
        }
    }
}

// 現在の表示言語。SettingsStore が設定変更のたびに同期し、
// ビューは AppState の変更通知で再描画されるため、切替は即座に全画面へ反映される
enum L10n {
    nonisolated(unsafe) static var current: AppLanguage = .japanese
}

/// UI 文言のローカライズ。呼び出し箇所に日英を並記する(キー間接参照なし)
func tr(_ ja: String, _ en: String) -> String {
    L10n.current == .japanese ? ja : en
}
