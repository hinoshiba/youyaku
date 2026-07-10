#if os(macOS)
import Combine
import Foundation
import Sparkle

// 直販(App Store 外)配布の macOS 版には OS による更新機構がないため、Sparkle を使って
// アプリ内でアップデートを完結させる。配布サイトの appcast.xml(build.sh --dist が生成)を
// 定期取得し、利用者が選んだときに DMG のダウンロード → 検証 → 入れ替え → 再起動まで行う。
//
// 安全性: Sparkle は DMG を EdDSA 署名(Info.plist の SUPublicEDKey に対応する秘密鍵で署名)で
// 検証し、さらに新旧アプリの Developer ID 署名が一致することを確認してから入れ替える。
//
// プライバシー上の注意: 通信は youyaku.hinoshiba.com への appcast.xml(数百バイト)の GET と、
// 利用者がアップデートを選んだときの DMG のダウンロードのみで、端末の情報は送信しない
// (User-Agent 以外。Sparkle の匿名システムプロファイル送信は既定のオフのまま使う)。
// 設定「アップデートを自動確認」でオフにできる。サイト・README の「外部通信」の記載には
// この通信を明記してある。
// Sparkle の SPUUpdater / SPUUpdaterDelegate は @MainActor(NS_SWIFT_UI_ACTOR)なので、
// こちらもメインアクタに載せる。
@MainActor
final class Updater: NSObject, ObservableObject {
    /// 現在より新しいバージョンが配布されていればその表示名(例: "1.1.0")
    @Published private(set) var availableVersion: String?

    /// Info.plist の SUPublicEDKey が未設定のときに入っている値(Scripts/setup-sparkle-keys.sh で置き換える)。
    /// build.sh --dist はこの値のままの配布ビルドを拒否する。
    static let placeholderPublicKey = "REPLACE_WITH_SPARKLE_PUBLIC_ED_KEY"

    /// 公開鍵が未設定なら更新機構ごと無効にする。鍵が無いと Sparkle は署名検証に必ず失敗するので、
    /// バナーを出してから失敗させるより、最初から何も表示せず通信もしない方がよい。
    private static var isConfigured: Bool {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String else { return false }
        return !key.isEmpty && key != placeholderPublicKey
    }

    // delegate に self を渡す必要があるため super.init 後に作る
    private var controller: SPUStandardUpdaterController?

    /// 自動更新が使える構成か(未設定なら UI 側も更新関連の導線を隠す)
    var isEnabled: Bool { controller != nil }

    init(automaticallyChecks: Bool) {
        super.init()
        guard Self.isConfigured else {
            NSLog("Youyaku: Info.plist の SUPublicEDKey が未設定のため、アプリ内アップデートを無効にしました")
            return
        }
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
        controller.updater.automaticallyChecksForUpdates = automaticallyChecks
        self.controller = controller
    }

    /// 設定「アップデートを自動確認」の反映(オフにすると定期チェックの通信も止まる)
    func setAutomaticChecks(_ enabled: Bool) {
        controller?.updater.automaticallyChecksForUpdates = enabled
    }

    /// 利用者の操作による更新確認。新版があれば Sparkle の確認ダイアログを表示し、
    /// そこからダウンロード → インストール → 再起動まで進む。
    func checkForUpdates() {
        controller?.updater.checkForUpdates()
    }
}

extension Updater: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        availableVersion = item.displayVersionString
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        availableVersion = nil
    }

    // 取得失敗(オフライン等)は静かに無視する。次回のチェックで再試行される
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {}
}

// SPUStandardUserDriverDelegate は SPUUpdaterDelegate と違いメインアクタに縛られていないため、
// 下の 2 つは nonisolated で満たす(どちらも状態を触らない定数返しなので問題ない)。
extension Updater: SPUStandardUserDriverDelegate {
    // メニューバー常駐アプリなので、定期チェックで更新ダイアログを勝手に前面に出さない。
    // 代わりにホーム画面とメニューのバナーで知らせ、利用者が押したときに Sparkle の UI を出す
    // (Sparkle の "gentle reminders")。
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }
}
#endif
