# Youyaku iOS 版 App Store 提出 手順書

> **メンテナ向けドキュメント。** リリース担当者が iOS 版を App Store に提出するための手順です。
> 開発・ビルドだけが目的なら [ios/README.md](../ios/README.md) を参照してください。

iOS 版（`ios/`）を App Store で公開するための手順。macOS 版の直販手順は [RELEASE.md](RELEASE.md) を参照。

- **Bundle ID**: `com.hinoshiba.youyaku`（macOS 版と統一。iOS/macOS で同一 ID）
- **配布**: App Store（macOS 版は直販 DMG。iOS だけがストア配布）
- **対応端末**: iPhone + iPad（`TARGETED_DEVICE_FAMILY: "1,2"`）
- **最低 OS**: iOS 17.0
- **プロジェクト生成**: [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`ios/project.yml` → `Youyaku.xcodeproj`）

> `ios/build.sh` は**シミュレータ動作確認用**（Debug・署名なし）。App Store 提出は本書の手順で行う。

---

## 0. Xcode Cloud 初回接続（初回のみ）

App Store Connect の既存アプリ `Youyaku`（App ID `6788719460`、Bundle ID
`com.hinoshiba.youyaku`）と Apple Developer Team `94HVVWXLK3` を使用する。署名はXcode Cloudの
automatic signingに任せ、ローカルのApple Distribution証明書やprovisioning profileは使用しない。

初回workflowだけはXcodeから作成する必要がある。`Youyaku.xcodeproj` はXcode Cloudが常に
productを検出できるようリポジトリに含めている。XcodeのReport navigatorにあるCloud画面から
`Youyaku` productを既存のApp Store Connectアプリへ接続する。

```bash
cd ios
open Youyaku.xcodeproj
```

最初の接続buildでは、Xcodeが提案するworkflowを編集してActionを**Build**（Archiveではない）にし、
`main`から1回実行する。release用scriptはタグなしArchiveを意図的に拒否する。productの登録が完了したら、
この初期workflowを次のrelease設定へ変更する。

最初のbuildが完了したら、App Store Connectの **Youyaku → Xcode Cloud** でworkflowを次の値にする。

- 名前: `Release`
- General: **Restrict Editing**を有効にし、編集できる管理者をリリース担当者に限定する
- Start Condition: **Tag Changes**、Custom Pattern `v*`
- Auto-cancel Builds: **Off**（release tag buildを途中で取り消さない）
- Action: **Archive**、Platform `iOS`、Scheme `Youyaku`
- Deployment Preparation: **TestFlight and App Store**
- TestFlightへの自動配布は、対象のinternal groupがある場合だけpost-actionとして追加する

`ios/ci_scripts/ci_post_clone.sh` が固定バージョンのllama.xcframeworkを用意する。
`ci_pre_xcodebuild.sh` はplatform、scheme、Bundle ID、Team、タグ、`MARKETING_VERSION`を検証し、
不一致ならbuildを停止して、`CI_BUILD_NUMBER`を`CURRENT_PROJECT_VERSION`へ設定する。

product登録後、App Store Connectの **Youyaku > Xcode Cloud > Settings > Build Number** で、
**Next Build Number**を同じmarketing versionで過去にupload済みの最大値より大きくする。
`ios/project.yml`の`CURRENT_PROJECT_VERSION`以上、かつApp Store Connectに同じmarketing versionで
存在する最大buildより大きい値から開始する。新しいmarketing versionではiOSの組み合わせ要件上
`1`からでもよいが、Cloud buildとcandidateを一意に追跡しやすいよう既存連番の継続を推奨する。

GitHubではworkflowを有効にする前に、**Settings > Rules > Rulesets**でActiveなtag rulesetを作成する。
対象patternを`v*`にし、**Restrict creations**、**Restrict updates**、**Restrict deletions**を有効にする。
bypassは指定されたリリース担当者だけに限定し、review済みの`main` commitにだけtagを作成する。release tagは
Xcode Cloudによる署名済みcandidateのbuild/uploadとmacOS版GitHub Releaseの起点になるため、移動・再利用しない。

---

## 1. バージョンを上げる

```bash
./Scripts/bump-version.sh X.Y.Z
```

`ios/project.yml` の `MARKETING_VERSION`（表示バージョン）とローカル用の
`CURRENT_PROJECT_VERSION`が更新される。Xcode CloudではCloud側の連番`CI_BUILD_NUMBER`を使用する。

> Info.plist の版数は `project.yml` の変数（`$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)`）を
> 参照するため、`xcodegen generate` のたびに正しい値で再生成される。

---

## 2. タグでアーカイブとアップロードを開始

変更を`main`へmergeし、`MARKETING_VERSION`と同じ`vX.Y.Z`タグをそのmerge commitへ付けてpushする。

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```

Xcode Cloudの`Release` workflowがarchive・automatic signing・App Store Connectへのuploadを行う。
処理後、TestFlightでversion、Cloud build number、Bundle IDが意図した値であることを確認する。
タグ名とversionが違う場合はbuildが失敗するため、誤ったタグを付け直して同じ版を上書きしない。

---

## 3. App Store Connect でのメタデータ設定

App Store Connect → アプリ → 対象バージョンのページで設定する（[提出前チェックリスト](RELEASE.md#ios-app-store-提出チェックリスト)も参照）。
以下は 2026-07 時点の Apple 公式仕様（[Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications/) /
[Creating Your Product Page](https://developer.apple.com/app-store/product-page/)）で確認した内容。

### 3.1 スクリーンショット（step by step）

**必要なサイズ（2024〜2025 に簡素化済み）**: 現在必須なのは次の **2 クラスだけ**。他サイズは Apple が
自動スケールするので用意不要。iPhone のみ／iPad のみのアプリはどちらか一方でよいが、本アプリは
iPhone + iPad 両対応（`TARGETED_DEVICE_FAMILY: "1,2"`）なので **両方必須**。

| クラス | 縦向きの受理寸法（いずれか。1px でもズレると不可） | 撮影用シミュレータ |
|---|---|---|
| **6.9" iPhone**（必須） | `1320 x 2868` / `1290 x 2796` / `1260 x 2736` | iPhone 16 Pro Max（1320×2868 出力）|
| **13" iPad**（必須） | `2064 x 2752` / `2048 x 2732` | iPad Pro 13-inch (M4)（2064×2752 出力）|

- 枚数は **1 クラスにつき最小 1・最大 10 枚**（`.png` / `.jpg` / `.jpeg`）。実務では各 3〜5 枚を推奨。
- シミュレータのネイティブ出力はこの寸法に一致するので、**リサイズせずそのまま提出**する（手動リサイズは 1px ズレの原因）。

**撮る画面（本アプリの 4 タブ。1 枚目に最も価値が伝わる画面を置く）**:
1. **音声入力（DictateView）** ← 1 枚目推奨。中央の大きなマイク＋整形結果が見える状態
2. **モデル（ModelsView）** … 日本語モデルをワンタップ DL できるカタログ
3. **履歴（HistoryView）** … 過去の入力を再利用
4. **設定（SettingsView）** … オンデバイス処理・プライバシーの訴求

> **シミュレータ機種名は Xcode のバージョンで変わる**。`xcrun simctl boot "iPhone 16 Pro Max"` が
> `Invalid device or device pair` で失敗する場合、その名前のシミュレータが無いだけ。下記①で
> **実際に使える機種を一覧確認**し、上のクラスに合うものを選ぶ（6.9" クラスなら 17/16/15/14 Pro Max・
> 16/15 Plus のいずれか、13" クラスなら iPad Pro 13-inch (M4) か iPad Pro 12.9-inch のいずれか）。
> 一覧に iOS/iPadOS シミュレータが無ければ **Xcode → Settings → Components** でランタイムを入れる。

**手順**:

```bash
cd ios && xcodegen generate

# ① 使えるシミュレータを一覧確認し、6.9" iPhone クラスと 13" iPad クラスの
#    「正確な名前」または UDID を控える(名前は完全一致が必要)
xcrun simctl list devices available
#   例: "iPhone 15 Pro Max (AAAAAAAA-....)" のように表示される

# ② 一覧に出た名前(または UDID)で起動する。以降 booted は「起動中のデバイス」を指す
DEVICE="iPhone 15 Pro Max"      # ← ①で確認した実在の名前に置き換える
xcrun simctl boot "$DEVICE"
open -a Simulator

# ③ アプリをインストールして起動(ios/build.sh。Debug 版でも撮影は可)
./build.sh "$DEVICE" run

# ④ ステータスバーを審査向けに整形(時刻 9:41・フル電波・フル電池・キャリア名なし)
#    ※オプション名は環境により異なることがあるので `xcrun simctl help status_bar` で最終確認
xcrun simctl status_bar booted override \
  --time "9:41" \
  --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 \
  --batteryState charged --batteryLevel 100 \
  --operatorName ""

# ⑤ 各タブを表示しながら撮影(アプリ操作は手動 or シミュレータ上で)
mkdir -p ~/Desktop/shots
xcrun simctl io booted screenshot ~/Desktop/shots/iphone-1-dictate.png
xcrun simctl io booted screenshot ~/Desktop/shots/iphone-2-models.png
xcrun simctl io booted screenshot ~/Desktop/shots/iphone-3-history.png
xcrun simctl io booted screenshot ~/Desktop/shots/iphone-4-settings.png

# ⑥ 撮影後、ステータスバーの上書きを解除
xcrun simctl status_bar booted clear

# ⑦ iPad(13" クラス)でも同じことを繰り返す
DEVICE="iPad Pro 13-inch (M4)"  # ← ①の一覧にある実在名に置き換える
xcrun simctl boot "$DEVICE"
# …③〜⑥ を実行(ファイル名は ipad-* にする)

# 寸法確認(受理寸法ちょうどであること)
sips -g pixelWidth -g pixelHeight ~/Desktop/shots/iphone-1-dictate.png
```

> 名前合わせが面倒なら、`open Youyaku.xcodeproj` で Xcode を開き、ツールバーで対応シミュレータを
> 選んで **⌘R** で実行するのが確実(Xcode が自動起動する)。起動後に上の `simctl io booted screenshot` で撮る。

**やってはいけないこと（審査で弾かれる／Guideline 2.3 正確なメタデータ）**:
- **端末フレーム（ベゼル）を合成しない**。提出するのは受理寸法ちょうどの**フラットなアプリ画面画像**。
  枠は App Store 側が表示時に付ける。
- **生のステータスバーを写さない**（実在キャリア名・低電波・低電池・実時刻）。上記③で整形する。
- **価格・期間限定の宣伝文・他プラットフォーム名（Android 等）・未実装機能のモック**を画面内に入れない。
- 文字を焼き込むキャプション付き画像にする場合も、上記の禁止事項は同じ。

> App Preview（動画）を登録する場合は、公式仕様上つねにスクリーンショットより前に表示される
> （`App previews always precede screenshots`）。動画は任意。

### 3.2 テキスト項目（文字数上限と例文）

日本語を主言語（Primary Language）にし、必要なら英語ローカライズを追加する。各上限は Apple 公式で確認済み:

| 項目 | 上限 | 更新タイミング | 備考 |
|---|---|---|---|
| App 名（Name） | **30 文字**（最小 2） | バージョン提出時 | 例: `Youyaku ー 声でAIに指示` |
| サブタイトル（Subtitle） | **30 文字** | バージョン提出時 | 名前の下に表示 |
| プロモーションテキスト | **170 文字** | **いつでも（審査不要）** | description 上部に表示。お知らせ向き |
| 概要（Description） | **4,000 文字** | バージョン提出時 | 機能説明の本文 |
| キーワード（Keywords） | **100 文字（合計）** | バージョン提出時 | カンマ区切り・**カンマ後にスペースを入れない** |

- **プロモーションテキストだけは新バージョンを出さずに随時更新できる**（お知らせやキャンペーン告知の差し替えに使える）。概要はバージョン提出時のみ更新可。
- **キーワードのスペースは 100 文字にカウントされ無駄**になる。`音声入力,AI,ローカル` のようにカンマ直後は詰める（句の中の語区切りにはスペース可）。

**例文（そのまま使わず調整すること。iOS は常に端末内処理なので断定表現も可）**:

- **サブタイトル案（30 字以内）**: `話すだけ、ローカルAIが指示文に整える`
- **プロモーションテキスト案（170 字以内）**:
  > 声で話すだけ。オンデバイスAIがフィラーを除き、AIアシスタントに伝わる指示文へ整えます。音声もテキストもすべて端末内で処理。アカウント不要・無料。
- **キーワード案（100 字以内・カンマ後スペースなし）**:
  > `音声入力,音声認識,オンデバイス,ローカルAI,文字起こし,ディクテーション,プロンプト,指示文,議事録,メモ,AIアシスタント`
- **概要案（骨子。4,000 字以内で肉付け）**:
  > Youyaku（ようやく）は、AIアシスタントへの指示を「声」で作るための音声入力アプリです。話した内容を、オンデバイスのローカルLLMが「AIに伝わる指示文」へ整えます。
  >
  > ■ すべて端末内で完結
  > 音声認識も文章整形も、すべてこの端末の中だけで動作します。音声もテキストも外部に送信されません（モデルのダウンロード時のみ Hugging Face に接続します）。
  >
  > ■ 主な機能
  > ・話すだけでフィラー（「えー」「あの」）や言い直しを除去し、構造化された指示文に再構成
  > ・そのまま／整文／AI命令化の3モード
  > ・日本語に強いモデルを厳選（端末のメモリに合わせて選択・ワンタップDL）
  > ・入力履歴の検索・再利用
  >
  > アカウント登録不要。完全無料。

> **注意**: キーワードや概要に **他社サービス名・商標（ChatGPT / Claude 等）を入れない**こと
> （Guideline 2.3.7・商標の観点でリジェクト要因になりやすい）。概要本文で「AIアシスタントへの指示」
> のように一般名詞で説明するのは問題ないが、キーワード欄にブランド名を並べるのは避ける。

### 3.3 その他の必須項目

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

- Xcode Cloudはbuildをuploadするところまでを担当し、App Reviewへの提出は自動実行しない。
- App Store Connectで正しいbuildを選択し、既存のrelease設定を確認してからレビューへ提出する。
- 公開されると App Store の製品ページ（<https://apps.apple.com/jp/app/id6788719460>）が有効になる。
  サイト（`http_dist/index.html`）や README の iOS リンクがこの URL を指していることを確認する。
  サイトの変更は `main` への push で GitHub Actions（`deploy-pages.yml`）が自動デプロイする。

---

## 参考リンク

- App Store Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- App Privacy Details: https://developer.apple.com/app-store/app-privacy-details/
- Xcode Cloud distribution: https://developer.apple.com/documentation/xcode/distributing-your-xcode-cloud-builds-through-testflight
