import Foundation
import SwiftUI

// MARK: - LLM エンジン

enum EngineKind: String, Codable, CaseIterable, Identifiable {
    case builtin   // 内蔵 llama.cpp エンジン(追加インストール不要)
    case ollama    // 既存の Ollama を利用(任意)

    var id: String { rawValue }

    var label: String {
        switch self {
        case .builtin: return tr("内蔵エンジン", "Built-in Engine")
        case .ollama: return "Ollama"
        }
    }

    var help: String {
        switch self {
        case .builtin: return tr("追加インストール不要。モデルはアプリ内から直接ダウンロードします(推奨)", "No extra installation required. Models are downloaded directly in the app (recommended).")
        case .ollama: return tr("すでに Ollama をお使いの方向け。Ollama のモデルをそのまま使えます", "For existing Ollama users. Use your Ollama models as they are.")
        }
    }
}

// MARK: - 整形モード

enum RefineMode: String, Codable, CaseIterable, Identifiable {
    case raw      // 文字起こしのみ
    case clean    // 整文(フィラー除去)
    case command  // AIへの命令文に再構成

    var id: String { rawValue }

    var label: String {
        switch self {
        case .raw: return tr("そのまま", "Raw")
        case .clean: return tr("整文", "Clean Up")
        case .command: return tr("AI命令化", "AI Prompt")
        }
    }

    var icon: String {
        switch self {
        case .raw: return "text.quote"
        case .clean: return "wand.and.stars"
        case .command: return "terminal"
        }
    }

    var help: String {
        switch self {
        case .raw: return tr("音声認識の結果をそのまま使います(LLM不使用)", "Uses the speech recognition result as is (no LLM)")
        case .clean: return tr("フィラーを除去し、読みやすい文章に整えます", "Removes filler words and tidies up the text")
        case .command: return tr("AIアシスタントへの明確な指示文に再構成します", "Restructures your speech into a clear instruction for an AI assistant")
        }
    }
}

// MARK: - 前提プリセット

struct PremisePreset: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var text: String

    static let defaultID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    static var initial: PremisePreset {
        PremisePreset(
            id: defaultID,
            name: "デフォルト",
            text: ""
        )
    }

    static var sample: PremisePreset {
        PremisePreset(
            name: "開発プロジェクト(例)",
            text: """
            - 私はソフトウェアエンジニアで、AIコーディングアシスタントへの指示を作成する
            - 使用技術: TypeScript / React / Node.js
            - 指示文には対象ファイルや期待する動作を明確に含めること
            - 出力形式の指定がない場合は箇条書きで整理すること
            """
        )
    }
}

// MARK: - ショートカット

struct KeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    // ⌥Space
    static let `default` = KeyCombo(keyCode: 49, carbonModifiers: 2048)

    var display: String {
        var s = ""
        if carbonModifiers & 4096 != 0 { s += "⌃" }
        if carbonModifiers & 2048 != 0 { s += "⌥" }
        if carbonModifiers & 512 != 0 { s += "⇧" }
        if carbonModifiers & 256 != 0 { s += "⌘" }
        return s + KeyCombo.keyName(for: keyCode)
    }

    static func keyName(for code: UInt32) -> String {
        let names: [UInt32: String] = [
            49: "Space", 36: "↩", 48: "⇥", 53: "⎋", 51: "⌫", 117: "⌦",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H",
            34: "I", 38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O",
            35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V",
            13: "W", 7: "X", 16: "Y", 6: "Z",
            18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6",
            26: "7", 28: "8", 25: "9", 29: "0",
            27: "-", 24: "=", 33: "[", 30: "]", 41: ";", 39: "'",
            43: ",", 47: ".", 44: "/", 42: "\\", 50: "`"
        ]
        return names[code] ?? "Key\(code)"
    }
}

// MARK: - アプリ設定

struct AppSettings: Codable {
    var hotkey = KeyCombo.default
    var uiLanguage = AppLanguage.japanese

    // 音声認識
    var localeID = "ja-JP"
    var inputDeviceUID: String? = nil    // 使用するマイク(nil = システム標準)。macOS のみ
    var preferOnDevice = true
    var punctuation = true
    var vocabulary = ""                  // レガシー(旧カンマ区切り形式)。初回移行後は未使用
    var vocabularyTerms: [String] = []   // 認識辞書(固有名詞・専門用語を 1 件ずつ登録)
    var autoStop = false
    var autoStopSeconds = 2.0

    // 整形
    var refineMode = RefineMode.command
    var temperature = 0.2
    var premises: [PremisePreset] = [.initial, .sample]
    var activePremiseID: UUID? = PremisePreset.defaultID

    // LLM
    var engine = EngineKind.builtin
    var builtinModelFile: String? = nil   // Models/ 内の GGUF ファイル名
    var model = "gemma3:4b"               // Ollama 用モデルタグ
    var ollamaHost = "http://127.0.0.1:11434"

    // 出力
    var autoPaste = true
    var keepInClipboard = true
    var instantPaste = false     // 整形完了後に確認なしで貼り付け
    var sounds = true

    // 更新チェック(macOS 直販版)。youyaku.hinoshiba.com の appcast.xml を1日1回取得して
    // 新バージョンを通知する。ダウンロード・インストールは毎回利用者の確認を経る(設定でオフ可能)
    var checkForUpdates = true

    var vocabularyList: [String] {
        vocabularyTerms
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // 入力文字列を用語のリストに分解する(カンマ・読点・改行区切りの一括貼り付け対応)
    static func splitTerms(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ",、\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var activePremise: PremisePreset? {
        premises.first { $0.id == activePremiseID }
    }

    // 認識言語の候補(設定・ツールバー・iOS音声入力画面で共通利用)
    struct SpeechLocaleOption: Identifiable, Hashable {
        let id: String      // localeID
        let label: String   // 各言語での名称(自言語表記)
        let short: String   // ツールバー等の省スペース表示
    }

    static let speechLocales: [SpeechLocaleOption] = [
        .init(id: "ja-JP", label: "日本語", short: "あ"),
        .init(id: "en-US", label: "English (US)", short: "EN"),
        .init(id: "zh-CN", label: "中文(简体)", short: "中"),
        .init(id: "ko-KR", label: "한국어", short: "한"),
    ]

    var speechLocaleLabel: String {
        Self.speechLocales.first { $0.id == localeID }?.label ?? localeID
    }

    var speechLocaleShort: String {
        Self.speechLocales.first { $0.id == localeID }?.short ?? localeID
    }

    // UI 表示用のモデル名(HUD のチップ等)
    var activeModelLabel: String {
        switch engine {
        case .builtin:
            guard let file = builtinModelFile else { return tr("モデル未選択", "No Model Selected") }
            return file.hasSuffix(".gguf") ? String(file.dropLast(5)) : file
        case .ollama:
            return model
        }
    }

    // 将来のフィールド追加に耐えるよう、欠損キーはデフォルト値で埋める
    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        hotkey = (try? c.decodeIfPresent(KeyCombo.self, forKey: .hotkey)) ?? d.hotkey
        uiLanguage = (try? c.decodeIfPresent(AppLanguage.self, forKey: .uiLanguage)) ?? d.uiLanguage
        localeID = (try? c.decodeIfPresent(String.self, forKey: .localeID)) ?? d.localeID
        inputDeviceUID = (try? c.decodeIfPresent(String.self, forKey: .inputDeviceUID)) ?? d.inputDeviceUID
        preferOnDevice = (try? c.decodeIfPresent(Bool.self, forKey: .preferOnDevice)) ?? d.preferOnDevice
        punctuation = (try? c.decodeIfPresent(Bool.self, forKey: .punctuation)) ?? d.punctuation
        vocabulary = (try? c.decodeIfPresent(String.self, forKey: .vocabulary)) ?? d.vocabulary
        // 旧カンマ区切り形式からの移行: 新形式が未保存なら旧文字列を分解して取り込む
        if let terms = try? c.decodeIfPresent([String].self, forKey: .vocabularyTerms) {
            vocabularyTerms = terms
        } else {
            vocabularyTerms = Self.splitTerms(vocabulary)
        }
        autoStop = (try? c.decodeIfPresent(Bool.self, forKey: .autoStop)) ?? d.autoStop
        autoStopSeconds = (try? c.decodeIfPresent(Double.self, forKey: .autoStopSeconds)) ?? d.autoStopSeconds
        refineMode = (try? c.decodeIfPresent(RefineMode.self, forKey: .refineMode)) ?? d.refineMode
        temperature = (try? c.decodeIfPresent(Double.self, forKey: .temperature)) ?? d.temperature
        premises = (try? c.decodeIfPresent([PremisePreset].self, forKey: .premises)) ?? d.premises
        activePremiseID = (try? c.decodeIfPresent(UUID.self, forKey: .activePremiseID)) ?? d.activePremiseID
        engine = (try? c.decodeIfPresent(EngineKind.self, forKey: .engine)) ?? d.engine
        builtinModelFile = (try? c.decodeIfPresent(String.self, forKey: .builtinModelFile)) ?? d.builtinModelFile
        model = (try? c.decodeIfPresent(String.self, forKey: .model)) ?? d.model
        ollamaHost = (try? c.decodeIfPresent(String.self, forKey: .ollamaHost)) ?? d.ollamaHost
        autoPaste = (try? c.decodeIfPresent(Bool.self, forKey: .autoPaste)) ?? d.autoPaste
        keepInClipboard = (try? c.decodeIfPresent(Bool.self, forKey: .keepInClipboard)) ?? d.keepInClipboard
        instantPaste = (try? c.decodeIfPresent(Bool.self, forKey: .instantPaste)) ?? d.instantPaste
        sounds = (try? c.decodeIfPresent(Bool.self, forKey: .sounds)) ?? d.sounds
        checkForUpdates = (try? c.decodeIfPresent(Bool.self, forKey: .checkForUpdates)) ?? d.checkForUpdates
    }
}

// MARK: - ストア

@MainActor
final class SettingsStore: ObservableObject {
    @Published var value: AppSettings {
        didSet {
            L10n.current = value.uiLanguage
            scheduleSave()
        }
    }

    private var saveWork: DispatchWorkItem?

    nonisolated static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Youyaku", isDirectory: true)
    }

    private static var fileURL: URL { directory.appendingPathComponent("settings.json") }

    init() {
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: Self.fileURL) {
            if let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
                value = decoded
            } else {
                // 破損したファイルを黙って上書きせず、退避してから初期化する
                // (ユーザーが前提プリセット等を手動復旧できる余地を残す)
                Self.quarantineCorruptFile(Self.fileURL)
                value = AppSettings()
            }
        } else {
            value = AppSettings()
        }
        L10n.current = value.uiLanguage
    }

    /// 読み込めなくなった JSON を <name>.corrupt-<日時> に退避する
    nonisolated static func quarantineCorruptFile(_ url: URL) {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let dest = url.appendingPathExtension("corrupt-\(stamp)")
        try? FileManager.default.moveItem(at: url, to: dest)
        NSLog("Youyaku: could not decode \(url.lastPathComponent); moved to \(dest.lastPathComponent)")
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func saveNow() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(value) {
            do {
                try data.write(to: Self.fileURL, options: Self.writeOptions)
                Self.restrictPermissions(Self.fileURL)
            } catch {
                NSLog("Youyaku: failed to save settings.json: \(error.localizedDescription)")
            }
        }
    }

    // 設定・履歴はディクテーション内容など機微になり得る情報を含むため、
    // iOS はファイル保護クラスを付け、macOS は所有者のみ読み書き可にする
    nonisolated static var writeOptions: Data.WritingOptions {
        #if os(iOS)
        return [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        #else
        return [.atomic]
        #endif
    }

    nonisolated static func restrictPermissions(_ url: URL) {
        #if os(macOS)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        #endif
    }
}
