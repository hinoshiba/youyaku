# http_dist/download/

Mac 版 Youyaku の配布に関わる **小さなテキストファイル** を置くディレクトリ。
DMG 本体はここには置かない(**GitHub Releases** にある)。

`build.sh --dist`(公証あり)を実行すると、`Scripts/make-dmg.sh` がここに生成する:

- `appcast.xml` … Sparkle(アプリ内アップデート)の更新フィード。アプリの `SUFeedURL` が指す先。
  最新版の版数・最低 OS・DMG の URL・EdDSA 署名を含む。**手で編集しない**。
- `version.txt` … 配布中のバージョン文字列(例: `1.0.0`)。トップページが読んで表示する。
- `notes/<version>.html`(任意) … 置いておくと、アップデート画面にリリースノートとして表示される。

## なぜ DMG をここに置かないのか

DMG はバイナリなので、commit するとリリースごとにリポジトリ履歴が数 MiB ずつ太り続ける。
代わりに **GitHub Releases** のアセットとして公開し、ここには「どこにあるか」を書いた
フィードだけを置く。

- appcast の `enclosure` … `https://github.com/hinoshiba/youyaku/releases/download/v<version>/Youyaku.dmg`
- サイトのダウンロードボタン … `https://github.com/hinoshiba/youyaku/releases/latest/download/Youyaku.dmg`

アセット名を版に依らず `Youyaku.dmg` で固定し、タグ(`v<version>`)で版を分けているため、
サイト側は版に依らない `latest` リンクを、appcast は版を固定したリンクを、同じ 1 ファイルに対して使える。

> **前提**: GitHub Releases のアセットは、**リポジトリが公開されている**ときだけ匿名で
> ダウンロードできる。非公開のままリリースすると、サイトのダウンロードボタンも
> アプリ内アップデートも 404 になる(`Scripts/publish-release.sh` はこれを検出して停止する)。

## 配布フロー

手順の詳細と実行順の理由は **[docs/RELEASE.md](../../docs/RELEASE.md)**「リリースごとの手順」を参照。
要点は「**先に Releases へ DMG を上げ、あとから appcast.xml を push する**」こと
(逆順にすると、更新は見えるのに DMG が 404 という時間帯ができる)。

> この `README.md` はデプロイ用ワークフローがアーティファクトから除外するため、
> `https://<site>/download/README.md` としては公開されない。

## 注意

- **未公証の DMG に対する appcast は生成されない**(macOS 15 以降で起動できず配布不可のため)。
  `YOUYAKU_NOTARY_PROFILE` を設定して公証を通すこと。
- `appcast.xml` の EdDSA 署名は **DMG のバイト列に紐づく**。公開済みの DMG を差し替えると、
  既に配ったフィードが検証に失敗する。差し替えず、版を上げて出し直すこと。
