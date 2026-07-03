import Foundation
import AppKit

struct InstalledModel: Identifiable, Hashable {
    var name: String
    var size: Int64
    var parameterSize: String?
    var quantization: String?

    var id: String { name }
}

struct PullProgress: Equatable {
    var status: String = tr("接続中…", "Connecting…")
    var total: Int64?
    var completed: Int64?

    var fraction: Double? {
        guard let total, let completed, total > 0 else { return nil }
        return Double(completed) / Double(total)
    }
}

@MainActor
final class OllamaClient: ObservableObject {
    enum Status: Equatable {
        case unknown
        case notInstalled
        case installedNotRunning
        case running(version: String)

        var isRunning: Bool {
            if case .running = self { return true }
            return false
        }
    }

    @Published private(set) var status: Status = .unknown
    @Published private(set) var installed: [InstalledModel] = []
    @Published private(set) var pulls: [String: PullProgress] = [:]
    @Published private(set) var lastError: String?

    private let settings: SettingsStore
    private var pullTasks: [String: Task<Void, Never>] = [:]

    init(settings: SettingsStore) {
        self.settings = settings
    }

    private var host: URL {
        URL(string: settings.value.ollamaHost) ?? URL(string: "http://127.0.0.1:11434")!
    }

    // MARK: - 状態検出

    func refresh() async {
        do {
            var req = URLRequest(url: host.appendingPathComponent("api/version"))
            req.timeoutInterval = 3
            let (data, _) = try await URLSession.shared.data(for: req)
            let version = (try? JSONDecoder().decode(VersionResponse.self, from: data))?.version ?? "?"
            status = .running(version: version)
            lastError = nil
            await refreshModels()
        } catch {
            installed = []
            status = Self.findInstallation() != nil ? .installedNotRunning : .notInstalled
        }
    }

    func refreshModels() async {
        do {
            var req = URLRequest(url: host.appendingPathComponent("api/tags"))
            req.timeoutInterval = 5
            let (data, _) = try await URLSession.shared.data(for: req)
            let tags = try JSONDecoder().decode(TagsResponse.self, from: data)
            installed = tags.models.map {
                InstalledModel(
                    name: $0.name,
                    size: $0.size,
                    parameterSize: $0.details?.parameter_size,
                    quantization: $0.details?.quantization_level
                )
            }
            .sorted { $0.name < $1.name }
        } catch {
            // サーバー停止中など。状態は refresh() 側で扱う
        }
    }

    enum Installation {
        case app(URL)
        case binary(String)
    }

    nonisolated static func findInstallation() -> Installation? {
        let appURL = URL(fileURLWithPath: "/Applications/Ollama.app")
        if FileManager.default.fileExists(atPath: appURL.path) {
            return .app(appURL)
        }
        for path in ["/opt/homebrew/bin/ollama", "/usr/local/bin/ollama", "/usr/bin/ollama"] {
            if FileManager.default.isExecutableFile(atPath: path) {
                return .binary(path)
            }
        }
        return nil
    }

    /// Ollama サーバーの起動を試み、起動を待つ
    func startServer() async -> Bool {
        guard let installation = Self.findInstallation() else { return false }
        switch installation {
        case .app(let url):
            NSWorkspace.shared.open(url)
        case .binary(let path):
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", "nohup \(path) serve >/dev/null 2>&1 &"]
            try? process.run()
        }
        // 最大 15 秒ポーリング
        for _ in 0..<30 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            await refresh()
            if status.isRunning { return true }
        }
        return status.isRunning
    }

    // MARK: - モデル管理

    var isPulling: Bool { !pulls.isEmpty }

    func pull(_ name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, pullTasks[name] == nil else { return }
        pulls[name] = PullProgress()

        pullTasks[name] = Task { [weak self] in
            guard let self else { return }
            do {
                var req = URLRequest(url: self.host.appendingPathComponent("api/pull"))
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.timeoutInterval = 3600
                req.httpBody = try JSONEncoder().encode(PullRequest(model: name, stream: true))

                let (bytes, response) = try await URLSession.shared.bytes(for: req)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw YouyakuError(tr("モデルの取得を開始できませんでした", "Could not start downloading the model"))
                }
                for try await line in bytes.lines {
                    if Task.isCancelled { break }
                    guard let data = line.data(using: .utf8) else { continue }
                    if let err = try? JSONDecoder().decode(ErrorResponse.self, from: data), !err.error.isEmpty {
                        throw YouyakuError(err.error)
                    }
                    if let chunk = try? JSONDecoder().decode(PullChunk.self, from: data) {
                        self.pulls[name] = PullProgress(
                            status: Self.localizedPullStatus(chunk.status),
                            total: chunk.total ?? self.pulls[name]?.total,
                            completed: chunk.completed ?? self.pulls[name]?.completed
                        )
                        if chunk.status == "success" { break }
                    }
                }
                await self.refreshModels()
            } catch is CancellationError {
                // ユーザーによるキャンセル
            } catch {
                self.lastError = tr("\(name) のダウンロードに失敗: \(error.localizedDescription)", "Failed to download \(name): \(error.localizedDescription)")
            }
            self.pulls[name] = nil
            self.pullTasks[name] = nil
        }
    }

    func cancelPull(_ name: String) {
        pullTasks[name]?.cancel()
        pullTasks[name] = nil
        pulls[name] = nil
    }

    func delete(_ name: String) async {
        do {
            var req = URLRequest(url: host.appendingPathComponent("api/delete"))
            req.httpMethod = "DELETE"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            // 旧 API は "name"、新 API は "model" を受け取るため両方送る
            req.httpBody = try JSONSerialization.data(withJSONObject: ["name": name, "model": name])
            _ = try await URLSession.shared.data(for: req)
            await refreshModels()
        } catch {
            lastError = tr("\(name) の削除に失敗: \(error.localizedDescription)", "Failed to delete \(name): \(error.localizedDescription)")
        }
    }

    // MARK: - チャット(ストリーミング)

    func chatStream(model: String, system: String, prompt: String, temperature: Double) -> AsyncThrowingStream<String, Error> {
        let host = self.host
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var req = URLRequest(url: host.appendingPathComponent("api/chat"))
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.timeoutInterval = 600
                    var messages: [ChatRequest.Message] = []
                    if !system.isEmpty {
                        messages.append(.init(role: "system", content: system))
                    }
                    messages.append(.init(role: "user", content: prompt))
                    req.httpBody = try JSONEncoder().encode(ChatRequest(
                        model: model,
                        messages: messages,
                        stream: true,
                        options: .init(temperature: temperature),
                        keep_alive: "10m"
                    ))

                    let (bytes, response) = try await URLSession.shared.bytes(for: req)
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if code != 200 {
                        var body = ""
                        for try await line in bytes.lines { body += line }
                        if let data = body.data(using: .utf8),
                           let err = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                            throw YouyakuError(err.error)
                        }
                        throw YouyakuError(tr("LLM サーバーがエラーを返しました (HTTP \(code))", "The LLM server returned an error (HTTP \(code))"))
                    }

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard let data = line.data(using: .utf8) else { continue }
                        if let err = try? JSONDecoder().decode(ErrorResponse.self, from: data), !err.error.isEmpty {
                            throw YouyakuError(err.error)
                        }
                        guard let chunk = try? JSONDecoder().decode(ChatChunk.self, from: data) else { continue }
                        if let content = chunk.message?.content, !content.isEmpty {
                            continuation.yield(content)
                        }
                        if chunk.done == true { break }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - JSON 型

    private struct VersionResponse: Decodable { let version: String }

    private struct TagsResponse: Decodable {
        struct Model: Decodable {
            let name: String
            let size: Int64
            let details: Details?
            struct Details: Decodable {
                let parameter_size: String?
                let quantization_level: String?
            }
        }
        let models: [Model]
    }

    private struct PullRequest: Encodable {
        let model: String
        let stream: Bool
    }

    private struct PullChunk: Decodable {
        let status: String
        let total: Int64?
        let completed: Int64?
    }

    private struct ErrorResponse: Decodable { let error: String }

    private struct ChatRequest: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }
        struct Options: Encodable {
            let temperature: Double
        }
        let model: String
        let messages: [Message]
        let stream: Bool
        let options: Options
        let keep_alive: String
    }

    private struct ChatChunk: Decodable {
        struct Message: Decodable { let content: String? }
        let message: Message?
        let done: Bool?
    }

    private static func localizedPullStatus(_ status: String) -> String {
        switch status {
        case "success": return tr("完了", "Done")
        case let s where s.hasPrefix("pulling manifest"): return tr("マニフェスト取得中…", "Fetching manifest…")
        case let s where s.hasPrefix("pulling"): return tr("ダウンロード中…", "Downloading…")
        case let s where s.hasPrefix("verifying"): return tr("検証中…", "Verifying…")
        case let s where s.hasPrefix("writing"): return tr("書き込み中…", "Writing…")
        case let s where s.hasPrefix("removing"): return tr("後処理中…", "Cleaning up…")
        default: return status
        }
    }
}
