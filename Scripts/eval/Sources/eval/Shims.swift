import Foundation

// 出荷ツリーの Refiner.swift / LlamaEngine.swift をそのままリンクするために、
// それらが依存する最小限のシンボルだけを再現する。
// (本体は SwiftUI/Speech に依存していて CLI から丸ごとは引けないため)

func tr(_ ja: String, _ en: String) -> String { ja }

struct YouyakuError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum RefineMode: String, Codable, CaseIterable, Identifiable {
    case raw
    case clean
    case command
    case template
    var id: String { rawValue }
}

struct PremisePreset: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var text: String
}

struct TemplatePreset: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var body: String
}
