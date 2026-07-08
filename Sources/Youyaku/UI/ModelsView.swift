import SwiftUI

struct ModelsView: View {
    @EnvironmentObject var app: AppState
    @State private var customModel = ""
    @State private var customURL = ""
    @State private var startingServer = false
    @State private var copiedBrew = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                engineCard

                if app.settings.value.engine == .builtin {
                    builtinInstalledCard
                    builtinCatalogCard
                    builtinCustomCard
                    if let error = app.modelStore.lastError {
                        errorCard(error)
                    }
                } else {
                    serverCard
                    if app.ollama.status.isRunning {
                        installedCard
                        catalogCard
                        customPullCard
                    } else if case .notInstalled = app.ollama.status {
                        installGuideCard
                    }
                    if let error = app.ollama.lastError {
                        errorCard(error)
                    }
                }
            }
            .padding(24)
        }
        .task {
            app.modelStore.refresh()
            if app.settings.value.engine == .ollama {
                await app.ollama.refresh()
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.system(size: 12))
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .card()
    }

    // MARK: - エンジン選択

    private var engineCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("LLM エンジン", "LLM Engine"))
                        .font(.system(size: 14, weight: .semibold))
                    Text(app.settings.value.engine.help)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $app.config.engine) {
                    ForEach(EngineKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240)
                .onChange(of: app.settings.value.engine) { _, newValue in
                    if newValue == .ollama {
                        Task { await app.ollama.refresh() }
                    }
                }
            }

            if app.settings.value.engine == .ollama {
                Label(tr("Ollama 利用中は「すべて Mac 内で完結」の対象外です。整形するテキストは Ollama サーバー(既定はこの Mac、設定で外部ホストも指定可)へ送信されます。", "With Ollama, the \"everything stays on your Mac\" guarantee does not apply. The text being refined is sent to your Ollama server (this Mac by default; you can point it to an external host in Settings)."),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label(tr("音声も文章もモデルも、すべて Mac の中だけで完結します。外部にデータは送信されません。", "Your voice, text, and models all stay on your Mac. No data is ever sent externally."),
                      systemImage: "lock.shield")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .card()
    }

    // MARK: - 内蔵エンジン: ダウンロード済み

    private var builtinInstalledCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(tr("ダウンロード済みモデル", "Downloaded Models"))
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button {
                    app.modelStore.revealInFinder()
                } label: {
                    Label(tr("保存先を開く", "Show in Finder"), systemImage: "folder")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
            }
            .padding(.bottom, 6)

            if app.modelStore.installed.isEmpty {
                Text(tr("まだモデルがありません。下のカタログからワンクリックでダウンロードできます。", "No models yet. Download one from the catalog below with a single click."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)
            } else {
                ForEach(app.modelStore.installed) { model in
                    builtinInstalledRow(model)
                    if model.id != app.modelStore.installed.last?.id {
                        Divider()
                    }
                }
            }

            Divider().padding(.vertical, 4)
            HStack {
                Image(systemName: "internaldrive")
                    .foregroundStyle(.tertiary)
                Text(tr("空き容量: \(Format.bytes(app.modelStore.freeDiskSpace))", "Free space: \(Format.bytes(app.modelStore.freeDiskSpace))"))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        }
        .padding(18)
        .card()
    }

    private func builtinInstalledRow(_ model: LocalModel) -> some View {
        let isActive = app.settings.value.builtinModelFile == model.fileName
        return HStack(spacing: 12) {
            Button {
                app.settings.value.builtinModelFile = model.fileName
            } label: {
                Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isActive ? Brand.primary : .secondary)
            }
            .buttonStyle(.plain)
            .help(tr("このモデルを使用", "Use This Model"))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(model.displayName)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                    if isActive {
                        Chip(text: tr("使用中", "In Use"), tint: Brand.primary)
                    }
                }
                Text(Format.bytes(model.size))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                if isActive {
                    app.settings.value.builtinModelFile = nil
                    app.llamaEngine.unload()
                }
                app.modelStore.delete(model)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(tr("削除", "Delete"))
        }
        .padding(.vertical, 6)
    }

    // MARK: - 内蔵エンジン: カタログ

    private var builtinCatalogCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tr("モデルカタログ", "Model Catalog"))
                .font(.system(size: 14, weight: .semibold))
            Text(tr("日本語の指示整形に向いたモデルを厳選。ワンクリックで Hugging Face から直接ダウンロードします。", "A curated selection of models well suited to prompt refinement. Download directly from Hugging Face with one click."))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)

            ForEach(BuiltinCatalog.all) { model in
                builtinCatalogRow(model)
                if model.id != BuiltinCatalog.all.last?.id {
                    Divider()
                }
            }
        }
        .padding(18)
        .card()
    }

    private func builtinCatalogRow(_ model: BuiltinModel) -> some View {
        let installed = app.modelStore.installed.contains { $0.fileName == model.fileName }
        let progress = app.modelStore.downloads[model.fileName]

        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(model.displayName)
                        .font(.system(size: 13, weight: .semibold))
                    Chip(text: model.vendor, tint: .secondary)
                    if let tag = model.tag {
                        Chip(text: tag, icon: model.isRecommended ? "star.fill" : nil,
                             tint: model.isRecommended ? .orange : Brand.primary)
                    }
                }
                Text(model.description)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    stars(model.japaneseStars)
                    Text(model.sizeLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Text(model.quant)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    if let license = model.licenseURL {
                        Link(tr("ライセンス", "License"), destination: license)
                            .font(.system(size: 10))
                    }
                }
            }

            Spacer()

            if installed {
                Label(tr("導入済み", "Installed"), systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
            } else if let progress {
                builtinProgressView(fileName: model.fileName, progress: progress)
            } else {
                Button {
                    app.modelStore.download(from: model.url, fileName: model.fileName, expectedBytes: model.sizeBytes)
                } label: {
                    Label(tr("ダウンロード", "Download"), systemImage: "arrow.down.circle")
                        .font(.system(size: 12))
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func builtinProgressView(fileName: String, progress: ModelDownload) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 8) {
                Text(builtinProgressLabel(progress))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button {
                    app.modelStore.cancel(fileName)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(tr("キャンセル", "Cancel"))
            }
            ProgressView(value: progress.fraction)
                .progressViewStyle(.linear)
                .frame(width: 160)
        }
    }

    private func builtinProgressLabel(_ p: ModelDownload) -> String {
        if let fraction = p.fraction, p.totalBytes > 0 {
            return "\(Int(fraction * 100))%(\(Format.bytes(p.receivedBytes)) / \(Format.bytes(p.totalBytes)))"
        }
        if p.receivedBytes > 0 {
            return tr("\(Format.bytes(p.receivedBytes)) 受信…", "\(Format.bytes(p.receivedBytes)) received…")
        }
        return tr("接続中…", "Connecting…")
    }

    // MARK: - 内蔵エンジン: 任意の GGUF

    private var builtinCustomCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("その他のモデル", "Other Models"))
                .font(.system(size: 14, weight: .semibold))
            Text(tr("Hugging Face 上の任意の GGUF ファイルの直リンク(…/resolve/main/xxx.gguf)を指定してダウンロードできます。", "Enter a direct link to any GGUF file on Hugging Face (…/resolve/main/xxx.gguf) to download it."))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                TextField("https://huggingface.co/…/resolve/main/model-Q4_K_M.gguf", text: $customURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .onSubmit { downloadCustom() }

                if let name = customFileName, let progress = app.modelStore.downloads[name] {
                    builtinProgressView(fileName: name, progress: progress)
                } else {
                    Button(tr("ダウンロード", "Download")) { downloadCustom() }
                        .disabled(customFileName == nil)
                }
            }

            Link(tr("GGUF モデルを探す(huggingface.co)", "Find GGUF Models (huggingface.co)"),
                 destination: URL(string: "https://huggingface.co/models?library=gguf&language=ja&sort=downloads")!)
                .font(.system(size: 11))
        }
        .padding(18)
        .card()
    }

    private var customFileName: String? {
        guard let url = URL(string: customURL.trimmingCharacters(in: .whitespaces)),
              url.scheme == "https",
              url.lastPathComponent.lowercased().hasSuffix(".gguf") else { return nil }
        return url.lastPathComponent
    }

    private func downloadCustom() {
        guard let url = URL(string: customURL.trimmingCharacters(in: .whitespaces)),
              let name = customFileName else { return }
        app.modelStore.download(from: url, fileName: name)
    }

    // MARK: - Ollama: サーバー状態

    private var serverCard: some View {
        HStack(spacing: 14) {
            Image(systemName: app.ollama.status.isRunning ? "bolt.fill" : "bolt.slash")
                .font(.system(size: 22))
                .foregroundStyle(app.ollama.status.isRunning ? Color.green : Color.orange)
                .frame(width: 44, height: 44)
                .background(
                    Circle().fill((app.ollama.status.isRunning ? Color.green : Color.orange).opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(serverTitle)
                    .font(.system(size: 14, weight: .semibold))
                Text(serverDetail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            switch app.ollama.status {
            case .notInstalled:
                Button(tr("Ollama を入手", "Get Ollama")) {
                    NSWorkspace.shared.open(URL(string: "https://ollama.com/download")!)
                }
                .buttonStyle(.borderedProminent)
            case .installedNotRunning:
                Button(startingServer ? tr("起動中…", "Starting…") : tr("サーバーを起動", "Start Server")) {
                    startingServer = true
                    Task {
                        _ = await app.ollama.startServer()
                        startingServer = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(startingServer)
            default:
                Button {
                    Task { await app.ollama.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help(tr("再読み込み", "Refresh"))
            }
        }
        .padding(18)
        .card()
    }

    private var serverTitle: String {
        switch app.ollama.status {
        case .running(let version): return tr("Ollama 稼働中(v\(version))", "Ollama Running (v\(version))")
        case .installedNotRunning: return tr("Ollama は停止しています", "Ollama Is Not Running")
        case .notInstalled: return tr("Ollama が見つかりません", "Ollama Not Found")
        case .unknown: return tr("確認中…", "Checking…")
        }
    }

    private var serverDetail: String {
        switch app.ollama.status {
        case .running: return tr("モデルはすべてローカルで動作します。", "All models run locally on your Mac.")
        case .installedNotRunning: return tr("サーバーを起動するとモデルの管理と整形が使えるようになります。", "Start the server to manage models and use refinement.")
        case .notInstalled: return tr("Ollama を使わない場合は、上の切替から「内蔵エンジン」をお選びください。", "If you prefer not to use Ollama, select \"Built-in Engine\" above.")
        case .unknown: return ""
        }
    }

    // MARK: - Ollama: セットアップガイド

    private var installGuideCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(tr("Ollama のセットアップ", "Set Up Ollama"))
                .font(.system(size: 14, weight: .semibold))

            guideRow(number: "1", title: tr("Ollama をインストール", "Install Ollama")) {
                HStack(spacing: 10) {
                    Button(tr("公式サイトからダウンロード", "Download from Official Site")) {
                        NSWorkspace.shared.open(URL(string: "https://ollama.com/download")!)
                    }
                    Text(tr("または", "or"))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Button {
                        _ = Paster.deliver("brew install ollama && brew services start ollama",
                                           paste: false, keepInClipboard: true)
                        copiedBrew = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedBrew = false }
                    } label: {
                        HStack(spacing: 6) {
                            Text("brew install ollama")
                                .font(.system(size: 11, design: .monospaced))
                            Image(systemName: copiedBrew ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10))
                        }
                    }
                    .help(tr("Homebrew コマンドをコピー", "Copy Homebrew Command"))
                }
            }

            guideRow(number: "2", title: tr("この画面に戻って「再確認」", "Come back here and click \"Check Again\"")) {
                Button {
                    Task { await app.ollama.refresh() }
                } label: {
                    Label(tr("再確認", "Check Again"), systemImage: "arrow.clockwise")
                        .font(.system(size: 12))
                }
            }

            guideRow(number: "3", title: tr("モデルをワンクリックでダウンロード", "Download a model with one click")) {
                Text(tr("接続後、この画面に Ollama 用モデルのカタログが表示されます。", "Once connected, a catalog of Ollama models will appear here."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .card()
    }

    private func guideRow<Content: View>(number: String, title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(number)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Brand.gradient))
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                content()
            }
            Spacer()
        }
    }

    // MARK: - Ollama: インストール済み

    @ViewBuilder
    private var installedCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tr("インストール済みモデル", "Installed Models"))
                .font(.system(size: 14, weight: .semibold))
                .padding(.bottom, 6)

            if app.ollama.installed.isEmpty {
                Text(tr("まだモデルがありません。下のカタログからダウンロードしてください。", "No models yet. Download one from the catalog below."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)
            } else {
                ForEach(app.ollama.installed) { model in
                    installedRow(model)
                    if model.id != app.ollama.installed.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(18)
        .card()
    }

    private func installedRow(_ model: InstalledModel) -> some View {
        let isActive = app.settings.value.model == model.name
        return HStack(spacing: 12) {
            Button {
                app.settings.value.model = model.name
            } label: {
                Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isActive ? Brand.primary : .secondary)
            }
            .buttonStyle(.plain)
            .help(tr("このモデルを使用", "Use This Model"))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(model.name)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                    if isActive {
                        Chip(text: tr("使用中", "In Use"), tint: Brand.primary)
                    }
                }
                HStack(spacing: 8) {
                    if let p = model.parameterSize { Text(p) }
                    if let q = model.quantization { Text(q) }
                    Text(Format.bytes(model.size))
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await app.ollama.delete(model.name) }
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(tr("削除", "Delete"))
        }
        .padding(.vertical, 6)
    }

    // MARK: - Ollama: カタログ

    private var catalogCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tr("おすすめモデル", "Recommended Models"))
                .font(.system(size: 14, weight: .semibold))
            Text(tr("日本語の指示整形に向いたモデルを厳選しています。", "A curated selection of models well suited to prompt refinement."))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)

            ForEach(ModelCatalog.all) { model in
                catalogRow(model)
                if model.id != ModelCatalog.all.last?.id {
                    Divider()
                }
            }
        }
        .padding(18)
        .card()
    }

    private func catalogRow(_ model: CatalogModel) -> some View {
        let installed = app.ollama.installed.contains { $0.name == model.name }
        let progress = app.ollama.pulls[model.name]

        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(model.title)
                        .font(.system(size: 13, weight: .semibold))
                    Chip(text: model.vendor, tint: .secondary)
                    if model.recommended {
                        Chip(text: tr("おすすめ", "Recommended"), icon: "star.fill", tint: .orange)
                    }
                }
                Text(model.description)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    stars(model.japaneseStars)
                    Text(model.sizeLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Text(model.name)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if installed {
                Label(tr("導入済み", "Installed"), systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
            } else if let progress {
                pullProgressView(name: model.name, progress: progress)
            } else {
                Button {
                    app.ollama.pull(model.name)
                } label: {
                    Label(tr("ダウンロード", "Download"), systemImage: "arrow.down.circle")
                        .font(.system(size: 12))
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func pullProgressView(name: String, progress: PullProgress) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 8) {
                Text(progressLabel(progress))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button {
                    app.ollama.cancelPull(name)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(tr("キャンセル", "Cancel"))
            }
            ProgressView(value: progress.fraction ?? 0)
                .progressViewStyle(.linear)
                .frame(width: 160)
        }
    }

    private func progressLabel(_ p: PullProgress) -> String {
        if let fraction = p.fraction, let total = p.total, let completed = p.completed {
            return "\(Int(fraction * 100))%(\(Format.bytes(completed)) / \(Format.bytes(total)))"
        }
        return p.status
    }

    private func stars(_ n: Int) -> some View {
        HStack(spacing: 1) {
            ForEach(0..<5, id: \.self) { i in
                Image(systemName: i < n ? "star.fill" : "star")
                    .font(.system(size: 8))
                    .foregroundStyle(i < n ? Color.orange : Color.secondary.opacity(0.4))
            }
            Text(tr("日本語", "Japanese"))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.leading, 3)
        }
    }

    // MARK: - Ollama: 任意のモデル

    private var customPullCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("その他のモデル", "Other Models"))
                .font(.system(size: 14, weight: .semibold))
            Text(tr("Ollama ライブラリの任意のモデルタグを指定してダウンロードできます。", "Download any model tag from the Ollama library."))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                TextField(tr("例: qwen3:14b", "e.g. qwen3:14b"), text: $customModel)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .onSubmit { pullCustom() }

                if let progress = app.ollama.pulls[customModel.trimmingCharacters(in: .whitespaces)] {
                    pullProgressView(name: customModel.trimmingCharacters(in: .whitespaces), progress: progress)
                } else {
                    Button(tr("ダウンロード", "Download")) { pullCustom() }
                        .disabled(customModel.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Link(tr("モデルライブラリを見る(ollama.com/library)", "Browse the Model Library (ollama.com/library)"),
                 destination: URL(string: "https://ollama.com/library")!)
                .font(.system(size: 11))
        }
        .padding(18)
        .card()
    }

    private func pullCustom() {
        let name = customModel.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        app.ollama.pull(name)
    }
}
