import Foundation
#if os(macOS)
import AppKit
#endif

struct LocalModel: Identifiable, Hashable {
    var fileName: String
    var size: Int64
    var fileURL: URL

    var id: String { fileName }

    var displayName: String {
        fileName.hasSuffix(".gguf") ? String(fileName.dropLast(5)) : fileName
    }
}

struct ModelDownload {
    var totalBytes: Int64
    var receivedBytes: Int64

    var fraction: Double? {
        guard totalBytes > 0 else { return nil }
        return Double(receivedBytes) / Double(totalBytes)
    }
}

// GGUF モデルを Hugging Face 等から直接ダウンロード・管理する
@MainActor
final class ModelStore: NSObject, ObservableObject {
    @Published private(set) var installed: [LocalModel] = []
    @Published private(set) var downloads: [String: ModelDownload] = [:]
    @Published var lastError: String?

    /// カタログDL完了時などに呼ばれる(未選択ならそのモデルを既定にする用途)
    var onInstalled: ((String) -> Void)?

    private var tasks: [String: URLSessionDownloadTask] = [:]
    private var lastPublished: [String: Double] = [:]

    nonisolated static var directory: URL {
        SettingsStore.directory.appendingPathComponent("Models", isDirectory: true)
    }

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 60 * 60 * 6
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    override init() {
        super.init()
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        refresh()
    }

    func refresh() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: Self.directory,
            includingPropertiesForKeys: [.fileSizeKey]
        )) ?? []
        installed = files
            .filter { $0.pathExtension.lowercased() == "gguf" }
            .compactMap { url in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                return LocalModel(fileName: url.lastPathComponent, size: size, fileURL: url)
            }
            .sorted { $0.fileName < $1.fileName }
    }

    var freeDiskSpace: Int64 {
        let attrs = try? FileManager.default.attributesOfFileSystem(forPath: Self.directory.path)
        return (attrs?[.systemFreeSize] as? Int64) ?? 0
    }

    // MARK: - ダウンロード

    func download(from url: URL, fileName: String, expectedBytes: Int64? = nil) {
        let fileName = fileName.trimmingCharacters(in: .whitespaces)
        guard !fileName.isEmpty, tasks[fileName] == nil else { return }
        guard fileName.lowercased().hasSuffix(".gguf") else {
            lastError = tr("GGUF ファイル(.gguf)の URL を指定してください", "Please provide a URL to a GGUF (.gguf) file")
            return
        }
        // サイズ不明(任意URL)の場合も最低 2GB の余裕を要求する
        let required = max(expectedBytes ?? 0, 1_000_000_000)
        if freeDiskSpace < required + 1_000_000_000 {
            lastError = tr("ディスクの空き容量が不足しています(必要: 約 \(Format.bytes(required)) + 余裕)", "Not enough free disk space (about \(Format.bytes(required)) needed, plus headroom)")
            return
        }

        lastError = nil
        downloads[fileName] = ModelDownload(totalBytes: expectedBytes ?? 0, receivedBytes: 0)

        var request = URLRequest(url: url)
        request.setValue("Youyaku/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        let task = session.downloadTask(with: request)
        task.taskDescription = fileName
        tasks[fileName] = task
        task.resume()
    }

    func cancel(_ fileName: String) {
        tasks[fileName]?.cancel()
        tasks[fileName] = nil
        downloads[fileName] = nil
        lastPublished[fileName] = nil
    }

    func delete(_ model: LocalModel) {
        try? FileManager.default.removeItem(at: model.fileURL)
        refresh()
    }

    var canRevealInFinder: Bool {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }

    func revealInFinder() {
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([Self.directory])
        #endif
    }

    // MARK: - 完了処理(デリゲートから)

    fileprivate func updateProgress(fileName: String, received: Int64, total: Int64) {
        // キャンセル後に届いた遅延コールバックで行が復活しないよう、追跡中のみ反映
        guard tasks[fileName] != nil else { return }

        if total > 0 {
            // 描画負荷を抑えるため 0.5% 刻みで発行
            let fraction = Double(received) / Double(total)
            if fraction - (lastPublished[fileName] ?? 0) < 0.005, fraction < 1.0 { return }
            lastPublished[fileName] = fraction
        } else {
            // サイズ不明時は 16MB ごとに発行(受信バイト数を進捗代わりに表示)
            if Double(received) - (lastPublished[fileName] ?? 0) < 16_000_000 { return }
            lastPublished[fileName] = Double(received)
        }
        downloads[fileName] = ModelDownload(totalBytes: total, receivedBytes: received)
    }

    fileprivate func finish(fileName: String, error: String?) {
        // すでにキャンセル済み(追跡外)なら、状態掃除だけして自動選択などは行わない
        let wasTracked = tasks[fileName] != nil
        downloads[fileName] = nil
        tasks[fileName] = nil
        lastPublished[fileName] = nil
        if let error {
            if wasTracked { lastError = error }
        } else {
            refresh()
            if wasTracked { onInstalled?(fileName) }
        }
    }
}

extension ModelStore: URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let fileName = downloadTask.taskDescription else { return }
        Task { @MainActor [weak self] in
            self?.updateProgress(fileName: fileName, received: totalBytesWritten, total: totalBytesExpectedToWrite)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let fileName = downloadTask.taskDescription else { return }
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        var errorMessage: String?

        if status != 200 {
            errorMessage = tr("サーバーがエラーを返しました (HTTP \(status))", "The server returned an error (HTTP \(status))")
        } else if !Self.looksLikeGGUF(location) {
            errorMessage = tr("ダウンロードしたファイルが GGUF 形式ではありません(URL を確認してください)", "The downloaded file is not in GGUF format (please check the URL)")
        } else {
            // 一時ファイルはこのメソッドを抜けると消えるため、同期的に移動する
            let dest = ModelStore.directory.appendingPathComponent(fileName)
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.moveItem(at: location, to: dest)
            } catch {
                errorMessage = tr("ファイルの保存に失敗しました: \(error.localizedDescription)", "Failed to save the file: \(error.localizedDescription)")
            }
        }

        let message = errorMessage
        Task { @MainActor [weak self] in
            self?.finish(fileName: fileName, error: message)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, (error as NSError).code != NSURLErrorCancelled,
              let fileName = task.taskDescription else { return }
        Task { @MainActor [weak self] in
            self?.finish(fileName: fileName, error: tr("ダウンロードに失敗しました: \(error.localizedDescription)", "Download failed: \(error.localizedDescription)"))
        }
    }

    private nonisolated static func looksLikeGGUF(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let magic = try? handle.read(upToCount: 4) else { return false }
        try? handle.close()
        return magic == Data("GGUF".utf8)
    }
}
