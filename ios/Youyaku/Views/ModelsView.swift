import SwiftUI

struct ModelsView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.openURL) private var openURL
    @State private var deviceRAM = ProcessInfo.processInfo.physicalMemory
    @State private var consentModel: BuiltinModel?   // DL 前のライセンス同意待ちモデル

    // 端末 RAM に対するモデルサイズの適合度
    private enum MemoryFit {
        case fits       // 問題なくロードできる見込み
        case risky      // RAM の 30〜45%: 動くが不安定になる可能性
        case unusable   // RAM の 45% 超: ロード不可とみなし DL させない
    }

    private func memoryFit(_ model: BuiltinModel) -> MemoryFit {
        let ram = Double(deviceRAM)
        let size = Double(model.sizeBytes)
        if size > ram * 0.45 { return .unusable }
        if size > ram * 0.30 { return .risky }
        return .fits
    }

    // ライセンス上必須の帰属表示(カタログ下部のフッタ用。重複は除く)
    private var attributions: [String] {
        var seen = Set<String>()
        return BuiltinCatalog.all.compactMap { model in
            guard let a = model.attribution, !seen.contains(a) else { return nil }
            seen.insert(a)
            return a
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if app.modelStore.installed.isEmpty {
                        Text(tr("まだモデルがありません。下から選んでダウンロードしてください。",
                                "No models yet. Download one below."))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(app.modelStore.installed) { model in
                            installedRow(model)
                        }
                    }
                } header: {
                    Text(tr("ダウンロード済み", "Downloaded"))
                } footer: {
                    Text(tr("空き容量: \(Format.bytes(app.modelStore.freeDiskSpace))",
                            "Free space: \(Format.bytes(app.modelStore.freeDiskSpace))"))
                }

                Section {
                    ForEach(BuiltinCatalog.all) { model in
                        catalogRow(model)
                    }
                } header: {
                    Text(tr("モデルカタログ", "Model Catalog"))
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tr("モデルは Hugging Face からダウンロードします(このアプリが外部と通信するのはモデルのダウンロード時のみです)。認識・整形はすべて端末内で動作し、音声も文章も外部に送信されません。端末のメモリに合ったサイズをお選びください。",
                                "Models are downloaded from Hugging Face — the only time this app connects to the network. Recognition and refinement run entirely on-device; your audio and text never leave the phone. Pick a size that fits your device memory."))
                        if !attributions.isEmpty {
                            Text(attributions.joined(separator: " / "))
                        }
                    }
                }

                if let error = app.modelStore.lastError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle(tr("モデル", "Models"))
            .confirmationDialog(
                tr("ダウンロードの確認", "Confirm Download"),
                isPresented: Binding(
                    get: { consentModel != nil },
                    set: { if !$0 { consentModel = nil } }
                ),
                titleVisibility: .visible,
                presenting: consentModel
            ) { model in
                Button(tr("同意してダウンロード", "Agree & Download")) {
                    app.modelStore.download(from: model.url, fileName: model.fileName, expectedBytes: model.sizeBytes)
                }
                if let license = model.licenseURL {
                    Button(tr("ライセンスを表示", "View License")) { openURL(license) }
                }
                Button(tr("キャンセル", "Cancel"), role: .cancel) {}
            } message: { model in
                Text(consentMessage(model))
            }
        }
    }

    // DL 前に提示するライセンス同意文
    private func consentMessage(_ model: BuiltinModel) -> String {
        let license = model.licenseName ?? tr("配布元のライセンス", "the distributor's license terms")
        return tr("「\(model.displayName)」をダウンロードします。このモデルは \(license) に基づいて提供されます。内容に同意のうえダウンロードしてください。",
                  "You're about to download \(model.displayName). This model is provided under \(license). Please review and agree to the license before downloading.")
    }

    private func installedRow(_ model: LocalModel) -> some View {
        let isActive = app.settings.value.builtinModelFile == model.fileName
        return Button {
            app.settings.value.builtinModelFile = model.fileName
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isActive ? Brand.primary : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(.primary)
                    Text(Format.bytes(model.size))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isActive {
                    Text(tr("使用中", "In use"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Brand.primary)
                }
            }
        }
        .swipeActions {
            Button(role: .destructive) {
                if isActive {
                    app.settings.value.builtinModelFile = nil
                    app.llamaEngine.unload()
                }
                app.modelStore.delete(model)
            } label: {
                Label(tr("削除", "Delete"), systemImage: "trash")
            }
        }
    }

    private func catalogRow(_ model: BuiltinModel) -> some View {
        let installed = app.modelStore.installed.contains { $0.fileName == model.fileName }
        let progress = app.modelStore.downloads[model.fileName]
        let fit = memoryFit(model)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(model.displayName).font(.system(size: 14, weight: .semibold))
                // この端末で使えないモデルに「おすすめ」バッジが付くと誤誘導になるため隠す
                if let tag = model.tag, !(model.isRecommended && fit == .unusable) {
                    Chip(text: tag, icon: model.isRecommended ? "star.fill" : nil,
                         tint: model.isRecommended ? .orange : Brand.primary)
                }
                Spacer()
            }
            Text(model.description)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let attribution = model.attribution {
                // ライセンス上必須の帰属表示
                Text(attribution)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            if fit == .unusable {
                Label(tr("この端末ではメモリ不足のため利用できません", "Not available on this device — not enough memory"),
                      systemImage: "xmark.octagon.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            } else if fit == .risky {
                Label(tr("この端末では動作が不安定になる可能性があります", "May be unstable on this device"),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
            HStack(spacing: 8) {
                stars(model.japaneseStars)
                Text(model.sizeLabel).font(.system(size: 11)).foregroundStyle(.tertiary)
                if let license = model.licenseURL {
                    Link(tr("ライセンス", "License"), destination: license)
                        .font(.system(size: 10))
                }
                Spacer()
                controls(model, installed: installed, progress: progress, fit: fit)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func controls(_ model: BuiltinModel, installed: Bool, progress: ModelDownload?, fit: MemoryFit) -> some View {
        if installed {
            Label(tr("導入済み", "Installed"), systemImage: "checkmark.circle.fill")
                .font(.system(size: 11)).foregroundStyle(.green)
        } else if let progress {
            HStack(spacing: 6) {
                if let f = progress.fraction {
                    Text("\(Int(f * 100))%").font(.system(size: 11)).monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: progress.fraction ?? 0).frame(width: 70)
                Button {
                    app.modelStore.cancel(model.fileName)
                } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
            }
        } else {
            Button {
                // 直接 DL せず、まずライセンス同意を求める
                consentModel = model
            } label: {
                Label(tr("入手", "Get"), systemImage: "arrow.down.circle").font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(fit == .unusable)
        }
    }

    private func stars(_ n: Int) -> some View {
        HStack(spacing: 1) {
            ForEach(0..<5, id: \.self) { i in
                Image(systemName: i < n ? "star.fill" : "star")
                    .font(.system(size: 8))
                    .foregroundStyle(i < n ? Color.orange : Color.secondary.opacity(0.4))
            }
        }
    }
}
