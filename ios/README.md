# Youyaku for iPhone / iPad

macOS 版 Youyaku の iOS 版。音声を話すとローカルLLMが整った指示文に変換します。**音声認識もLLM推論もすべて端末内**で完結し、音声や文章が外部に送信されることはありません。外部への通信はモデルのダウンロード時(Hugging Face)のみです。

macOS 版との違いは「出力方法」です。iOS はサンドボックスの制約で他アプリへの自動貼り付けができないため、**アプリを開く → 話す → 整形 → コピー / 共有** という流れになります。

## macOS 版とのコード共有

プラットフォーム非依存のコア(設定・履歴・LLMエンジン・整形ロジック・モデル管理・音声認識・波形・ローカライズ)は macOS 版の `../Sources/Youyaku/` のファイルをそのまま共有し、`#if os(iOS)` で差分だけを吸収しています。UI とアプリ状態(`ios/Youyaku/`)は iOS 向けに書き下ろしています。

## セットアップ(初回のみ・要管理者パスワード)

Xcode のライセンス同意とツールチェーン選択が必要です:

```bash
sudo xcodebuild -license accept
sudo xcode-select -s /Applications/Xcode.app
```

## ビルド

```bash
cd ios
./build.sh "iPhone 16"          # シミュレータ向けにビルド
./build.sh "iPhone 16" run      # ビルド後にシミュレータで起動
```

`project.yml` がプロジェクト設定の正本です。Xcode Cloud が常に product と shared scheme を検出できるよう、生成した `Youyaku.xcodeproj` もリポジトリに含めます。`project.yml` を変更したら `xcodegen generate` を実行し、両方を同じ変更に含めてください。`build.sh` はローカルビルド前にプロジェクトを再生成します。

Xcode で開く場合:

```bash
cd ios && xcodegen generate && open Youyaku.xcodeproj
```

## Xcode Cloud

App Store向けRelease archiveはXcode Cloudで作成します。`vX.Y.Z`タグをpushすると、`ios/ci_scripts/`が依存取得・タグと`project.yml`および追跡済みXcode projectのversion照合・Cloud build numberの設定を行います。Workflowの設定値と初回接続手順は[App Store提出手順](../docs/RELEASE-iOS.md)を参照してください。

## 必要環境

- iOS 17 以降(iPhone / iPad)
- Xcode 16 以降
- メモリに注意: 4B モデル(約2.5GB)は多くの iPhone で強制終了され得ます。カタログでは端末RAMに対して大きすぎるモデル(RAMの45%超)はダウンロード不可、ややきついモデル(RAMの30〜45%)には不安定警告を表示します。iPhone は Qwen3 0.6B / 1.7B、メモリの大きい iPad Pro なら 4B も、が目安です。

## 構成

```
ios/
├── project.yml            # xcodegen のプロジェクト定義(真の設定)
├── build.sh               # 生成 → ビルド → 任意で起動
└── Youyaku/
    ├── YouyakuApp.swift        # @main / TabView(音声入力・モデル・履歴・設定)
    ├── AppModel.swift      # セッション状態機械(録音→整形→結果、iOS向け)
    ├── Info.plist          # マイク / 音声認識の使用目的
    ├── Views/              # DictateView / ModelsView / HistoryView / SettingsView
    └── Support/            # 権限・クリップボード・共有シート・触覚
```
