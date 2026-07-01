import SwiftUI

struct HUDView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 10)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 20)

            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .frame(width: 660, height: 320)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(borderGradient, lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
        )
        .animation(.easeInOut(duration: 0.2), value: app.phase)
    }

    private var borderGradient: LinearGradient {
        switch app.phase {
        case .recording:
            return Brand.recordingGradient
        default:
            return LinearGradient(
                colors: [Brand.primary.opacity(0.55), Brand.secondary.opacity(0.35)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            phaseIndicator
            Text(phaseTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            if app.settings.value.refineMode != .raw {
                if let premise = app.settings.value.activePremise, !premise.text.isEmpty {
                    Chip(text: premise.name, icon: "doc.text", tint: Brand.primary)
                }
                Chip(text: app.settings.value.activeModelLabel, icon: "cpu", tint: .secondary)
            }
            Chip(
                text: app.settings.value.refineMode.label,
                icon: app.settings.value.refineMode.icon,
                tint: Brand.secondary
            )
        }
    }

    @ViewBuilder
    private var phaseIndicator: some View {
        switch app.phase {
        case .recording:
            Circle()
                .fill(Brand.recording)
                .frame(width: 9, height: 9)
                .modifier(Pulse())
        case .refining:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
        case .result:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.green)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.orange)
        case .idle:
            EmptyView()
        }
    }

    private var phaseTitle: String {
        switch app.phase {
        case .recording: return "聞き取り中"
        case .refining: return "整理しています…"
        case .result: return "できました"
        case .error: return "エラー"
        case .idle: return ""
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch app.phase {
        case .recording:
            VStack(spacing: 14) {
                transcriptScroll(
                    text: app.speech.partial,
                    placeholder: "どうぞ、お話しください…",
                    font: .system(size: 17, weight: .regular),
                    color: .primary
                )
                WaveformView(level: app.speech.level)
                    .frame(height: 40)
            }
        case .refining:
            VStack(alignment: .leading, spacing: 10) {
                Text(app.transcript)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Divider()
                transcriptScroll(
                    text: app.refined,
                    placeholder: "ローカルLLMが指示文を整理しています…",
                    font: .system(size: 16),
                    color: .primary
                )
            }
        case .result:
            VStack(alignment: .leading, spacing: 8) {
                transcriptScroll(
                    text: app.refined,
                    placeholder: "",
                    font: .system(size: 16),
                    color: .primary
                )
                if let message = app.statusMessage {
                    Label(message, systemImage: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }
        case .error(let message):
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "mic.slash")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button("マイク設定を開く") { Permissions.openMicrophoneSettings() }
                    Button("音声認識設定を開く") { Permissions.openSpeechSettings() }
                }
                .controlSize(.small)
                Spacer()
            }
        case .idle:
            EmptyView()
        }
    }

    private func transcriptScroll(text: String, placeholder: String, font: Font, color: Color) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if text.isEmpty {
                        Text(placeholder)
                            .font(font)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(text)
                            .font(font)
                            .foregroundStyle(color)
                            .textSelection(.enabled)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: text) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 14) {
            switch app.phase {
            case .recording:
                keyHint("↩", "整形して確定")
                keyHint(app.settings.value.hotkey.display, "停止")
                keyHint("esc", "キャンセル")
            case .refining:
                keyHint("esc", "中断")
            case .result:
                keyHint("↩", app.settings.value.autoPaste ? "貼り付け" : "コピー")
                keyHint("⌘C", "コピーのみ")
                if app.settings.value.refineMode != .raw {
                    keyHint("⌘R", "整形をやり直す")
                }
                keyHint("esc", "閉じる")
            case .error:
                keyHint("esc", "閉じる")
            case .idle:
                EmptyView()
            }
            Spacer()
            Text("Koe")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Brand.gradient)
        }
    }

    private func keyHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.08))
                )
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

private struct Pulse: ViewModifier {
    @State private var animating = false

    func body(content: Content) -> some View {
        content
            .opacity(animating ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: animating)
            .onAppear { animating = true }
    }
}
