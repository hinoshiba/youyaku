# コントリビューションガイド / Contributing

Youyaku に関心をお寄せいただきありがとうございます。個人開発のプロジェクトですが、Issue・Pull Request を歓迎します。
まずはこのガイドに目を通してください。日本語・英語のどちらでも構いません（Japanese or English are both welcome）。

## プロジェクトの方針

Youyaku は「**音声認識も LLM 推論も既定でオンデバイス完結**・**日本語重視**の音声入力」を軸にしています。
この方向性に沿った提案・修正は採り入れやすいです。大きな変更や新機能は、着手前に Issue で相談してもらえると調整がスムーズです。

## Issue のルール

### 投稿前に

- **既存の Issue（Open / Closed）を検索**し、重複がないか確認してください。
- **1 Issue につき 1 トピック**にしてください（複数の不具合・要望をまとめない）。
- テンプレート（バグ報告 / 機能リクエスト）に沿って記入してください。空の Issue は無効化しています。

### バグ報告に含めてほしいこと

- 再現手順、期待する挙動、実際の挙動
- 環境: OS とバージョン（macOS / iOS）、Youyaku のバージョン、端末・チップ、使用モデル・推論エンジン
- 可能ならログ・スクリーンショット（**個人情報や機微な発話内容は必ず伏せてください**）

### セキュリティ脆弱性

**脆弱性は公開 Issue / PR / Discussions に書かないでください。** [SECURITY.md](SECURITY.md) の手順で非公開に報告してください。

## Pull Request の流れ

1. **フォーク**して作業用ブランチを作成（例: `fix/...`, `feature/...`）。
2. **ビルドが通ることを確認**する:
   - macOS: `./build.sh`（詳細は [README](README.md#ビルド)）
   - iOS: `cd ios && ./build.sh "iPhone 16" run`（[ios/README.md](ios/README.md)）
3. **変更は 1 テーマに絞る**。無関係な整形・リネームを混ぜない。
4. **既存のコードスタイル・命名・コメントの粒度に合わせる**（周囲のコードに読み味を合わせる）。
5. PR テンプレートに沿って説明・動作確認・関連 Issue を記入して提出。

コミットメッセージ・PR は日本語で構いません（本リポジトリの既存コミットも日本語です）。

## ビルド環境

- macOS 14 (Sonoma) 以降。ローカルの Xcode 16 以降とXcodeGen 2.45.4を使用します。
- `./build.sh` が `Scripts/fetch-vendor.sh` を呼び、llama.cpp の公式ビルド済み xcframework を `Vendor/` に取得します（タグ + SHA-256 でピン留め）。

## メンテナ向けドキュメントについて

`docs/RELEASE.md` / `docs/RELEASE-iOS.md` は**リリース担当（メンテナ）向け**の署名・公証・App Store 提出手順です。
一般のコントリビューションには不要ですが、リリースフローに影響する変更をする場合は併せて更新してください。

## ライセンス

このリポジトリへの貢献は、プロジェクトと同じ [MIT ライセンス](LICENSE) の下で提供されるものとします。

## 行動規範

参加者は [行動規範（CODE_OF_CONDUCT.md）](CODE_OF_CONDUCT.md) に従ってください。

## Repository workflow / リポジトリ運用

Start from an up-to-date `main` (`git switch main` then `git pull --ff-only`).
Use local Xcode for development and release preparation. Pull-request checks
use unsigned builds (or an ad-hoc signature for local bundle checks), with no
maintainer Apple Account, signing identity, or private credentials.

Commit and push completed changes on a focused branch, then open a pull request
using the shared template. For repository maintenance use
`improve/repository-<message>`. Check website changes in Japanese and English
at mobile, tablet, and desktop widths.

Use `support@hinoshiba.com` for project contact information. Before publishing,
check author/committer metadata and changed files for personal contact details,
secrets, and generated artifacts. Preserve legally required third-party notices.
