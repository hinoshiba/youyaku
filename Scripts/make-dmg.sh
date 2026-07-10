#!/bin/zsh
# 署名済み Youyaku.app から配布用 DMG を作成し、可能なら公証(notarize)+staple したうえで、
# Sparkle の更新フィード(http_dist/download/appcast.xml)を生成する。
# DMG の実体は GitHub Releases に置くため、ここでは配置しない(→ Scripts/publish-release.sh)。
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
echo "==> DMG ステージング作成"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
# ドラッグ&ドロップでインストールできるよう /Applications へのシンボリックリンクを置く
ln -s /Applications "$STAGING/Applications"

echo "==> DMG 生成: $DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

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
# DMG の実体は GitHub Releases に置く(`Scripts/publish-release.sh` がアップロードする)。
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
echo "  1) ./Scripts/publish-release.sh          … GitHub Releases に DMG を上げる"
echo "  2) git add http_dist/download/appcast.xml http_dist/download/version.txt Info.plist ios/project.yml"
echo "     git commit && git push               … Pages にフィードを反映"
