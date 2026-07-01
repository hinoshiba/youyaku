import SwiftUI

struct ModelsView: View {
    @EnvironmentObject var app: AppModel
    @State private var deviceRAM = ProcessInfo.processInfo.physicalMemory

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
                    Text(tr("すべて Mac/iPhone 内で動作し、音声も文章も外部に送信されません。端末のメモリに合ったサイズをお選びください。",
                            "Everything runs on-device; your audio and text never leave the phone. Pick a size that fits your device memory."))
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
        }
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
        let heavy = model.sizeBytes > Int64(Double(deviceRAM) * 0.55)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(model.displayName).font(.system(size: 14, weight: .semibold))
                if let tag = model.tag {
                    Chip(text: tag, icon: model.isRecommended ? "star.fill" : nil,
                         tint: model.isRecommended ? .orange : Brand.primary)
                }
                Spacer()
            }
            Text(model.description)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                stars(model.japaneseStars)
                Text(model.sizeLabel).font(.system(size: 11)).foregroundStyle(.tertiary)
                if heavy {
                    Label(tr("大きめ", "Large"), systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
                Spacer()
                controls(model, installed: installed, progress: progress)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func controls(_ model: BuiltinModel, installed: Bool, progress: ModelDownload?) -> some View {
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
                app.modelStore.download(from: model.url, fileName: model.fileName, expectedBytes: model.sizeBytes)
            } label: {
                Label(tr("入手", "Get"), systemImage: "arrow.down.circle").font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
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
