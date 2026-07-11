# http_dist/download/

Mac 版 Youyaku の配布に関わる **小さなテキストファイル** を置くディレクトリ。DMG 本体は **GitHub Releases** にある。

`build.sh --dist`(公証あり)を実行すると、`Scripts/make-dmg.sh` がここに生成する:

- `appcast.xml` … Sparkle(アプリ内アップデート)の更新フィード。アプリの `SUFeedURL` が指す先。最新版の版数・最低 OS・DMG の URL・EdDSA 署名を含む(生成物。手で編集しない)。
- `version.txt` … 配布中のバージョン文字列(例: `1.0.0`)。トップページが読んで表示する。
- `notes/<version>.html`(任意) … 置いておくと、アップデート画面にリリースノートとして表示される。

DMG は版に依らず `Youyaku.dmg` の名前で Releases に置き、タグ(`v<version>`)で版を分ける。そのため URL は次の 2 つを使い分けられる:

- appcast の `enclosure` … `https://github.com/hinoshiba/youyaku/releases/download/v<version>/Youyaku.dmg`
- サイトのダウンロードボタン … `https://github.com/hinoshiba/youyaku/releases/latest/download/Youyaku.dmg`

## 配布フロー

手順の詳細と実行順の理由は **[docs/RELEASE.md](../../docs/RELEASE.md)**「リリースごとの手順」を参照。
要点は「**先に Releases へ DMG を上げ、あとから appcast.xml を push する**」こと。
