# Youyaku iOS 版 App Store 提出 手順書

iOS 版（`ios/`）を App Store で公開するための手順。macOS 版の直販手順は [RELEASE.md](RELEASE.md) を参照。

- **Bundle ID**: `com.hinoshiba.youyaku`（macOS 版と統一。iOS/macOS で同一 ID）
- **配布**: App Store（macOS 版は直販 DMG。iOS だけがストア配布）
- **対応端末**: iPhone + iPad（`TARGETED_DEVICE_FAMILY: "1,2"`）
- **最低 OS**: iOS 17.0
- **プロジェクト生成**: [XcodeGen](https://github.com/yonsm/XcodeGen)（`ios/project.yml` → `Youyaku.xcodeproj`）

> `ios/build.sh` は**シミュレータ動作確認用**（Debug・署名なし）。App Store 提出は本書の手順で行う。

---

## 0. 前提条件（初回のみ）

### ツール

```bash
# XcodeGen（未導入なら）
brew install xcodegen
# Xcode 本体（App Store 版 Xcode 15.3 以降を推奨）と Command Line Tools
xcode-select -p                       # /Applications/Xcode.app/Contents/Developer になっていること
sudo xcodebuild -license accept
```

### Apple Developer / App Store Connect

1. **Apple Developer Program**（$99/年）に登録済みであること（macOS 版と共通）。
2. **Apple Distribution 証明書**をキーチェーンに用意する（Xcode の Settings → Accounts →
   Manage Certificates → ＋ → Apple Distribution でも作成可）。
3. **App ID を登録**（Developer サイト → Certificates, IDs & Profiles → Identifiers → ＋ → App IDs）:
   - Bundle ID: **`com.hinoshiba.youyaku`**（Explicit）
   - Capabilities で **Extended Virtual Addressing** と **Increased Memory Limit** を有効化する
     （本アプリは大きな LLM モデルをロードするため。`ios/Youyaku/Youyaku.entitlements` の
     `com.apple.developer.kernel.increased-memory-limit` に対応）。
4. **App Store Connect にアプリを新規作成**（App Store Connect → マイ App → ＋ → 新規 App）:
   - プラットフォーム: iOS
   - Bundle ID: `com.hinoshiba.youyaku`
   - SKU: 任意（例 `youyaku-ios`）
   - 名前: `Youyaku`

### 署名の Team ID を設定

`ios/project.yml` の `DEVELOPMENT_TEAM` が空なので、自分の Team ID を設定する（Developer サイト →
Membership の Team ID・10 桁）。**`project.yml` を直接編集する**（生成される `.xcodeproj` は毎回上書きされるため）:

```yaml
# ios/project.yml
settings:
  base:
    DEVELOPMENT_TEAM: "XXXXXXXXXX"   # ← 自分の Team ID
```

> Team ID をリポジトリに commit したくない場合は、`xcodebuild` の引数
> `DEVELOPMENT_TEAM=XXXXXXXXXX` で毎回渡してもよい（下の手順はこの方式）。

### App Store Connect API キー（CLI アップロード用）

コマンドラインからアップロードする場合に必要（Xcode GUI を使うなら不要）。
App Store Connect → Users and Access → Integrations → App Store Connect API → ＋ で
**キーを作成**し、`AuthKey_XXXXXXXXXX.p8` をダウンロードする（再ダウンロード不可・**commit 厳禁**、
`.gitignore` 済み）。あわせて **Key ID** と **Issuer ID** を控える。

---

## 1. バージョンを上げる

```bash
./Scripts/bump-version.sh X.Y.Z
```

`ios/project.yml` の `MARKETING_VERSION`（表示バージョン）と `CURRENT_PROJECT_VERSION`（ビルド番号）が
更新される。**ビルド番号は App Store Connect 内で一意**である必要があるため、同じ版を再アップロードする
場合も `CURRENT_PROJECT_VERSION` を増やす（`bump-version.sh` はビルド番号もインクリメントする）。

> Info.plist の版数は `project.yml` の変数（`$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)`）を
> 参照するため、`xcodegen generate` のたびに正しい値で再生成される。

---

## 2. アーカイブとアップロード

### 方法 A: Xcode GUI（推奨・初回はこちらが確実）

```bash
cd ios
xcodegen generate
open Youyaku.xcodeproj
```

1. スキーム `Youyaku`、実行先を **Any iOS Device (arm64)** にする。
2. **Product → Archive**。
3. Organizer が開いたら **Distribute App → App Store Connect → Upload** を選び、案内に従う
   （自動署名なら証明書・プロファイルは Xcode が用意する）。

### 方法 B: コマンドライン（CI・再現性重視）

```bash
cd ios
xcodegen generate

# 1) アーカイブ（実機向け Release）
xcodebuild \
  -project Youyaku.xcodeproj \
  -scheme Youyaku \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/Youyaku.xcarchive \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=XXXXXXXXXX \
  archive

# 2) エクスポート & アップロード
cp ExportOptions.plist.example ExportOptions.plist    # 初回だけ。teamID を自分の値に編集
xcodebuild -exportArchive \
  -archivePath build/Youyaku.xcarchive \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath build/export \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$HOME/keys/AuthKey_XXXXXXXXXX.p8" \
  -authenticationKeyID XXXXXXXXXX \
  -authenticationKeyIssuerID xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

`ExportOptions.plist` の `destination` が `upload` なら、この 2) の完了時に App Store Connect へ
アップロードされる。`export` にした場合は `build/export/Youyaku.ipa` が出るので、
**Transporter**アプリ（Mac App Store で無料）または以下でアップロードする:

```bash
xcrun altool --upload-app -f build/export/Youyaku.ipa -t ios \
  --apiKey XXXXXXXXXX --apiIssuer xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

アップロード後、App Store Connect で処理が終わると（数分〜十数分）、対象ビルドが選択可能になる。

---

## 3. App Store Connect でのメタデータ設定

アプリのバージョンページで設定する（[提出前チェックリスト](RELEASE.md#ios-app-store-提出チェックリスト)も参照）:

- **スクリーンショット**: iPhone（6.9" と 6.5" 等）と **iPad（13"）の両方**が必須
  （`TARGETED_DEVICE_FAMILY: "1,2"` のため iPad を落とすと審査で止まる）。
  `Youyaku --snapshot` は macOS 用。iOS はシミュレータで撮る:
  ```bash
  xcrun simctl boot "iPhone 16 Pro Max"
  # アプリを起動して各画面を表示し
  xcrun simctl io booted screenshot iphone-home.png
  ```
- **プロモーションテキスト / 概要 / キーワード**: 日本語（＋任意で英語ローカライズ）。
  「完全ローカル」「オンデバイス」を訴求する場合は、macOS 版の設定次第でサーバー認識になり得る点
  （iOS は常に端末内）と齟齬がないようにする。
- **サポート URL**: `https://youyaku.hinoshiba.com/privacy.html#contact`
- **マーケティング URL**（任意）: `https://youyaku.hinoshiba.com/`
- **プライバシーポリシー URL**: `https://youyaku.hinoshiba.com/privacy.html`
- **App のプライバシー（App Privacy）**: 「**データを収集していません（Data Not Collected）**」で申告。
  - 音声認識・整形はオンデバイス、履歴・設定は端末内保存で、開発者はデータを受け取らない。
  - モデル DL は Hugging Face への通信だが、開発者がユーザーデータを収集するわけではない。
  - `ios/Youyaku/PrivacyInfo.xcprivacy`（Privacy Manifest）は同梱済み。
- **価格**: 無料。
- **年齢レーティング**: 新しいレーティング質問票に回答（該当コンテンツなしの想定）。
  AI による文章生成機能について問われた場合は、「ユーザー自身の発話を整形するもので、
  自由生成のチャットボットではない」旨を踏まえて回答する。
- **輸出コンプライアンス**: `ITSAppUsesNonExemptEncryption = false`（設定済み）。
  HTTPS 等の OS 標準暗号のみで独自暗号を含まないため、追加書類は不要。
- **EU DSA トレーダーステータス**: 個人開発者として trader / non-trader を申告
  （trader の場合は連絡先住所等の公開が必要）。

---

## 4. Review Notes（審査メモ）と提出

「App Review Information」の Notes に、モデル DL の性質を先回りで説明しておくとリジェクトを避けやすい:

> This app downloads GGUF files, which are **model weight data — not executable code**.
> Inference runs entirely within the bundled llama.cpp engine, and downloading a model does not
> change the app's features or behavior (this is not the download of executable code under
> guideline 2.5.2). All speech recognition and text refinement run **on-device**; audio is never
> sent to a server.
>
> To test quickly: open the Models tab and download **"Qwen3 0.6B"** (the smallest model), then
> dictate on the first tab. No account or login is required.

設定が済んだら **「レビューに提出（Submit for Review）」**。

---

## 5. よくあるリジェクト理由と対策

| 事象 | 対策 |
|---|---|
| **2.1 パフォーマンス**: モデル DL 中にアプリが落ちる/固まる | 端末 RAM に対して大きすぎるモデルは DL 不可にしてある（`ModelsView` の RAM フィルタ）。審査は小さい 0.6B で試すよう Notes に明記。 |
| **2.5.2 実行コードの DL** と誤解される | 上記 Review Notes で「重みデータであって実行コードではない」と説明。 |
| **5.1.1 プライバシー**: ポリシー URL に到達できない | 審査前に `youyaku.hinoshiba.com`（GitHub Pages）が公開・到達可能で、`privacy.html` / `terms.html` が開けることを確認。 |
| **2.3 誇大表現**: 「完全オンデバイス」の断定 | iOS は常時オンデバイスなので断定 OK。サイト/文言は既定設定の限定付きで統一済み。 |
| マイク/音声認識の usage description 不足 | `NSMicrophoneUsageDescription` / `NSSpeechRecognitionUsageDescription` を設定済み（`project.yml`）。 |

---

## 6. 承認後

- **手動リリース**にしておくと、承認後に自分のタイミングで公開できる。
- 公開後、サイトの「近日 App Store へ」表示を実際の App Store リンクに差し替える
  （`http_dist/index.html` の該当箇所）。この変更は `main` への push で GitHub Actions が
  自動デプロイする（[RELEASE.md](RELEASE.md#サイト公開ダウンロードリンク) 参照）。

---

## 参考リンク

- App Store Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- App Privacy Details: https://developer.apple.com/app-store/app-privacy-details/
- Uploading apps (Xcode / altool / Transporter): https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases
