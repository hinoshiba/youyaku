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

    // デリゲート(nonisolated)と共有するメタ情報。MainActor プロパティを
    // デリゲートから直接読めないため、ロック越しに受け渡す
    private let metaLock = NSLock()
    private nonisolated(unsafe) var expectedSizes: [String: Int64] = [:]

    nonisolated static var directory: URL {
        SettingsStore.directory.appendingPathComponent("Models", isDirectory: true)
    }

    // 中断したダウンロードの再開情報(URLSession の resumeData)を保存する場所。
    // アプリ再起動後も「もう一度ダウンロード」で途中から再開できる
    nonisolated static var partialsDirectory: URL {
        directory.appendingPathComponent(".partials", isDirectory: true)
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
        try? FileManager.default.createDirectory(at: Self.partialsDirectory, withIntermediateDirectories: true)
        // モデルは再ダウンロード可能なデータのため、iCloud/デバイスバックアップから除外する
        // (iOS Data Storage Guidelines。数GBのモデルで無料 iCloud 枠を圧迫しないため)
        Self.excludeFromBackup(Self.directory)
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

    /// 保存に使ってよいファイル名だけを通す(パス区切りや相対参照で
    /// Models/ の外へ書き出されるのを防ぐ)。不正なら nil
    nonisolated static func sanitizedFileName(_ raw: String) -> String? {
        let name = (raw.trimmingCharacters(in: .whitespaces) as NSString).lastPathComponent
        guard !name.isEmpty,
              !name.hasPrefix("."),
              !name.contains("/"), !name.contains("\\"), !name.contains("\0")
        else { return nil }
        return name
    }

    func download(from url: URL, fileName rawFileName: String, expectedBytes: Int64? = nil) {
        guard let fileName = Self.sanitizedFileName(rawFileName) else {
            lastError = tr("ファイル名に使用できない文字が含まれています", "The file name contains characters that cannot be used")
            return
        }
        guard tasks[fileName] == nil else { return }
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
        metaLock.lock()
        expectedSizes[fileName] = expectedBytes ?? 0
        metaLock.unlock()

        // 前回中断分の再開情報があれば途中から再開する
        let task: URLSessionDownloadTask
        if let resumeData = Self.takeResumeData(for: fileName) {
            task = session.downloadTask(withResumeData: resumeData)
        } else {
            var request = URLRequest(url: url)
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            task = session.downloadTask(with: request)
        }
        task.taskDescription = fileName
        tasks[fileName] = task
        task.resume()
    }

    func cancel(_ fileName: String) {
        // 再開情報を残してキャンセルする(次回のダウンロードは途中から再開される)
        tasks[fileName]?.cancel { data in
            guard let data else { return }
            Task { @MainActor [weak self] in
                // キャンセル直後に同名の再ダウンロードが始まっていたら、
                // 古い再開情報で新しいダウンロードを壊さない
                guard self == nil || self?.tasks[fileName] == nil else { return }
                Self.storeResumeData(data, for: fileName)
            }
        }
        tasks[fileName] = nil
        downloads[fileName] = nil
        lastPublished[fileName] = nil
        metaLock.lock()
        expectedSizes[fileName] = nil
        metaLock.unlock()
    }

    func delete(_ model: LocalModel) {
        try? FileManager.default.removeItem(at: model.fileURL)
        Self.removeResumeData(for: model.fileName)
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
        metaLock.lock()
        expectedSizes[fileName] = nil
        metaLock.unlock()
        if let error {
            if wasTracked { lastError = error }
        } else {
            refresh()
            if wasTracked { onInstalled?(fileName) }
        }
    }

    // MARK: - ユーティリティ

    private nonisolated static var userAgent: String {
        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0"
        #if os(iOS)
        return "Youyaku/\(version) (iOS)"
        #else
        return "Youyaku/\(version) (macOS)"
        #endif
    }

    private nonisolated static func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    // MARK: - 再開情報(resumeData)の保存

    private nonisolated static func resumeDataURL(for fileName: String) -> URL {
        partialsDirectory.appendingPathComponent(fileName + ".resume")
    }

    fileprivate nonisolated static func storeResumeData(_ data: Data, for fileName: String) {
        try? FileManager.default.createDirectory(at: partialsDirectory, withIntermediateDirectories: true)
        try? data.write(to: resumeDataURL(for: fileName), options: .atomic)
        excludeFromBackup(partialsDirectory)
    }

    private nonisolated static func takeResumeData(for fileName: String) -> Data? {
        let url = resumeDataURL(for: fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.removeItem(at: url)
        return data
    }

    fileprivate nonisolated static func removeResumeData(for fileName: String) {
        try? FileManager.default.removeItem(at: resumeDataURL(for: fileName))
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

        metaLock.lock()
        let expected = expectedSizes[fileName] ?? 0
        metaLock.unlock()
        let actualSize = (try? FileManager.default.attributesOfItem(atPath: location.path)[.size] as? Int64) ?? nil

        if status != 200, status != 206 {
            errorMessage = Self.httpErrorMessage(status)
        } else if expected > 0, let actualSize, actualSize != expected {
            // カタログ記載サイズとの完全一致を要求する(配布元での差し替え・
            // 途中破損をここで検出する。カタログは URL をコミット SHA に固定済み)
            errorMessage = tr(
                "ダウンロードしたファイルのサイズが想定と一致しません(想定 \(Format.bytes(expected)) / 実際 \(Format.bytes(actualSize)))。配布元でファイルが変更された可能性があります。",
                "The downloaded file size does not match the expected size (expected \(Format.bytes(expected)), got \(Format.bytes(actualSize))). The file may have changed at the source."
            )
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
                Self.excludeFromBackup(dest)
                Self.removeResumeData(for: fileName)
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
        // 通信断などの失敗時は再開情報を保存し、次回のダウンロードで途中から再開する
        var suffix = ""
        if let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
            Self.storeResumeData(resumeData, for: fileName)
            suffix = tr(" もう一度ダウンロードすると途中から再開します。", " Download again to resume from where it left off.")
        }
        let message = tr("ダウンロードに失敗しました: \(error.localizedDescription)", "Download failed: \(error.localizedDescription)") + suffix
        Task { @MainActor [weak self] in
            self?.finish(fileName: fileName, error: message)
        }
    }

    private nonisolated static func httpErrorMessage(_ status: Int) -> String {
        switch status {
        case 401, 403:
            return tr("配布元がダウンロードを制限しています (HTTP \(status))。モデルの配布条件が変更された可能性があります。アプリの更新や配布元の情報を確認してください。",
                      "The source has restricted this download (HTTP \(status)). The model's distribution terms may have changed. Check for app updates or the source page.")
        case 404:
            return tr("配布元にファイルが見つかりません (HTTP 404)。ファイルが移動または削除された可能性があります。",
                      "The file was not found at the source (HTTP 404). It may have been moved or deleted.")
        case 429:
            return tr("配布元へのアクセスが混み合っています (HTTP 429)。しばらく時間をおいてから再試行してください。",
                      "The source is rate-limiting downloads (HTTP 429). Please wait a while and try again.")
        case 500...599:
            return tr("配布元サーバーでエラーが発生しました (HTTP \(status))。しばらくしてから再試行してください。",
                      "The source server returned an error (HTTP \(status)). Please try again later.")
        default:
            return tr("サーバーがエラーを返しました (HTTP \(status))", "The server returned an error (HTTP \(status))")
        }
    }

    private nonisolated static func looksLikeGGUF(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let magic = try? handle.read(upToCount: 4) else { return false }
        try? handle.close()
        return magic == Data("GGUF".utf8)
    }
}
