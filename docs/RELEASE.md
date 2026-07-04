# Youyaku 配布・署名・公証 手順書(macOS)

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

> `YOUYAKU_NOTARY_PROFILE` を設定せずに `--dist` を実行すると、署名と DMG 生成までは行い、**公証はスキップ**される
> （手元テスト用。この DMG は配布しないこと）。

---

## パイプラインが行うこと

`build.sh --dist` → `Scripts/make-dmg.sh` の流れ:

1. **Swift ビルド**（`swift build -c release`）してアプリバンドルを組み立て、`llama.framework` を埋め込む。
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

- 販売（有料アプリ / アプリ内課金）を行う場合の **特定商取引法の表記・氏名/住所プライバシー** はメモリ（`youyaku-release-monetization-legal`）に整理済み。無料配布 + 寄付のみなら特商法は非適用。
- 署名周り（TCC 永続化用のローカル自己署名証明書）は `Scripts/setup-signing.sh` を参照。
