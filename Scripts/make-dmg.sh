#!/bin/zsh
# 署名済み Youyaku.app から配布用 DMG を作成し、可能なら公証(notarize)+staple する。
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

# ---- 5. HP 直販用に http_dist へ配置 ----
# 公証 + staple 済みの DMG だけを公開ディレクトリへ置く。未公証の DMG は macOS 15 以降で起動できず、
# 公開してはいけないため、YOUYAKU_NOTARY_PROFILE 未設定時はここをスキップする。
# wrangler は http_dist をローカルから配信するので、ここに置けば次の deploy でそのまま配布される。
# 版が変わってもサイトのリンク(/download/Youyaku.dmg)を固定にするため、安定名でコピーする。
PUBLISH_DIR="http_dist/download"
PUBLISH_DMG="$PUBLISH_DIR/${APP_NAME}.dmg"
if [ -n "$PROFILE" ]; then
    mkdir -p "$PUBLISH_DIR"
    cp "$DMG" "$PUBLISH_DMG"
    printf '%s\n' "$VERSION" > "$PUBLISH_DIR/version.txt"
    echo "==> HP 配布用に配置: $PUBLISH_DMG (v$VERSION)"

    # Cloudflare Workers の静的アセットは 1 ファイル 25 MiB が上限。超えると deploy / 配信が失敗する。
    DMG_BYTES=$(stat -f%z "$PUBLISH_DMG" 2>/dev/null || echo 0)
    LIMIT=$((25 * 1024 * 1024))
    if [ "${DMG_BYTES:-0}" -gt "$LIMIT" ]; then
        echo "!! 警告: DMG が $((DMG_BYTES / 1024 / 1024)) MiB あり、Cloudflare の 1 ファイル上限(25 MiB)を超えています。" >&2
        echo "   このままでは wrangler deploy か配信が失敗します。GitHub Releases 等の外部ホスティングに切り替え、" >&2
        echo "   index.html のダウンロードリンクをその URL に向けてください。" >&2
    fi
else
    echo "==> http_dist への配置はスキップ(未公証の DMG は配布できません)。"
    echo "    公開用に配置するには YOUYAKU_NOTARY_PROFILE を設定して公証を通してください。"
fi

echo "==> DMG: $DMG"
