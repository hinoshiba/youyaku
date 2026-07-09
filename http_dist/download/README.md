# http_dist/download/

Mac 版 Youyaku の **HP 直販ダウンロード** 用ディレクトリ。

`build.sh --dist`(公証あり)を実行すると、`Scripts/make-dmg.sh` が公証・staple 済みの
DMG をここへ **安定名で** 配置する:

- `Youyaku.dmg` … 最新版の DMG。サイトの `/download/Youyaku.dmg` から配信される。
- `version.txt` … 配布中のバージョン文字列(例: `1.0.0`)。トップページとアプリの更新確認が読み取る。

## 配布フロー(git 管理下 → GitHub Pages)

**この 2 ファイルを git に commit** して配布する(詳細は `docs/RELEASE.md`)。

1. 証明書のある Mac で `./build.sh --dist`(要 `YOUYAKU_NOTARY_PROFILE`)を実行 → ここに DMG と version.txt が置かれる。
2. `git add http_dist/download/Youyaku.dmg http_dist/download/version.txt && git commit && git push`
3. `main` への push で **GitHub Actions**(`.github/workflows/deploy-pages.yml`)が
   `http_dist` を GitHub Pages へ公開し、`https://youyaku.hinoshiba.com/download/Youyaku.dmg` で配信される。

> この `README.md` はデプロイ用ワークフローがアーティファクトから除外するため、
> `https://<site>/download/README.md` としては公開されない。

## 注意

- **未公証の DMG はここに置かれない**(macOS 15 以降で起動できず配布不可のため)。
  公開用に配置するには `YOUYAKU_NOTARY_PROFILE` を設定して公証を通すこと。詳細は `docs/RELEASE.md`。
- GitHub Pages は **1 ファイル 100 MB・サイト全体 1 GB** がソフト上限。DMG がこれを超える場合は
  DMG を小さくするか、外部の公開ストレージへ切り替えて `http_dist/index.html` のダウンロードリンクを
  そこへ向けること(`make-dmg.sh` はサイズ超過時にエラーで停止する)。
