# http_dist/download/

Mac 版 Youyaku の **HP 直販ダウンロード** 用ディレクトリ。

`build.sh --dist`(公証あり)を実行すると、`Scripts/make-dmg.sh` が公証・staple 済みの
DMG をここへ **安定名で** 配置する:

- `Youyaku.dmg` … 最新版の DMG。サイトの `/download/Youyaku.dmg` から配信される。
- `version.txt` … 配布中のバージョン文字列(例: `1.0.0`)。トップページとアプリの更新確認が読み取る。

## 配布フロー(git 管理下)

本リポジトリは **非公開**のため GitHub Releases は使わず、**この 2 ファイルを git に commit** して配布する。

1. 証明書のある Mac で `./build.sh --dist`(要 `YOUYAKU_NOTARY_PROFILE`)を実行 → ここに DMG と version.txt が置かれる。
2. `git add http_dist/download/Youyaku.dmg http_dist/download/version.txt && git commit && git push`
3. `main` への push で **GitHub Actions**(`.github/workflows/deploy-site.yml`)が
   `http_dist` を Cloudflare Workers へ deploy し、`https://youyaku.hinoshiba.com/download/Youyaku.dmg` で公開される。

> このディレクトリの `README.md` は `http_dist/.assetsignore` によって配信対象から除外される
> (`https://<site>/download/README.md` としては公開されない)。

## 注意

- **未公証の DMG はここに置かれない**(macOS 15 以降で起動できず配布不可のため)。
  公開用に配置するには `YOUYAKU_NOTARY_PROFILE` を設定して公証を通すこと。詳細は `docs/RELEASE.md`。
- Cloudflare Workers の静的アセットは **1 ファイル 25 MiB** が上限。DMG がこれを超える場合は
  Cloudflare では配信できないため、GitHub 等の外部ホスティングへ切り替え、
  `http_dist/index.html` のダウンロードリンクをその URL に向けること
  (`make-dmg.sh` はサイズ超過時にエラーで停止する)。
- DMG はバイナリのため commit するとリポジトリ履歴が肥大化する。同じファイル名で上書き
  commit すれば最新ツリーは 1 つに保たれる(過去版は履歴に残る)。
