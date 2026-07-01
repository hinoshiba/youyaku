import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 12) {
            header
            recordButton
            modePicker
            selectors
            lastResult
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 340)
    }

    private var header: some View {
        HStack {
            Text("Koe")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Brand.gradient)
            Text(tr("AIのための音声入力", "Voice input for AI"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            ollamaDot
        }
    }

    private var ollamaDot: some View {
        let ready: Bool
        let label: String
        if app.settings.value.engine == .builtin {
            ready = app.settings.value.builtinModelFile.map { file in
                app.modelStore.installed.contains { $0.fileName == file }
            } ?? false
            label = ready ? tr("ローカルLLM 準備完了", "Local LLM Ready") : tr("モデル未設定", "No Model Selected")
        } else {
            ready = app.ollama.status.isRunning
            label = ready ? tr("Ollama 稼働中", "Ollama Running") : tr("Ollama 停止中", "Ollama Stopped")
        }
        return HStack(spacing: 5) {
            Circle()
                .fill(ready ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private var recordButton: some View {
        Button {
            app.toggle()
        } label: {
            HStack {
                Image(systemName: app.phase == .recording ? "stop.fill" : "mic.fill")
                Text(app.phase == .recording ? tr("停止して整形", "Stop & Refine") : tr("音声入力を開始", "Start Dictation"))
                    .fontWeight(.semibold)
                Spacer()
                Text(app.settings.value.hotkey.display)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .opacity(0.75)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(app.phase == .recording ? Brand.recordingGradient : Brand.gradient)
            )
        }
        .buttonStyle(.plain)
    }

    private var modePicker: some View {
        Picker(tr("モード", "Mode"), selection: $app.config.refineMode) {
            ForEach(RefineMode.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var selectors: some View {
        VStack(spacing: 6) {
            HStack {
                Label(tr("モデル", "Model"), systemImage: "cpu")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                if app.settings.value.engine == .builtin {
                    if app.modelStore.installed.isEmpty {
                        Button(tr("ダウンロードする", "Download")) {
                            WindowManager.shared.show(tab: .models)
                        }
                        .controlSize(.small)
                    } else {
                        Picker("", selection: $app.config.builtinModelFile) {
                            Text(tr("未選択", "None")).tag(String?.none)
                            ForEach(app.modelStore.installed) { model in
                                Text(model.displayName).tag(String?.some(model.fileName))
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 190)
                    }
                } else {
                    Picker("", selection: $app.config.model) {
                        if !app.ollama.installed.contains(where: { $0.name == app.settings.value.model }) {
                            Text(app.settings.value.model).tag(app.settings.value.model)
                        }
                        ForEach(app.ollama.installed) { model in
                            Text(model.name).tag(model.name)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 190)
                }
            }
            HStack {
                Label(tr("前提", "Context"), systemImage: "doc.text")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $app.config.activePremiseID) {
                    Text(tr("なし", "None")).tag(UUID?.none)
                    ForEach(app.settings.value.premises) { preset in
                        Text(preset.name).tag(UUID?.some(preset.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 180)
            }
        }
    }

    @ViewBuilder
    private var lastResult: some View {
        if let last = app.history.entries.first {
            let text = last.refined.isEmpty ? last.raw : last.refined
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(last.refined.isEmpty ? tr("最近の入力(音声のみ)", "Recent Input (Voice Only)") : tr("最近の入力", "Recent Input"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        _ = Paster.deliver(text, paste: false, keepInClipboard: true)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .help(tr("コピー", "Copy"))
                }
                Text(text)
                    .font(.system(size: 11))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .card(cornerRadius: 10)
        }
    }

    private var footer: some View {
        HStack {
            Button {
                WindowManager.shared.show(tab: .home)
            } label: {
                Label(tr("ダッシュボード", "Dashboard"), systemImage: "rectangle.grid.2x2")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                WindowManager.shared.show(tab: .settings)
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help(tr("設定", "Settings"))

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .help(tr("Koe を終了", "Quit Koe"))
        }
        .foregroundStyle(.secondary)
    }
}
