#!/bin/zsh
# 署名済み Youyaku.app から配布用 DMG を作成し、可能なら公証(notarize)+staple したうえで、
# Sparkle の更新フィード(http_dist/download/appcast.xml)を生成する。
# DMG の実体は GitHub Releases に置く(→ docs/RELEASE.md「リリースごとの手順」で手動アップロード)。
#
#   使い方: ./Scripts/make-dmg.sh [dist/Youyaku.app]
#   通常は ./build.sh --dist から自動で呼ばれる。
#
# 公証を有効にするには、事前に一度だけ notarytool のキーチェーンプロファイルを作成しておく:
#   xcrun notarytool store-credentials youyaku-notary \
#       --apple-id  <Apple ID(メール)> \
#       --team-id   <10桁のTEAMID> \
#       --password  <App用パスワード(appleid.apple.com で発行)>
# その上で環境変数で有効化:
#   export YOUYAKU_NOTARY_PROFILE=youyaku-notary
#   ./build.sh --dist
#
# 公証は「アプリ本体」と「DMG」の2段階で行う。アプリ本体に staple しておくことで、
# DMG から /Applications へコピーした後もオフラインで Gatekeeper を通せる(初回起動の警告回避)。
#
# インストーラーウィンドウの見た目(背景画像・アイコン配置)は Finder を AppleScript で
# 操作して作るため、初回実行時はターミナルへの「Finder の操作許可」ダイアログが出る。
set -e
cd "$(dirname "$0")/.."

APP="${1:-dist/Youyaku.app}"
if [ ! -d "$APP" ]; then
    echo "!! アプリが見つかりません: $APP" >&2
    exit 1
fi

APP_NAME="Youyaku"
# DMG を置く GitHub リポジトリ(Releases)。appcast の enclosure URL に埋め込まれる
GITHUB_REPO="hinoshiba/youyaku"
# PlistBuddy は読み取り失敗時にエラー文言を stdout に出しうるので、非0終了なら空に倒し、
# さらに想定外の文字列(空白混じり=エラー文言等)も弾く
if ! VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null); then
    VERSION=""
fi
if [ -z "$VERSION" ] || [[ "$VERSION" == *" "* ]]; then
    echo "!! バージョン(CFBundleShortVersionString)を正しく取得できませんでした: $APP/Contents/Info.plist" >&2
    exit 1
fi
DMG="dist/${APP_NAME}-${VERSION}.dmg"
STAGING="dist/dmg-staging"

# 署名に使う Developer ID を解決(build.sh から YOUYAKU_DIST_IDENTITY で渡される。単体実行時はここで検出)
DIST_ID="${YOUYAKU_DIST_IDENTITY:-}"
if [ -z "$DIST_ID" ]; then
    DID_COUNT=$(security find-identity -v -p codesigning 2>/dev/null | grep -c 'Developer ID Application') || true
    if [ "${DID_COUNT:-0}" -gt 1 ]; then
        echo "!! Developer ID Application 証明書が複数あります。YOUYAKU_DIST_IDENTITY で明示指定してください。" >&2
        exit 1
    fi
    DIST_ID=$(security find-identity -v -p codesigning 2>/dev/null \
        | grep -o '"Developer ID Application:[^"]*"' | head -1 | tr -d '"')
fi
PROFILE="${YOUYAKU_NOTARY_PROFILE:-}"

# ---- 1. アプリ本体を公証 + staple(DMG 封入前に app 自身へチケットを焼き込む)----
if [ -n "$PROFILE" ]; then
    echo "==> アプリ本体を公証(notarytool) — 数分かかることがあります"
    APP_ZIP="dist/${APP_NAME}-notarize.zip"
    ditto -c -k --keepParent "$APP" "$APP_ZIP"
    if xcrun notarytool submit "$APP_ZIP" --keychain-profile "$PROFILE" --wait; then
        xcrun stapler staple "$APP"
        echo "==> アプリ本体に staple 完了"
        # Gatekeeper 評価の確認(source=Notarized Developer ID を期待)。情報表示のみ
        spctl --assess -vvv "$APP" 2>&1 | sed 's/^/    /' || true
    else
        echo "!! アプリの公証に失敗しました。ログ: xcrun notarytool log <submission-id> --keychain-profile $PROFILE" >&2
        rm -f "$APP_ZIP"
        exit 1
    fi
    rm -f "$APP_ZIP"
fi

# ---- 2. DMG 生成(staple 済み app を封入)----
# Chrome 等と同じ「背景画像+大きなアイコン+→ Applications」のインストーラーウィンドウにする。
# 手順: 書き込み可能な UDRW で作る → 一時マウントして Finder にレイアウト(.DS_Store)を
# 書かせる → 読み取り専用の UDZO に変換。レイアウトの座標は MakeDMGBackground.swift と対応。
echo "==> DMG ステージング作成"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING/.background"
cp -R "$APP" "$STAGING/"
# ドラッグ&ドロップでインストールできるよう /Applications へのシンボリックリンクを置く
ln -s /Applications "$STAGING/Applications"

# 背景画像(Retina 対応: 1x/2x の PNG を生成して TIFF に合成)
echo "==> DMG 背景画像を生成"
swift Scripts/MakeDMGBackground.swift dist
tiffutil -cathidpicheck dist/dmg-background.png "dist/dmg-background@2x.png" \
    -out "$STAGING/.background/background.tiff"
rm -f dist/dmg-background.png "dist/dmg-background@2x.png"

# 作業イメージはホームディレクトリ配下に置かない: Finder が背景画像のブックマークに
# 作業イメージの絶対パスを書き込むため、dist/ 配下だと配布 DMG の .DS_Store に
# /Users/<ユーザー名>/... が残ってしまう(/tmp なら個人情報を含まない)
echo "==> DMG 生成(読み書き可能な作業イメージ)"
RW_DIR=$(mktemp -d /tmp/youyaku-dmg.XXXXXX)
RW_DMG="$RW_DIR/${APP_NAME}-rw.dmg"
trap 'rm -rf "$RW_DIR"' EXIT
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -fs HFS+ -format UDRW "$RW_DMG" >/dev/null
rm -rf "$STAGING"

# 一時マウント。マウントポイント名は衝突時に「Youyaku 1」等へ変わりうるので出力から拾う
ATTACH_OUT=$(hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen)
DEVICE=$(echo "$ATTACH_OUT" | head -n1 | awk '{print $1}')
MOUNT_POINT=$(echo "$ATTACH_OUT" | grep -o '/Volumes/.*$' | head -n1)
if [ -z "$DEVICE" ] || [ -z "$MOUNT_POINT" ]; then
    echo "!! 作業イメージのマウントに失敗しました" >&2
    exit 1
fi
VOL_NAME="${MOUNT_POINT#/Volumes/}"

# Finder にウィンドウの見た目を設定させる(結果はボリューム直下の .DS_Store に保存される)。
# ターミナルから Finder を操作するため、初回は「オートメーション」の許可ダイアログが出る。
echo "==> Finder でインストーラーウィンドウのレイアウトを設定"
sleep 2  # Finder がボリュームを認識するのを待つ
if ! osascript - "$VOL_NAME" "$APP_NAME" <<'EOS'
on run argv
    set volName to item 1 of argv
    set appName to item 2 of argv
    tell application "Finder"
        tell disk volName
            open
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            -- 内容領域 660x400(+タイトルバー)。MakeDMGBackground.swift のキャンバスと対応
            set bounds of container window to {200, 120, 860, 548}
            set opts to icon view options of container window
            set arrangement of opts to not arranged
            set icon size of opts to 128
            set text size of opts to 13
            set background picture of opts to file ".background:background.tiff"
            set position of item (appName & ".app") of container window to {165, 190}
            set position of item "Applications" of container window to {495, 190}
            update without registering applications
            delay 1
            close
        end tell
    end tell
end run
EOS
then
    hdiutil detach "$DEVICE" >/dev/null 2>&1 || true
    echo "!! Finder でのレイアウト設定に失敗しました。" >&2
    echo "   初回はターミナルに Finder の操作許可が必要です:" >&2
    echo "   システム設定 > プライバシーとセキュリティ > オートメーション > (ターミナル) > Finder" >&2
    exit 1
fi

# ボリュームアイコン(マウント時に Finder のサイドバー/デスクトップへ出るアイコン)。
# Finder はレイアウト書き込み時に既存の .VolumeIcon.icns を消すため、レイアウト設定の
# 「後」に置くこと(create-dmg も同じ順序)。SetFile は Command Line Tools 由来なので、
# 無ければアイコンなしのまま進める(致命的ではない)
if command -v SetFile >/dev/null 2>&1; then
    cp "$APP/Contents/Resources/AppIcon.icns" "$MOUNT_POINT/.VolumeIcon.icns"
    SetFile -c icnC "$MOUNT_POINT/.VolumeIcon.icns"
    SetFile -a C "$MOUNT_POINT"
else
    echo "==> SetFile が無いためボリュームアイコンはスキップ(xcode-select --install で入ります)"
fi

# Finder が .DS_Store を書き終えるのを待ってからアンマウント
for i in {1..10}; do
    [ -f "$MOUNT_POINT/.DS_Store" ] && break
    sleep 1
done
sync
DETACHED=0
for i in {1..6}; do
    if hdiutil detach "$DEVICE" >/dev/null 2>&1; then
        DETACHED=1
        break
    fi
    sleep 2
done
if [ "$DETACHED" -ne 1 ]; then
    echo "!! 作業イメージのアンマウントに失敗しました: $DEVICE" >&2
    exit 1
fi

echo "==> DMG 変換(配布用・読み取り専用): $DMG"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG" >/dev/null
rm -rf "$RW_DIR"

# ---- 3. DMG 署名(あれば)----
if [ -n "$DIST_ID" ]; then
    echo "==> DMG 署名: $DIST_ID"
    codesign --force --timestamp --sign "$DIST_ID" "$DMG"
fi

# ---- 4. DMG を公証 + staple ----
if [ -n "$PROFILE" ]; then
    echo "==> DMG を公証(notarytool) — 数分かかることがあります"
    if xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait; then
        echo "==> staple(公証チケットを DMG に貼り付け)"
        xcrun stapler staple "$DMG"
        if xcrun stapler validate "$DMG"; then
            echo "==> DMG 公証 + staple 完了"
        else
            echo "!! DMG の staple 検証に失敗しました" >&2
            exit 1
        fi
    else
        echo "!! DMG の公証に失敗しました。ログ: xcrun notarytool log <submission-id> --keychain-profile $PROFILE" >&2
        exit 1
    fi
else
    echo "==> 公証はスキップ(YOUYAKU_NOTARY_PROFILE 未設定)"
    echo "    配布前に公証が必要です。手順:"
    echo "      1) xcrun notarytool store-credentials youyaku-notary --apple-id <ID> --team-id <TEAMID> --password <App用パスワード>"
    echo "      2) export YOUYAKU_NOTARY_PROFILE=youyaku-notary && ./build.sh --dist"
fi

# ---- 5. 更新フィード(appcast.xml)を生成 ----
# DMG の実体は GitHub Releases に置く(docs/RELEASE.md「リリースごとの手順」で手動アップロード)。
# ここで作るのは Pages に置くフィードだけ。フィード URL(アプリの SUFeedURL)を Pages 側に
# 固定しておくと、将来 DMG の置き場所を変えてもアプリを作り直さずに追随できる。
#
# 未公証の DMG は macOS 15 以降で起動できず配布してはいけないため、公証していないときは
# フィードも作らない(壊れた更新を利用者へ流さない)。
PUBLISH_DIR="http_dist/download"
if [ -z "$PROFILE" ]; then
    echo "==> appcast.xml の生成はスキップ(未公証の DMG は配布できません)。"
    echo "    公開用に生成するには YOUYAKU_NOTARY_PROFILE を設定して公証を通してください。"
    echo "==> DMG: $DMG"
    exit 0
fi

SIGN_UPDATE="Vendor/sparkle-bin/sign_update"
if [ ! -x "$SIGN_UPDATE" ]; then
    echo "!! $SIGN_UPDATE がありません。./Scripts/fetch-vendor.sh を実行してください。" >&2
    exit 1
fi

# Sparkle は appcast の EdDSA 署名で DMG の真正性を検証する。秘密鍵はキーチェーンにあり、
# 対応する公開鍵は Info.plist の SUPublicEDKey に埋め込まれている(Scripts/setup-sparkle-keys.sh)。
# 署名を http_dist の更新より先に取る: 失敗したときに中途半端なフィードを残さないため。
echo "==> DMG に EdDSA 署名(Sparkle)"
if ! SIGNATURE=$("$SIGN_UPDATE" "$DMG"); then
    echo "!! sign_update に失敗しました。署名鍵が無い可能性があります。" >&2
    echo "   初回のみ ./Scripts/setup-sparkle-keys.sh を実行して鍵を作成してください。" >&2
    exit 1
fi
# 出力は `sparkle:edSignature="..." length="..."` の 1 行。想定外なら空の enclosure を作らず止める
case "$SIGNATURE" in
    *'sparkle:edSignature="'*'length="'*) ;;
    *)
        echo "!! sign_update の出力を解釈できませんでした: $SIGNATURE" >&2
        exit 1
        ;;
esac

BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")
MIN_OS=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$APP/Contents/Info.plist")
PUB_DATE=$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")

# タグ v<version> の下に安定名 Youyaku.dmg でアップロードする(Scripts/publish-release.sh)。
# タグが版を分けるのでファイル名は固定でよく、サイト側は
# /releases/latest/download/Youyaku.dmg という版に依らないリンクを使える。
ENCLOSURE_URL="https://github.com/${GITHUB_REPO}/releases/download/v${VERSION}/${APP_NAME}.dmg"

# リリースノート(任意)。置いてあればアップデート画面に表示される
NOTES_TAG=""
if [ -f "$PUBLISH_DIR/notes/${VERSION}.html" ]; then
    NOTES_TAG="      <sparkle:releaseNotesLink>https://youyaku.hinoshiba.com/download/notes/${VERSION}.html</sparkle:releaseNotesLink>"
fi

mkdir -p "$PUBLISH_DIR"
cat > "$PUBLISH_DIR/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<!-- Scripts/make-dmg.sh が生成する。手で編集しない -->
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Youyaku</title>
    <link>https://youyaku.hinoshiba.com/download/appcast.xml</link>
    <description>Youyaku (macOS) の更新フィード</description>
    <language>ja</language>
    <item>
      <title>${VERSION}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <sparkle:version>${BUILD}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${MIN_OS}</sparkle:minimumSystemVersion>
${NOTES_TAG}
      <enclosure url="${ENCLOSURE_URL}" type="application/octet-stream" ${SIGNATURE} />
    </item>
  </channel>
</rss>
EOF
# NOTES_TAG が空のときに残る空行を落とす(フィードの見た目を保つだけで、動作には影響しない)
sed -i '' '/^$/d' "$PUBLISH_DIR/appcast.xml"

printf '%s\n' "$VERSION" > "$PUBLISH_DIR/version.txt"
echo "==> 更新フィードを生成: $PUBLISH_DIR/appcast.xml (v$VERSION → $ENCLOSURE_URL)"

echo "==> DMG: $DMG"
echo
echo "次の手順(docs/RELEASE.md「リリースごとの手順」):"
echo "  1) cp $DMG dist/${APP_NAME}.dmg"
echo "  2) GitHub Web UI で Release(タグ v$VERSION)を作り dist/${APP_NAME}.dmg を上げる"
echo "     (gh があれば ./Scripts/publish-release.sh でも可)"
echo "  3) git add http_dist/download/appcast.xml http_dist/download/version.txt"
echo "     git commit && git push               … Pages にフィードを反映"
