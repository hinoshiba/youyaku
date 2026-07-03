import SwiftUI
import UIKit

struct DictateView: View {
    @EnvironmentObject var app: AppModel
    @Binding var tab: Int
    @State private var shareText: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    modePicker
                    stage
                    if !app.hasModel {
                        modelPrompt
                    }
                }
                .padding(20)
            }
            .navigationTitle("Youyaku")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .sheet(item: Binding(
                get: { shareText.map { SharePayload(text: $0) } },
                set: { shareText = $0?.text }
            )) { payload in
                ShareSheet(items: [payload.text])
            }
        }
    }

    // MARK: - ヘッダー(モデル・前提)

    private var header: some View {
        HStack(spacing: 8) {
            chip(app.settings.value.activeModelLabel, "cpu")
            if let premise = app.settings.value.activePremise, !premise.text.isEmpty {
                chip(premise.name, "doc.text")
            }
            Spacer()
            languageMenu
        }
    }

    // 認識言語をこの画面から直接切り替えられるメニュー
    private var languageMenu: some View {
        Menu {
            Picker(tr("認識言語", "Recognition language"), selection: $app.config.localeID) {
                ForEach(AppSettings.speechLocales) { Text($0.label).tag($0.id) }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "globe").font(.system(size: 10, weight: .semibold))
                Text(app.settings.value.speechLocaleLabel)
                    .font(.system(size: 11, weight: .medium))
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(Brand.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Brand.primary.opacity(0.12)))
        }
        .disabled(app.phase == .recording || app.phase == .refining)
    }

    private func chip(_ text: String, _ icon: String) -> some View {
        Chip(text: text, icon: icon, tint: .secondary)
    }

    private var modePicker: some View {
        Picker(tr("モード", "Mode"), selection: $app.config.refineMode) {
            ForEach(RefineMode.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .disabled(app.phase == .recording || app.phase == .refining)
    }

    // MARK: - 中央(状態ごと)

    @ViewBuilder
    private var stage: some View {
        switch app.phase {
        case .idle:
            idleStage
        case .recording:
            recordingStage
        case .refining:
            refiningStage
        case .result:
            resultStage
        case .error(let message):
            errorStage(message)
        }
    }

    private var micButton: some View {
        Button {
            app.toggle()
        } label: {
            ZStack {
                Circle()
                    .fill(app.phase == .recording ? Brand.recordingGradient : Brand.gradient)
                    .frame(width: 116, height: 116)
                    .shadow(color: Brand.primary.opacity(0.4), radius: 16, y: 6)
                Image(systemName: app.phase == .recording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
    }

    private var idleStage: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 30)
            micButton
            Text(tr("タップして話す", "Tap to speak"))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            Text(tr("話した内容をローカルAIが整った指示文にします", "A local AI turns your speech into a polished prompt"))
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer(minLength: 30)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .card()
    }

    private var recordingStage: some View {
        VStack(spacing: 16) {
            transcriptText(app.speech.partial.isEmpty ? tr("どうぞ、お話しください…", "Go ahead, start speaking…") : app.speech.partial,
                           placeholder: app.speech.partial.isEmpty)
            WaveformView(level: app.speech.level)
                .frame(height: 44)
            micButton
            Text(tr("もう一度タップで停止して整形", "Tap again to stop and refine"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .card()
    }

    private var refiningStage: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(tr("整理しています…", "Refining…"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            if !app.refined.isEmpty {
                transcriptText(app.refined, placeholder: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .card()
    }

    private var resultStage: some View {
        VStack(alignment: .leading, spacing: 14) {
            transcriptText(app.refined, placeholder: false)

            if let message = app.statusMessage {
                Label(message, systemImage: "info.circle")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 10) {
                Button {
                    app.copyResult()
                } label: {
                    Label(tr("コピー", "Copy"), systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    shareText = app.refined
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 10) {
                Button {
                    app.resumeRecording()
                } label: {
                    Label(tr("続きから再開", "Resume"), systemImage: "mic.badge.plus")
                        .font(.system(size: 13))
                }
                if app.settings.value.refineMode != .raw {
                    Button {
                        app.retryRefine()
                    } label: {
                        Label(tr("やり直す", "Retry"), systemImage: "arrow.clockwise")
                            .font(.system(size: 13))
                    }
                }
                Spacer()
                Button(role: .cancel) {
                    app.cancelSession()
                } label: {
                    Text(tr("閉じる", "Close")).font(.system(size: 13))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                app.startRecording()
            } label: {
                Label(tr("新しく話す", "New dictation"), systemImage: "mic.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .card()
    }

    private func errorStage(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack {
                Button(tr("設定を開く", "Open Settings")) { Permissions.openSettings() }
                    .buttonStyle(.bordered)
                Button(tr("もう一度", "Try again")) { app.startRecording() }
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .card()
    }

    private func transcriptText(_ text: String, placeholder: Bool) -> some View {
        Text(text)
            .font(.system(size: 17))
            .foregroundStyle(placeholder ? .tertiary : .primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }

    private var modelPrompt: some View {
        Button {
            tab = 1
        } label: {
            HStack {
                Image(systemName: "arrow.down.circle.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("整形用モデルをダウンロード", "Download a refinement model"))
                        .font(.system(size: 13, weight: .medium))
                    Text(tr("「モデル」タブから。未設定でも音声認識は使えます", "From the Models tab. Speech works even without one."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(14)
            .card()
        }
        .buttonStyle(.plain)
    }
}

