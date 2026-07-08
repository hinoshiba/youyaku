#if os(macOS)
import Foundation

// 直販(App Store 外)配布の macOS 版には OS による更新通知がないため、
// 配布サイトの version.txt(build.sh --dist が生成)を定期取得して
// 新バージョンの存在を利用者に知らせる。
//
// プライバシー上の注意: 通信は youyaku.hinoshiba.com へのバージョン文字列(数バイト)の
// GET のみで、端末の情報は送信しない(User-Agent 以外)。設定
// 「アップデートを自動確認」でオフにできる。サイト・README の
// 「外部通信」の記載にはこの通信を明記してある。
@MainActor
final class UpdateChecker: ObservableObject {
    /// 現在より新しいバージョンが配布されていればその文字列(例: "1.1.0")
    @Published private(set) var availableVersion: String?

    static let downloadPageURL = URL(string: "https://youyaku.hinoshiba.com/#download")!
    private static let versionURL = URL(string: "https://youyaku.hinoshiba.com/download/version.txt")!
    private static let interval: TimeInterval = 60 * 60 * 24   // 1日1回

    private var timer: Timer?
    // 「1日1回」の表明(privacy.html / 設定画面ヘルプ)を再起動をまたいで守るため、
    // 最終確認日時はファイルに永続化する
    private var lastChecked: Date
    private let isEnabled: () -> Bool

    private static var stampURL: URL {
        SettingsStore.directory.appendingPathComponent("update-check.stamp")
    }

    var currentVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
    }

    init(isEnabled: @escaping () -> Bool) {
        self.isEnabled = isEnabled
        let stamp = (try? String(contentsOf: Self.stampURL, encoding: .utf8))
            .flatMap { TimeInterval($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        lastChecked = stamp.map(Date.init(timeIntervalSince1970:)) ?? .distantPast
        // 起動直後(少し遅らせて)+ 以後は1日1回。オフ設定なら何も通信しない
        Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.checkIfDue() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.checkIfDue() }
        }
    }

    private func checkIfDue() async {
        guard isEnabled(), Date().timeIntervalSince(lastChecked) > Self.interval - 60 else { return }
        await check()
    }

    /// version.txt を取得して比較する。失敗は静かに無視する(次回に再試行)
    func check() async {
        lastChecked = Date()
        try? String(lastChecked.timeIntervalSince1970).write(to: Self.stampURL, atomically: true, encoding: .utf8)
        var request = URLRequest(url: Self.versionURL)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let text = String(data: data, encoding: .utf8) else { return }
        let remote = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remote.isEmpty, remote.count <= 32 else { return }
        availableVersion = Self.isNewer(remote, than: currentVersion) ? remote : nil
    }

    /// "1.2.3" 形式の数値比較(桁数が違っても不足分は 0 とみなす)
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
#endif
