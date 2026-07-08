import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        NavigationStack {
            Form {
                refineSection
                premiseSection
                speechSection
                vocabularySection
                generalSection
                aboutSection
            }
            .navigationTitle(tr("設定", "Settings"))
        }
    }

    private var refineSection: some View {
        Section {
            Picker(tr("既定のモード", "Default mode"), selection: $app.config.refineMode) {
                ForEach(RefineMode.allCases) { Text($0.label).tag($0) }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(tr("創造性", "Creativity"))
                    Spacer()
                    Text(String(format: "%.2f", app.settings.value.temperature))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $app.config.temperature, in: 0...1, step: 0.05)
            }
        } header: {
            Text(tr("整形", "Refinement"))
        } footer: {
            Text(app.settings.value.refineMode.help)
        }
    }

    private var premiseSection: some View {
        Section(tr("前提プリセット", "Context presets")) {
            Picker(tr("使用中", "Active"), selection: $app.config.activePremiseID) {
                Text(tr("なし", "None")).tag(UUID?.none)
                ForEach(app.settings.value.premises) { Text($0.name).tag(UUID?.some($0.id)) }
            }
            ForEach(Array(app.settings.value.premises.enumerated()), id: \.element.id) { index, _ in
                NavigationLink {
                    PremiseEditor(index: index)
                } label: {
                    Text(app.settings.value.premises[index].name.isEmpty
                         ? tr("名称未設定", "Untitled")
                         : app.settings.value.premises[index].name)
                }
            }
            .onDelete { indexSet in
                var premises = app.settings.value.premises
                premises.remove(atOffsets: indexSet)
                if premises.isEmpty { premises = [.initial] }
                app.config.premises = premises
                if !premises.contains(where: { $0.id == app.settings.value.activePremiseID }) {
                    app.config.activePremiseID = premises.first?.id
                }
            }
            Button {
                var p = PremisePreset(name: tr("新しいプリセット", "New preset"), text: "")
                p.id = UUID()
                app.config.premises.append(p)
            } label: {
                Label(tr("プリセットを追加", "Add preset"), systemImage: "plus")
            }
        }
    }

    private var speechSection: some View {
        Section(tr("音声認識", "Speech recognition")) {
            Picker(tr("言語", "Language"), selection: $app.config.localeID) {
                ForEach(AppSettings.speechLocales) { Text($0.label).tag($0.id) }
            }
            // iOS は常時オンデバイス認識のため「優先」トグルは置かない
            Toggle(tr("句読点を自動挿入", "Auto punctuation"), isOn: $app.config.punctuation)
            Toggle(tr("無音で自動停止", "Auto-stop on silence"), isOn: $app.config.autoStop)
            if app.settings.value.autoStop {
                Picker(tr("停止までの無音", "Silence before stop"), selection: $app.config.autoStopSeconds) {
                    Text(tr("1.5 秒", "1.5s")).tag(1.5)
                    Text(tr("2 秒", "2s")).tag(2.0)
                    Text(tr("3 秒", "3s")).tag(3.0)
                }
            }
        }
    }

    private var vocabularySection: some View {
        Section {
            NavigationLink {
                VocabularyEditor()
            } label: {
                HStack {
                    Text(tr("認識辞書", "Vocabulary"))
                    Spacer()
                    Text(tr("\(app.settings.value.vocabularyList.count) 語", "\(app.settings.value.vocabularyList.count) terms"))
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text(tr("固有名詞・専門用語を登録すると認識精度が上がります。", "Registered proper nouns and terms improve recognition accuracy."))
        }
    }

    private var generalSection: some View {
        Section(tr("一般", "General")) {
            Picker(tr("表示言語", "App language"), selection: $app.config.uiLanguage) {
                ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
            }
        }
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Youyaku")
                Spacer()
                Text(tr("AIのための音声入力", "Voice input for AI"))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Label(tr("音声認識・整形はすべて端末内で処理されます。外部への通信は、モデルのダウンロード時(Hugging Face)のみです。",
                     "Speech recognition and refinement happen entirely on-device. The only network access is for model downloads (Hugging Face)."),
                  systemImage: "lock.shield")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Link(destination: URL(string: "https://youyaku.hinoshiba.com/privacy.html")!) {
                Text(tr("プライバシーポリシー", "Privacy Policy"))
            }
            Link(destination: URL(string: "https://youyaku.hinoshiba.com/terms.html")!) {
                Text(tr("利用規約", "Terms of Use"))
            }
            NavigationLink {
                LicenseView()
            } label: {
                Text(tr("オープンソースライセンス", "Open-Source Licenses"))
            }
        }
    }
}

// MARK: - ライセンス表示

struct LicenseView: View {
    var body: some View {
        ScrollView {
            Text(Licenses.thirdPartyText)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .navigationTitle(tr("ライセンス", "Licenses"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 前提エディタ

struct PremiseEditor: View {
    @EnvironmentObject var app: AppModel
    let index: Int

    var body: some View {
        Form {
            Section(tr("名前", "Name")) {
                TextField(tr("プリセット名", "Preset name"), text: Binding(
                    get: { app.settings.value.premises[safe: index]?.name ?? "" },
                    set: { if app.settings.value.premises.indices.contains(index) { app.config.premises[index].name = $0 } }
                ))
            }
            Section {
                TextEditor(text: Binding(
                    get: { app.settings.value.premises[safe: index]?.text ?? "" },
                    set: { if app.settings.value.premises.indices.contains(index) { app.config.premises[index].text = $0 } }
                ))
                .frame(minHeight: 180)
                .font(.system(size: 14))
            } header: {
                Text(tr("前提情報", "Background information"))
            } footer: {
                Text(tr("例: 使用技術、対象読者、出力形式の指定など", "e.g. tech stack, audience, output format"))
            }
        }
        .navigationTitle(tr("前提プリセット", "Context preset"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 認識辞書エディタ

struct VocabularyEditor: View {
    @EnvironmentObject var app: AppModel
    @State private var newTerm = ""

    var body: some View {
        List {
            Section {
                HStack {
                    TextField(tr("用語を追加(カンマ・改行で一括可)", "Add a term (comma/newline for bulk)"), text: $newTerm)
                        .onSubmit(add)
                    Button(action: add) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(newTerm.trimmingCharacters(in: .whitespaces).isEmpty ? .secondary : Brand.primary)
                    }
                    .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            Section {
                ForEach(app.settings.value.vocabularyTerms, id: \.self) { term in
                    Text(term)
                }
                .onDelete { indexSet in
                    var terms = app.settings.value.vocabularyTerms
                    terms.remove(atOffsets: indexSet)
                    app.config.vocabularyTerms = terms
                }
            }
        }
        .navigationTitle(tr("認識辞書", "Vocabulary"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func add() {
        let terms = AppSettings.splitTerms(newTerm)
        guard !terms.isEmpty else { return }
        var existing = Set(app.settings.value.vocabularyTerms)
        for t in terms where !existing.contains(t) {
            app.config.vocabularyTerms.append(t)
            existing.insert(t)
        }
        newTerm = ""
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
