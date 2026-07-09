# Youyaku 配布・署名・公証 手順書(macOS)

> **メンテナ向けドキュメント。** リリース担当者が macOS 版を Developer ID 直販で配布するための手順です。
> アプリのビルドや開発だけが目的なら [README](../README.md) と [CONTRIBUTING](../CONTRIBUTING.md) で十分です。

macOS 版 Youyaku を **Developer ID 直販（App Store 外）** で配布するための手順書。
`build.sh --dist` を実行すると、**署名 → DMG 生成 → 公証(notarization) → staple** までが自動で走る。

## なぜ Mac App Store ではなく直販なのか

Youyaku の中核機能「`⌥Space` でどこでも呼び出し → 最前面の他アプリへ自動貼り付け」は、
グローバルホットキー（Carbon `RegisterEventHotKey`）と他アプリへのキー合成（`CGEvent` + アクセシビリティ）に依存する。
これらは **Mac App Store 必須の App Sandbox では禁止** されているため、MacWhisper / Superwhisper / Raycast / Alfred 等と同様に
**Developer ID 署名 + 公証による直販**（自サイト DMG / Homebrew Cask）で配布する。

- App Sandbox は付けない（`Youyaku.entitlements` に sandbox キーなし）。
- 配布物はユーザーのダウンロード用に必ず **公証 + staple** すること（未公証だと macOS 15 以降で起動がほぼ不可）。

---

## 前提条件（初回のみ）

### 1. Apple Developer Program に登録（$99 / 年）

- iOS の App Store 提出だけでなく、**Mac 直販の公証(notarytool)にも必須**。1 メンバーシップで両方をカバーする。
- 失効（未更新）しても、**すでに公証して配布した DMG / アプリは無期限に起動し続ける**（タイムスタンプ + 公証チケットが有効なため）。ただし新しい版の公証はできなくなる。

### 2. Developer ID Application 証明書をキーチェーンに用意

Xcode か Apple Developer サイトから **「Developer ID Application」** 証明書を作成し、ログインキーチェーンに取り込む。

```bash
# 取り込めているか確認(1件だけ表示されるのが理想)
security find-identity -v -p codesigning | grep 'Developer ID Application'
```

> 複数の Developer ID Application 証明書がある場合、`build.sh` は取り違えを避けるためエラーで停止する。
> その場合は環境変数 `YOUYAKU_DIST_IDENTITY` で使う証明書を明示する（後述）。

### 3. 公証(notarytool)の認証情報を保存

App 用パスワードを [appleid.apple.com](https://appleid.apple.com) で発行し、キーチェーンプロファイルとして一度だけ保存する。

```bash
xcrun notarytool store-credentials youyaku-notary \
    --apple-id  <Apple ID(メール)> \
    --team-id   <10桁のTEAMID> \
    --password  <App用パスワード>
```

---

## ビルド

### 0. バージョンを上げる（リリースごとに最初に行う）

```bash
./Scripts/bump-version.sh 1.1.0   # 例: 1.1.0 に上げる
```

- ルート `Info.plist` の `CFBundleShortVersionString` を書き換え、`CFBundleVersion` を +1 する。
- `ios/project.yml` の `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` も同じ値に同期する（macOS / iOS で版数がズレるのを防ぐ）。
- DMG のファイル名やサイトの `version.txt`、アプリ内の更新チェックはこの値を参照するため、**ビルド前に必ず実行**する。

### 開発ビルド（手元での動作確認用）

```bash
./build.sh
```

Developer ID 証明書は不要。ローカル自己署名証明書（`./Scripts/setup-signing.sh` で作成）があればそれを使い、
なければ ad-hoc 署名になる。公証・DMG は行わない。

### 配布ビルド（署名 + DMG + 公証 + staple）

```bash
export YOUYAKU_NOTARY_PROFILE=youyaku-notary   # 手順3で保存したプロファイル名
./build.sh --dist
```

成果物: `dist/Youyaku-<バージョン>.dmg`（公証・staple 済み）。

配布ビルドは **universal（arm64 + x86_64）** でビルドされる（`swift build -c release --arch arm64 --arch x86_64`）。
Apple Silicon / Intel の両方の Mac で動く DMG にするためで、`build.sh` は `lipo -archs` で
両アーキテクチャが含まれることを検証し、片方しか無ければエラーで停止する。
（開発ビルド `./build.sh` はホストのアーキテクチャのみで高速にビルドする。）

> `YOUYAKU_NOTARY_PROFILE` を設定せずに `--dist` を実行すると、署名と DMG 生成までは行い、**公証はスキップ**される
> （手元テスト用。この DMG は配布しないこと）。

---

## パイプラインが行うこと

`build.sh --dist` → `Scripts/make-dmg.sh` の流れ:

1. **Swift ビルド**（universal: `swift build -c release --arch arm64 --arch x86_64`）してアプリバンドルを組み立て、
   `lipo -archs` で両アーキテクチャを検証し、`llama.framework` を埋め込む。
2. **inside-out 署名**（埋め込みフレームワーク → アプリ本体の順）。いずれも:
   - `--options runtime`（Hardened Runtime。公証の必須要件）
   - `--timestamp`（セキュアタイムスタンプ。公証の必須要件・証明書失効後も検証可）
   - アプリ本体に `--entitlements Youyaku.entitlements` を適用
3. **署名検証** + **rpath 検証**（`@executable_path/../Frameworks` が無いと起動時に dyld で落ちるため）。
4. **アプリ本体を公証 + staple**（`ditto` で zip 化 → `notarytool submit --wait` → `stapler staple`）。
   DMG 封入前にアプリ自身へチケットを焼き込むことで、**DMG から取り出した後もオフラインで Gatekeeper を通せる**。
5. **DMG 生成**（staple 済みアプリ + `/Applications` シンボリックリンク）。
6. **DMG 署名**（Developer ID + タイムスタンプ）。
7. **DMG を公証 + staple**、`stapler validate` で検証。
8. **HP 配布用に配置**：公証済み DMG を `http_dist/download/Youyaku.dmg`（安定名）にコピーし、`http_dist/download/version.txt` にバージョンを書き出す。トップページのダウンロードボタン（`/download/Youyaku.dmg`）がこれを配信する。
   - 未公証（`YOUYAKU_NOTARY_PROFILE` 未設定）の場合はこの配置を**スキップ**する（配布不可の DMG を公開しないため）。
   - `http_dist/download/*.dmg` と `version.txt` は **git 管理下**（手動 commit）。commit → push で GitHub Actions が GitHub Pages へ公開する（後述「サイト公開」）。

### エンタイトルメント（`Youyaku.entitlements`）

- `com.apple.security.device.audio-input` — マイク録音（AVAudioEngine + SFSpeechRecognizer）。Hardened Runtime 下で必須。
- **App Sandbox は付けない**（自動貼り付け・グローバルホットキーに非互換）。
- `allow-jit` / `disable-library-validation` は **不要**（ggml Metal は out-of-process コンパイルで JIT を使わず、埋め込みフレームワークは同一 Developer ID で再署名するためライブラリ検証も通る）。

---

## 環境変数

| 変数 | 用途 | 例 |
|---|---|---|
| `YOUYAKU_NOTARY_PROFILE` | 公証に使う notarytool キーチェーンプロファイル名。未設定なら公証をスキップ | `youyaku-notary` |
| `YOUYAKU_DIST_IDENTITY` | 使う Developer ID 証明書を明示指定（複数証明書がある場合に必要） | `Developer ID Application: 名前 (TEAMID)` |

---

## サイト公開（ダウンロードリンク）

サイトは **`youyaku.hinoshiba.com`**（**GitHub Pages**）で配信する。macOS 版のダウンロード導線は
トップページ（`http_dist/index.html`）の「Mac版をダウンロード」ボタン（`/download/Youyaku.dmg`）。
ページ側は `download/version.txt` を読んで配布中のバージョンを表示する。

deploy は **GitHub Actions**（`.github/workflows/deploy-pages.yml`）で自動化している。
`main` への push で `http_dist/` 配下（DMG・version.txt を含む）が変わると、`http_dist` を
Pages のアーティファクトとしてアップロードして公開する。

### 初回セットアップ（一度だけ）

1. **Pages ソースを Actions に**: リポジトリ Settings → Pages → Build and deployment → Source を
   **「GitHub Actions」** にする。
2. **カスタムドメイン**: `http_dist/CNAME`（`youyaku.hinoshiba.com`）で指定済み。DNS 側（Cloudflare で
   hinoshiba.com を管理している場合）に **CNAME レコード** `youyaku` → `<ユーザー名>.github.io` を
   **「DNS only（グレーの雲）」** で作成する（オレンジの雲＝プロキシ ON だと GitHub の DNS 検証と
   証明書発行に失敗しやすい）。設定後、Settings → Pages で「Enforce HTTPS」を有効化する。

### リリースごとの手順

```bash
# 証明書のある Mac で:
export YOUYAKU_NOTARY_PROFILE=youyaku-notary
./Scripts/bump-version.sh X.Y.Z   # バージョンを上げる(前述)
./build.sh --dist                 # → http_dist/download/Youyaku.dmg / version.txt を生成(公証込み)

# 生成物を commit して push すると Actions が自動デプロイする
git add http_dist/download/Youyaku.dmg http_dist/download/version.txt Info.plist ios/project.yml
git commit -m "リリース vX.Y.Z"
git push
```

> 公開後は `https://youyaku.hinoshiba.com/download/Youyaku.dmg` からダウンロードできる。

- Mac 版はサイト（`/download/Youyaku.dmg`）から直接ダウンロードさせる。
- iOS は App Store 公開。手順は **[docs/RELEASE-iOS.md](RELEASE-iOS.md)** を参照。

### DMG のサイズ上限

GitHub Pages は **1 ファイル 100 MB・サイト全体 1 GB** がソフト上限（大容量バイナリの常時配信は
推奨用途外だが、数十 MB 級の DMG は実用上問題ない）。現状の内蔵構成（llama.framework の macOS
スライスは約 12 MiB）では DMG は十分収まる。将来大きくなった場合は、不要なアーキテクチャ・
デバッグシンボルを削って DMG を小さくするか、外部の公開ストレージ（R2 の公開バケット等）へ
DMG を移して `http_dist/index.html` のダウンロードリンク 2 か所（ヒーロー・`#download`）と
JSON-LD の `downloadUrl` をその URL に向ける。

## llama.cpp（Vendor）の更新手順

`Scripts/fetch-vendor.sh` は取得する `llama.xcframework` を **リリースタグ + SHA-256 でピン留め**している
（GitHub のリリース資産は権限者が後から差し替え可能なため、タグ固定だけでは真正性を担保できない）。
llama.cpp を上げるときは、次の **3 点セット**を必ず揃えて更新する:

1. **URL（タグ）**: `LLAMA_VERSION` を新しいリリースタグに変更する。
2. **SHA-256**: 新しい資産を手元にダウンロードして `shasum -a 256 <zip>` で実測し、`LLAMA_SHA256` を差し替える。
3. **`.llama-version`**: 展開後に `Vendor/build-apple/.llama-version` へ自動で書き込まれる。
   スクリプトは「ヘッダが存在し、かつ `.llama-version` が `LLAMA_VERSION` と一致」を取得済みと判定するため、
   タグを上げれば次回のビルドで自動的に再取得される（手動での削除は不要）。

あわせて `Sources/Youyaku/LLM/LlamaEngine.swift` が使う API との整合を確認すること。

---

## iOS App Store 提出チェックリスト

> **iOS の詳しいビルド・提出手順は [docs/RELEASE-iOS.md](RELEASE-iOS.md) を参照。** 以下は提出前の最終チェックリスト。

App Store Connect へ提出する前に確認する:

- [ ] **バージョン**: `Scripts/bump-version.sh` で macOS 側と同期済みか（`ios/project.yml` の `MARKETING_VERSION`）。
- [ ] **アプリアイコン**: 1024x1024 のマーケティングアイコンを含む全サイズが揃っているか。
- [ ] **スクリーンショット**: **iPhone と iPad の両方**（`TARGETED_DEVICE_FAMILY: "1,2"` のため iPad 分も必須）。
- [ ] **プライバシーポリシー URL**: `https://youyaku.hinoshiba.com/privacy.html`
- [ ] **サポート URL**: `https://youyaku.hinoshiba.com/privacy.html#contact`（サイトの問い合わせセクション）。
      **提出前に privacy.html の問い合わせ先プレースホルダを実アドレスへ差し替えること**（デプロイ用 GitHub Actions が未設定のままの公開をブロックする）。
- [ ] **App Privacy（プライバシー詳細）**: 「**データ収集なし**」で申告する
      （音声認識・要約ともデバイス上で完結し、外部へデータを送信しないため）。
- [ ] **年齢レーティング**: 新しい questionnaire（2025 年改定版）に回答する（Youyaku は該当コンテンツなしの想定）。
- [ ] **EU DSA トレーダーステータス**: EU デジタルサービス法に基づくトレーダー申告
      （個人開発者なら non-trader / trader を選択し、trader の場合は連絡先住所等の公開が必要）。
- [ ] **輸出コンプライアンス**: `ITSAppUsesNonExemptEncryption` は `false` 設定済み
      （HTTPS 等の OS 標準暗号のみ使用。独自暗号なし）。提出時の質問にも同様に回答する。
- [ ] **Review Notes（審査メモ）文例**:
      > 本アプリがダウンロードする GGUF ファイルは実行コードではなく **モデル重みデータ**であり、
      > 推論はアプリにバンドルされた llama.cpp で行います。モデルのダウンロードによって
      > アプリの機能・挙動は変化しません（ガイドライン 2.5.2 の実行コード DL には該当しません）。
      >
      > 試し方: 設定からモデル「Qwen3 0.6B」をダウンロードすると最速で要約機能を確認できます。
- [ ] **サイトの公開確認**: 審査前に `https://youyaku.hinoshiba.com` が公開・到達可能で、
      `privacy.html` / `terms.html` が開けることを確認する
      （プライバシーポリシー URL・サポート URL に審査担当者がアクセスできないとリジェクトされる）。

---

## 検証（配布前チェック）

```bash
# アプリが「公証済み Developer ID」として受理されるか
spctl --assess -vvv dist/Youyaku.app        # → source=Notarized Developer ID を期待

# 署名内容(runtime フラグ・チーム)の確認
codesign -dv --verbose=4 dist/Youyaku.app

# DMG の staple 検証
xcrun stapler validate dist/Youyaku-*.dmg
```

---

## トラブルシューティング

| 症状 | 対処 |
|---|---|
| 公証が `Invalid` で却下される | `xcrun notarytool log <submission-id> --keychain-profile youyaku-notary` で詳細を確認。多くは timestamp / runtime / entitlements 不備 |
| 起動時に Metal/推論で検証エラー・クラッシュ | `Youyaku.entitlements` の `com.apple.security.cs.disable-library-validation` を有効化して再ビルド・再公証（通常は不要） |
| 起動直後に `dyld: Library not loaded` | rpath 検証で停止するはずだが、埋め込み `llama.framework` の配置と `@executable_path/../Frameworks` を確認 |
| `Developer ID Application 証明書が複数あります` | `YOUYAKU_DIST_IDENTITY='Developer ID Application: 名前 (TEAMID)'` で明示指定 |
| 将来 `llama.xcframework` が複数バイナリ構成になった | 現在は単一 Mach-O 前提で framework を1回署名。取得バージョンを `Scripts/fetch-vendor.sh` で固定（ピン留め）し、必要なら inside-out で個別署名を追加 |

---

## 関連

- 署名周り（TCC 永続化用のローカル自己署名証明書）は `Scripts/setup-signing.sh` を参照。
