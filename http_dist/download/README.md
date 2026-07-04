# http_dist/download/

Mac 版 Youyaku の **HP 直販ダウンロード** 用ディレクトリ。

`build.sh --dist`(公証あり)を実行すると、`Scripts/make-dmg.sh` が公証・staple 済みの
DMG をここへ **安定名で** 配置する:

- `Youyaku.dmg` … 最新版の DMG。サイトの `/download/Youyaku.dmg` から配信される。
- `version.txt` … 配布中のバージョン文字列(例: `1.0.0`)。トップページが読み取って表示する。

どちらも生成物のため git 管理外(`.gitignore` 済み)。`wrangler` は `http_dist` を
ローカルディスクから配信するので、`build.sh --dist` の後に `wrangler deploy` すれば公開される。

## 注意

- **未公証の DMG はここに置かれない**(macOS 15 以降で起動できず配布不可のため)。
  公開用に配置するには `YOUYAKU_NOTARY_PROFILE` を設定して公証を通すこと。詳細は `docs/RELEASE.md`。
- Cloudflare Workers の静的アセットは **1 ファイル 25 MiB** が上限。DMG がこれを超える場合は
  Cloudflare では配信できないため、GitHub Releases 等の外部ホスティングへ切り替え、
  `http_dist/index.html` のダウンロードリンクをその URL に向けること
  (`make-dmg.sh` はサイズ超過時に警告を出す)。
