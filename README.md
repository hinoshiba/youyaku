# Youyaku(ようやく)— AIのための音声入力

**どのアプリでも `⌥Space` を押して話すだけ。ローカルLLMがあなたの言葉を、AIに伝わる指示文に整えます。**

Youyaku は、AIアシスタント(Claude、ChatGPT、Copilot など)への命令入力を音声で行うための macOS メニューバーアプリです。**追加インストール一切不要** — 推論エンジン(llama.cpp)を内蔵し、モデルはアプリ内から直接ダウンロード。音声認識も文章整形も既定設定では Mac の中で完結し、音声やテキストが外部に送信されることはありません(外部通信の全経路は後述の[プライバシー](#プライバシー)を参照)。

## 特徴

- **完全スタンドアロン** — llama.cpp を内蔵。モデル(GGUF)は Hugging Face からアプリ内でワンクリックDL・削除・切替
- **グローバルショートカット** — どのアプリの上でも `⌥Space`(変更可)で Spotlight 風の入力パネルを呼び出し
- **オンデバイス音声認識** — macOS 内蔵エンジンによる日本語認識。句読点自動挿入・専門用語辞書対応
- **ローカルLLMによる整形** — フィラー(えー、あの…)や言い直しを除去し、構造化された AI 命令文に再構成
- **3つのモード** — そのまま / 整文 / AI命令化 をワンタップで切替
- **前提プリセット** — 「使用技術は TypeScript」「出力は箇条書き」などの背景情報をプロジェクトごとに登録・切替
- **日本語重視のモデルカタログ** — Qwen3 / ELYZA JP(日本語特化・Built with Meta Llama 3)/ Gemma 3 / Llama 3.2(Built with Llama)など、検証済みモデルを厳選。各モデルは配布元のライセンスに従って利用のこと
- **英語対応** — 設定の「表示言語」でUI全体を日本語⇄Englishに切替。整形プロンプトは認識言語に自動追従(英語で話せば英語の指示文が出力される)
- **長文ディクテーション対応** — macOSの音声認識には1タスクあたり約1分の連続認識制限があるため、上限に達する前に発話の切れ目で認識タスクを自動で継ぎ直し、途切れずに長く話せる。認識が無音で止まった場合やオーディオデバイス変更時も自動復旧。万一中断された場合は確定画面から `⌘↩` で続きから再開できる
- **Ollama 連携(任意)** — すでに Ollama をお使いなら、設定でエンジンを切り替えてそのまま利用可能
- **カーソル位置へ自動貼り付け** — 確定と同時に最前面アプリへ入力(クリップボード復元オプション付き)
- **履歴** — 過去の入力を検索・再コピー

## 必要環境

- macOS 14 (Sonoma) 以降 / Intel 対応(推論は Metal GPU が使える Apple Silicon 推奨)
- メモリ 8GB 以上(4B モデル使用時。ELYZA 8B は 16GB 推奨)

## ダウンロード

- **Mac 版**: [youyaku.hinoshiba.com](https://youyaku.hinoshiba.com/) から公証済み DMG をダウンロード(Developer ID 署名 + 公証済み)。
- **iPhone / iPad 版**: App Store で公開予定。

ソースからビルドする場合は以下を参照してください。

## ビルド

```bash
./build.sh          # 依存取得 → ビルド → dist/Youyaku.app 生成まで自動(開発用)
open dist/Youyaku.app

./build.sh --dist   # 配布用: Developer ID 署名 + 公証 + DMG 生成(要 Apple Developer Program)
```

Xcode 不要(Command Line Tools のみでビルド可能)。配布(署名・公証・DMG)の手順は、メンテナ向けに [docs/RELEASE.md](docs/RELEASE.md) にまとめています。

`build.sh` は最初に `Scripts/fetch-vendor.sh` を呼び、llama.cpp の公式ビルド済み xcframework(ggml-org, b9859, 約 242MB)と、アプリ内アップデート用の Sparkle(sparkle-project, 2.9.4, 約 11MB)を `Vendor/` にダウンロードします。どちらもリリースタグと SHA-256 でピン留めしており、再取得可能なバイナリのため **git にはコミットしていません**(`Vendor/` と `dist/` は `.gitignore` 済み)。クローン直後は `./Scripts/fetch-vendor.sh` 単体でも取得できます。

## 初回セットアップ

1. `dist/Youyaku.app` を起動(必要なら `/Applications` へコピー)
2. ホーム画面のチェックリストに従って **マイク / 音声認識** を許可
3. 自動貼り付けを使う場合は **アクセシビリティ** を許可(任意)
4. 「モデル」画面のカタログからモデルをダウンロード(推奨: Qwen3 4B / お試し: Qwen3 0.6B)

## 使い方

| 操作 | キー |
|---|---|
| 入力パネルを開く / 録音停止 | `⌥Space`(変更可) |
| 停止して整形 | `↩` |
| 整形結果を貼り付け | `↩` |
| 続きから再開(それまでの内容を保持して録音再開) | `⌘↩` |
| コピーのみ | `⌘C` |
| 整形をやり直す | `⌘R` |
| キャンセル / 閉じる | `esc` |

## アーキテクチャ

```
Sources/Youyaku/
├── YouyakuApp.swift          # エントリポイント(MenuBarExtra)
├── AppState.swift        # セッション状態機械(録音→整形→確定)
├── Models/               # 設定・履歴の永続化(Settings.swift / HistoryStore.swift)
├── Speech/               # AVAudioEngine + SFSpeechRecognizer(オンデバイス)
├── LLM/
│   ├── LlamaEngine.swift    # 内蔵 llama.cpp エンジン(Metal 推論・チャットテンプレート)
│   ├── ModelStore.swift     # GGUF ダウンロード管理(進捗・検証・容量チェック)
│   ├── BuiltinCatalog.swift # 検証済みモデルカタログ(HF 直リンク)
│   ├── OllamaClient.swift   # Ollama バックエンド(任意)
│   └── Refiner.swift        # 整形プロンプト構築
├── Hotkey/               # Carbon グローバルホットキー
├── HUD/                  # 非アクティブ化フローティングパネル(NSPanel + SwiftUI)
├── UI/                   # メインウィンドウ(ホーム/モデル/履歴/設定)
└── Support/              # 貼り付け・権限・テーマ・スナップショット・セルフテスト
```

- 設定と履歴は `~/Library/Application Support/Youyaku/` に JSON で保存、モデルは同 `Models/` に GGUF で保存
- `Youyaku --snapshot <dir>` で全画面をオフスクリーンレンダリング(UI 検証用)
- `Youyaku --selftest <gguf> [プロンプト]` で内蔵エンジンの推論を CLI から検証

## プライバシー

- 音声認識は既定でデバイス上で実行(「オンデバイス認識を優先」ON)。OFF にした場合のみ Apple のサーバー認識が使われ、音声が Apple に送信される
- LLM 推論はアプリ内蔵エンジン(llama.cpp + Metal)でローカル実行
- 外部通信の全経路は以下のみ。テレメトリ・分析・広告 SDK は一切なし
  - モデルのダウンロード時: Hugging Face へ接続(IP アドレス・User-Agent 等が同社に送信される)
  - Ollama 連携(任意設定): 有効にすると設定先ホストへ整形対象テキストを送信(既定はローカル 127.0.0.1。外部ホストも指定可)
  - 更新チェック(macOS): youyaku.hinoshiba.com から更新情報(appcast.xml)のみを1日1回取得(設定でオフ可)
  - アプリ内アップデート(macOS): 利用者が「アップデート」を選んだときだけ GitHub Releases から DMG を取得して適用(Sparkle。同意なしに更新は入らない)
- 履歴・設定・モデルはすべて `~/Library/Application Support/Youyaku/` に保存され、ユーザーが削除可能
- 詳細は配布サイトのプライバシーポリシー([http_dist/privacy.html](http_dist/privacy.html))を参照

## iOS 版

iPhone / iPad 版のソースは [`ios/`](ios/) にあります。コアロジック(設定・履歴・LLM エンジン・整形・モデル管理・音声認識)は macOS 版と共有し、UI のみ iOS 向けに実装しています。ビルド方法は [ios/README.md](ios/README.md) を参照。

## 貢献

Issue・Pull Request を歓迎します。まず [CONTRIBUTING.md](CONTRIBUTING.md) をご覧ください。

- バグ報告・機能リクエストは Issue テンプレートに沿ってお願いします。
- セキュリティ上の脆弱性は公開 Issue に書かず、[SECURITY.md](SECURITY.md) の手順で非公開に報告してください。
- 参加者は [行動規範](CODE_OF_CONDUCT.md) に従ってください。

リリース(署名・公証・App Store 提出)の手順は、メンテナ向けに [docs/RELEASE.md](docs/RELEASE.md) / [docs/RELEASE-iOS.md](docs/RELEASE-iOS.md) にまとめています。

## ライセンス

[MIT License](LICENSE) © 2026 hinoshiba

- 同梱する推論エンジン [llama.cpp](https://github.com/ggml-org/llama.cpp)(MIT)ほか、第三者ライセンスは [THIRD_PARTY_LICENSES.txt](THIRD_PARTY_LICENSES.txt) を参照。
- モデル(GGUF)は各配布元のライセンスに従って利用してください(重みはアプリに同梱せず、利用者がダウンロードします)。
