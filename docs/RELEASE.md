# Youyaku 配布・署名・公証 手順書(macOS)

> **メンテナ向けドキュメント。** リリース担当者が macOS 版を Developer ID 直販で配布するための手順です。
> アプリのビルドや開発だけが目的なら [README](../README.md) と [CONTRIBUTING](../CONTRIBUTING.md) で十分です。

macOS 版 Youyaku を **Developer ID 直販（App Store 外）** で配布するための手順書。
`build.sh --dist` を実行すると、**署名 → DMG 生成 → 公証(notarization) → staple → 更新フィード(appcast.xml)生成**
までが自動で走る。DMG 本体は **GitHub Releases**（タグ `v<version>` / アセット名 `Youyaku.dmg`）へ手動でアップロードする。

## リリース権限の保護

`v*`タグはレビュー済みのリリースcommitを記録するものとして扱う。GitHubの **Settings > Rules > Rulesets** にActiveなtag rulesetを作り、
対象patternを`v*`、rulesを **Restrict creations**、**Restrict updates**、**Restrict deletions** とする。
bypassは指定されたリリース担当者だけに限定し、review済みの`main` commitにだけtagを作成する。
一度公開したrelease tagは移動、削除、再利用せず、訂正時は新しいversionを使う。

## ローカルXcodeによるリリース

macOS版は本書のローカルビルド・署名・公証手順、iOS版は
[ローカルXcode Organizerでの提出手順](RELEASE-iOS.md)を使用します。
タグのpushからiOSアーカイブやApp Store Connectへのアップロードを自動実行しません。
GitHub Actionsは認証情報を必要としない検証とサイト配信を担当します。

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

承認済みMacのキーチェーンにある既存の **Developer ID Application** identityを使用します。通常のビルドで新規作成や秘密鍵の書き出しは行いません。

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

### 4. Sparkle（アプリ内アップデート）の署名鍵を作成

アプリは、更新用 DMG が **自分たちの鍵で署名されたもの** であることを EdDSA 署名で検証してから適用する。
その鍵ペアを一度だけ作る。

```bash
./Scripts/setup-sparkle-keys.sh
```

- 秘密鍵は **ログインキーチェーン**に保存される（リポジトリには入らない）。
- 表示された公開鍵を `Info.plist` の `SUPublicEDKey` に反映する:
  `/usr/libexec/PlistBuddy -c "Set :SUPublicEDKey <公開鍵>" Info.plist`
- 未設定（プレースホルダのまま）だと、`build.sh --dist` は**エラーで停止**し、開発ビルドのアプリは
  更新機構を起動しない（鍵が無ければ検証に必ず失敗するため、通信もせず黙って無効化する）。

> **★ 秘密鍵は必ずバックアップする。** 失うと既存の利用者へアップデートを配れなくなる
> （公開鍵を変えた新版を配っても、旧版のアプリはそれを検証できない）。
> 書き出し: `Vendor/sparkle-bin/generate_keys -x sparkle-private-key.txt`（安全な場所へ移してから削除）

> **別の Mac で署名する場合は「作成」ではなく「取り込み」。** 署名用 Mac を移行・新調したときに
> `setup-sparkle-keys.sh`（引数なしの `generate_keys`）を実行すると**新しい鍵ペアができてしまい**、
> 公開鍵が変わって既存利用者へアップデートを配れなくなる。バックアップした秘密鍵を取り込む:
> `Vendor/sparkle-bin/generate_keys -f sparkle-private-key.txt`
> （キーチェーンに既存の「Private key for signing Sparkle updates」があれば先に削除してから）。
> 取り込み後、`Info.plist` の `SUPublicEDKey` が既存の公開鍵のままであることを確認する。

### 5. GitHub CLI（`gh`）を用意（任意）

タグ作成と DMG アップロードは GitHub Web UI で行うため必須ではない。
`Scripts/publish-release.sh` でコマンドから自動化したい場合のみ用意する。

```bash
brew install gh && gh auth login
```

---

## ビルド

### 0. バージョンを上げる（リリースごとに最初に行う）

```bash
./Scripts/bump-version.sh 1.1.0   # 例: 1.1.0 に上げる
```

- ルート `Info.plist` の `CFBundleShortVersionString` を書き換え、`CFBundleVersion` を +1 する。
- `ios/project.yml` の `MARKETING_VERSION` / ローカル用`CURRENT_PROJECT_VERSION`も同期する（App Store Connectの提出済みbuild番号を確認して重複を避ける）。
- DMG のファイル名、リリースタグ `v<version>`、サイトの `version.txt`、`appcast.xml` の版数は
  すべてこの値を参照するため、**ビルド前に必ず実行**する。

### 開発ビルド（手元での動作確認用）

```bash
./build.sh
```

既定ではcredential不要のad-hoc署名を使います。権限の継続が必要な場合だけ、既にインストールされた開発用identityを `YOUYAKU_DEV_IDENTITY` で明示指定できます。自動キーチェーン解除や鍵の作成は行いません。公証・DMGは配布ビルドで行います。

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

0. **Sparkle 公開鍵の確認**：`Info.plist` の `SUPublicEDKey` が未設定なら即エラー
   （長いビルドと公証を走らせてから、更新機構の死んだ配布物ができあがるのを防ぐ）。
1. **Swift ビルド**（universal: `swift build -c release --arch arm64 --arch x86_64`）してアプリバンドルを組み立て、
   `lipo -archs` で両アーキテクチャを検証し、`llama.framework` と `Sparkle.framework` を埋め込む。
   Sparkle の `XPCServices` は App Sandbox 下のアプリ専用なので取り除く。
2. **inside-out 署名**（フレームワーク内の実行ファイル → フレームワーク → アプリ本体の順）。いずれも:
   - `--options runtime`（Hardened Runtime。公証の必須要件）
   - `--timestamp`（セキュアタイムスタンプ。公証の必須要件・証明書失効後も検証可）
   - アプリ本体に `--entitlements Youyaku.entitlements` を適用
   - `Sparkle.framework` は中に実行ファイル（`Autoupdate`）とアプリ（`Updater.app`）を抱えているため、
     **先にそれらを署名しないと**フレームワークの署名が壊れ、公証も通らない。
3. **署名検証** + **rpath 検証**（`@executable_path/../Frameworks` が無いと起動時に dyld で落ちるため）。
4. **アプリ本体を公証 + staple**（`ditto` で zip 化 → `notarytool submit --wait` → `stapler staple`）。
   DMG 封入前にアプリ自身へチケットを焼き込むことで、**DMG から取り出した後もオフラインで Gatekeeper を通せる**。
5. **DMG 生成**（staple 済みアプリ + `/Applications` シンボリックリンク）。
   Chrome などと同じ「背景画像 + 大きなアイコン + → Applications」のインストーラーウィンドウにする。
   背景画像は `Scripts/MakeDMGBackground.swift` が生成（Retina 対応）し、レイアウトは一時マウントした
   イメージ上で Finder に書かせて（`.DS_Store`）から読み取り専用の UDZO に変換する。
   - Finder を AppleScript で操作するため、**初回はターミナルへの「Finder の操作許可」ダイアログが出る**
     （システム設定 > プライバシーとセキュリティ > オートメーション）。
6. **DMG 署名**（Developer ID + タイムスタンプ）。
7. **DMG を公証 + staple**、`stapler validate` で検証。
8. **更新フィードを生成**：`sign_update` で DMG に EdDSA 署名を付け、`http_dist/download/appcast.xml` と
   `http_dist/download/version.txt` を書き出す。
   - 未公証（`YOUYAKU_NOTARY_PROFILE` 未設定）の場合は**スキップ**する（配布不可の DMG 向けのフィードを作らないため）。
   - appcast の `enclosure` は `https://github.com/hinoshiba/youyaku/releases/download/v<version>/Youyaku.dmg` を指す。
     - **この時点ではまだアセットは存在しない**（次節「リリースごとの手順」で GitHub Releases へ上げる）。
     - DMG 本体の公開は GitHub Web UI でのタグ作成 + アップロードで行う（`gh` があれば `Scripts/publish-release.sh` でも可）。


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

## 配布物の置き場所

| もの | 置き場所 | 理由 |
|---|---|---|
| DMG 本体 | **GitHub Releases**（タグ `v<version>` / アセット名 `Youyaku.dmg` 固定） | バイナリを commit するとリリースごとに履歴が数 MiB ずつ太るため |
| `appcast.xml` / `version.txt` | **GitHub Pages**（`youyaku.hinoshiba.com/download/`） | 小さなテキスト。フィード URL をサイト側に固定しておくと、将来 DMG の置き場所を変えてもアプリを作り直さずに追随できる |
| サイト本体（HTML） | **GitHub Pages** | 同上 |

- appcast の `enclosure`: `https://github.com/hinoshiba/youyaku/releases/download/v<version>/Youyaku.dmg`
- サイトのダウンロードボタン: `https://github.com/hinoshiba/youyaku/releases/latest/download/Youyaku.dmg`

アセット名を版に依らず `Youyaku.dmg` に固定し、タグで版を分けているため、サイトは版に依らない
`latest` リンクを、appcast は版を固定したリンクを、同じ 1 ファイルに対して使える。

> **⚠ リポジトリが公開されていることが前提。** GitHub Releases のアセットは、非公開リポジトリでは
> 認証なしにダウンロードできない。非公開のままリリースすると、サイトのダウンロードボタンも
> アプリ内アップデートも 404 になる。`Scripts/publish-release.sh` はこれを検出してエラーで停止する。

サイトは **`youyaku.hinoshiba.com`**（**GitHub Pages**）で配信する。ページ側は `download/version.txt` を
読んで配布中のバージョンを表示する。deploy は **GitHub Actions**（`.github/workflows/deploy-pages.yml`）で
自動化しており、`main` への push で `http_dist/` 配下が変わると Pages へ公開する。

### 初回セットアップ（一度だけ）

1. **Pages ソースを Actions に**: リポジトリ Settings → Pages → Build and deployment → Source を **「GitHub Actions」** にする。
2. **カスタムドメイン**: `http_dist/CNAME`（`youyaku.hinoshiba.com`）で指定済み。DNS 側（Cloudflare で
   hinoshiba.com を管理している場合）に **CNAME レコード** `youyaku` → `<ユーザー名>.github.io` を
   **「DNS only（グレーの雲）」** で作成する（オレンジの雲＝プロキシ ON だと GitHub の DNS 検証と
   証明書発行に失敗しやすい）。設定後、Settings → Pages で「Enforce HTTPS」を有効化する。

### リリースごとの手順

DMG の署名・公証と appcast の EdDSA 署名は、**Developer ID 証明書と Sparkle 秘密鍵のある Mac**（以下「署名用 Mac」）で行う。
タグ打ちと DMG のアップロードは **GitHub の Web UI** で手作業で行う。

**実行順に意味がある**。先に Releases へ DMG を上げ、あとから appcast.xml を push する。
逆順にすると、Pages にフィードが載ってから DMG がアップされるまでのあいだ、
「アプリには更新が見えるのにダウンロードは 404」という時間帯ができる。

#### 1. 署名用 Mac でビルドする

```bash
export YOUYAKU_NOTARY_PROFILE=youyaku-notary

# バージョンを上げ、コードの状態を確定させて push する
# （タグはこのコミットに付ける。未 push のコミットにはタグを作れない）
./Scripts/bump-version.sh X.Y.Z
git add Info.plist ios/project.yml ios/Youyaku.xcodeproj
git commit -m "リリース vX.Y.Z"
git push

# ビルド → 公証 → DMG と appcast.xml / version.txt を生成
./build.sh --dist
```

生成物:
- `dist/Youyaku-X.Y.Z.dmg`（公証・staple 済み）
- `http_dist/download/appcast.xml` / `http_dist/download/version.txt`（手順 3 で push する）

#### 2. GitHub Web UI でタグを打ち、DMG を上げる

アップロードするアセット名は **`Youyaku.dmg` に統一する**（appcast の `enclosure` とサイトの `latest`
リンクがこの名前を指すため）。ビルド成果物は版番号つきの名前なので、先に固定名へコピーしておく:

```bash
cp dist/Youyaku-X.Y.Z.dmg dist/Youyaku.dmg
```

そのうえで GitHub の Web UI で:

1. リポジトリの **Releases → Draft a new release** を開く。
2. **Choose a tag** に `vX.Y.Z` を入力し、**Create new tag: vX.Y.Z on publish** を選ぶ。
   ターゲット（Target）は手順 1 で push した `main` の最新コミット。
3. タイトルに `vX.Y.Z`、必要なら本文にリリースノートを書く。
4. **Attach binaries** の欄へ `dist/Youyaku.dmg` をドラッグしてアップロードする。
5. **Publish release**。

iOS版は同じレビュー済みversionをローカルXcodeでアーカイブします。タグのpushだけでは提出されません。

公開後、アセットが `Youyaku.dmg` として
`https://github.com/hinoshiba/youyaku/releases/latest/download/Youyaku.dmg` から取得できることを確認する。

#### 3. 更新フィードを公開する

Releases に DMG が載ったのを確認してから appcast を push する（既存利用者のアプリ内アップデートに反映される）:

```bash
git add http_dist/download/appcast.xml http_dist/download/version.txt
git commit -m "appcast vX.Y.Z"
git push
```

- Mac 版はサイトのボタン（→ GitHub Releases）から直接ダウンロードさせる。既存利用者はアプリ内で更新する。
- iOS は App Store 公開。手順は **[docs/RELEASE-iOS.md](RELEASE-iOS.md)** を参照。

> 公開済みの DMG を**差し替えてはいけない**。`appcast.xml` の EdDSA 署名は DMG のバイト列に紐づくため、
> 差し替えると、既に配ったフィードを持つアプリが検証に失敗する。版を上げて出し直すこと。

> **`gh` CLI が使える署名用 Mac なら**、手順 2 の代わりに `./Scripts/publish-release.sh` で
> タグ作成と `Youyaku.dmg` のアップロードを自動化できる（固定名へのコピーも同スクリプトが行い、
> 既存アセットの上書きは既定で拒否する）。

### 公開範囲について

GitHub Pages は公開サイトのため、Cloudflare Access のような認証ゲートは使えない
（Pages の URL を知っていれば誰でもアクセスできる）。加えて、上記のとおり **Releases 配布は
リポジトリの公開が前提**。身内限定フェーズを厳密に保ちたい場合は、サイトのリンクを共有しない
運用にとどめるか、認証付きの別ホスティングと外部ストレージ（R2 の公開バケット等）へ
`appcast.xml` の `enclosure` と `index.html` のリンクを向け直す。
iOS 審査時は、審査担当がプライバシーポリシー URL・サポート URL に到達できるようサイトが公開されている必要がある。

---

## アプリ内アップデート（Sparkle）

macOS 版は [Sparkle 2](https://sparkle-project.org/) を埋め込んでおり、更新はアプリ内で完結する
（ダウンロード → 署名検証 → 入れ替え → 再起動）。

- **フィード**: `Info.plist` の `SUFeedURL` = `https://youyaku.hinoshiba.com/download/appcast.xml`
- **検証**: DMG の EdDSA 署名（`SUPublicEDKey` と対になる秘密鍵で `sign_update` が署名）に加えて、
  Sparkle が新旧アプリの Developer ID 署名の一致も確認してから入れ替える。
- **勝手に入れない**: `SUAllowsAutomaticUpdates=false`。ダウンロードとインストールは毎回利用者が選ぶ。
- **通知の出しかた**: メニューバー常駐アプリなので、定期チェックで更新ダイアログを前面に出さず、
  ホーム画面とメニューにバナーを出すだけにしている（Sparkle の "gentle reminders"）。
  実装は `Sources/Youyaku/Support/Updater.swift`。
- **設定**: 「アップデートを自動確認」をオフにすると定期チェックの通信ごと止まる。

鍵の作成・バックアップ・別 Mac への取り込みは「前提条件 → 4. Sparkle の署名鍵を作成」を参照。

## Vendor（llama.cpp / Sparkle）の更新手順

`Scripts/fetch-vendor.sh` は取得する xcframework を **リリースタグ + SHA-256 でピン留め**している
（GitHub のリリース資産は権限者が後から差し替え可能なため、タグ固定だけでは真正性を担保できない）。
上げるときは、次の **3 点セット**を必ず揃えて更新する:

1. **URL（タグ）**: `LLAMA_VERSION` / `SPARKLE_VERSION` を新しいリリースタグに変更する。
2. **SHA-256**: 新しい資産を手元にダウンロードして `shasum -a 256 <zip>` で実測し、
   `LLAMA_SHA256` / `SPARKLE_SHA256` を差し替える。
3. **バージョンファイル**: 展開後に `Vendor/build-apple/.llama-version` / `Vendor/.sparkle-version` へ
   自動で書き込まれる。スクリプトはこれが定数と一致するかで取得済みを判定するため、
   タグを上げれば次回のビルドで自動的に再取得される（手動での削除は不要）。

- llama.cpp: あわせて `Sources/Youyaku/LLM/LlamaEngine.swift` が使う API との整合を確認すること。
- Sparkle: `Package.swift` のコメントの版数と、`THIRD_PARTY_LICENSES.txt` の帰属表記
  （`Vendor/sparkle-LICENSE` と突き合わせる）も更新すること。**公開鍵（`SUPublicEDKey`）は変えない**。

---

## iOS App Store 提出チェックリスト

> **iOS の詳しいビルド・提出手順は [docs/RELEASE-iOS.md](RELEASE-iOS.md) を参照。** 以下は提出前の最終チェックリスト。

App Store Connect へ提出する前に確認する:

- [ ] **バージョン**: `Scripts/bump-version.sh` で macOS 側と同期済みか（`ios/project.yml` の `MARKETING_VERSION`）。
- [ ] **ローカルビルド**: Xcode Organizerから検証・アップロードし、意図したversion/buildをTestFlightで確認したか。
- [ ] **アプリアイコン**: 1024x1024 のマーケティングアイコンを含む全サイズが揃っているか。
- [ ] **スクリーンショット**: **iPhone と iPad の両方**（`TARGETED_DEVICE_FAMILY: "1,2"` のため iPad 分も必須）。
- [ ] **プライバシーポリシー URL**: `https://youyaku.hinoshiba.com/#privacy`
- [ ] **サポート URL**: `https://youyaku.hinoshiba.com/#support`（サイトの問い合わせセクション）。
- [ ] **App Privacy（プライバシー詳細）**: 現在のアプリの挙動・設定・依存に合わせて申告し、サイトのポリシーと一致させる。
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
      `#privacy` / `#terms` / `#support` が開けることを確認する
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

- 開発用の署名は `YOUYAKU_DEV_IDENTITY` による既存identityの選択を使用します。`Scripts/setup-signing.sh` はidentityを作成する独立した管理用操作で、通常のビルド手順には含めません。
