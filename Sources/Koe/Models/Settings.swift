import Foundation
import SwiftUI

// MARK: - LLM エンジン

enum EngineKind: String, Codable, CaseIterable, Identifiable {
    case builtin   // 内蔵 llama.cpp エンジン(追加インストール不要)
    case ollama    // 既存の Ollama を利用(任意)

    var id: String { rawValue }

    var label: String {
        switch self {
        case .builtin: return "内蔵エンジン"
        case .ollama: return "Ollama"
        }
    }

    var help: String {
        switch self {
        case .builtin: return "追加インストール不要。モデルはアプリ内から直接ダウンロードします(推奨)"
        case .ollama: return "すでに Ollama をお使いの方向け。Ollama のモデルをそのまま使えます"
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
        case .raw: return "そのまま"
        case .clean: return "整文"
        case .command: return "AI命令化"
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
        case .raw: return "音声認識の結果をそのまま使います(LLM不使用)"
        case .clean: return "フィラーを除去し、読みやすい文章に整えます"
        case .command: return "AIアシスタントへの明確な指示文に再構成します"
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
    var onboarded = false
    var hotkey = KeyCombo.default

    // 音声認識
    var localeID = "ja-JP"
    var preferOnDevice = true
    var punctuation = true
    var vocabulary = ""          // カンマ区切りの専門用語
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

    var vocabularyList: [String] {
        vocabulary
            .components(separatedBy: CharacterSet(charactersIn: ",、\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var activePremise: PremisePreset? {
        premises.first { $0.id == activePremiseID }
    }

    // UI 表示用のモデル名(HUD のチップ等)
    var activeModelLabel: String {
        switch engine {
        case .builtin:
            guard let file = builtinModelFile else { return "モデル未選択" }
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
        onboarded = (try? c.decodeIfPresent(Bool.self, forKey: .onboarded)) ?? d.onboarded
        hotkey = (try? c.decodeIfPresent(KeyCombo.self, forKey: .hotkey)) ?? d.hotkey
        localeID = (try? c.decodeIfPresent(String.self, forKey: .localeID)) ?? d.localeID
        preferOnDevice = (try? c.decodeIfPresent(Bool.self, forKey: .preferOnDevice)) ?? d.preferOnDevice
        punctuation = (try? c.decodeIfPresent(Bool.self, forKey: .punctuation)) ?? d.punctuation
        vocabulary = (try? c.decodeIfPresent(String.self, forKey: .vocabulary)) ?? d.vocabulary
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
    }
}

// MARK: - ストア

@MainActor
final class SettingsStore: ObservableObject {
    @Published var value: AppSettings {
        didSet { scheduleSave() }
    }

    private var saveWork: DispatchWorkItem?

    nonisolated static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Koe", isDirectory: true)
    }

    private static var fileURL: URL { directory.appendingPathComponent("settings.json") }

    init() {
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: Self.fileURL),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            value = decoded
        } else {
            value = AppSettings()
        }
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
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }
}
