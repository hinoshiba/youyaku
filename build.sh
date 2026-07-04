#!/bin/zsh
# Youyaku.app をビルドして dist/ に生成する
#   ./build.sh          … 開発ビルド(ローカル署名 or ad-hoc。手元での動作確認用)
#   ./build.sh --dist   … 配布ビルド(Developer ID 署名 + Hardened Runtime)→ DMG 生成(+可能なら公証)
set -e
cd "$(dirname "$0")"

MODE="dev"
if [ "$1" = "--dist" ] || [ "$1" = "dist" ]; then
    MODE="dist"
fi

echo "==> ベンダー依存(llama.xcframework)を確認"
./Scripts/fetch-vendor.sh

echo "==> Swift ビルド"
swift build -c release

APP=dist/Youyaku.app
FRAMEWORK_SRC=Vendor/build-apple/llama.xcframework/macos-arm64_x86_64/llama.framework
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

cp .build/release/Youyaku "$APP/Contents/MacOS/Youyaku"
cp Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# 第三者ライセンス表記を同梱(llama.cpp MIT 等の表示義務を満たす)
cp THIRD_PARTY_LICENSES.txt "$APP/Contents/Resources/THIRD_PARTY_LICENSES.txt"

echo "==> llama.framework を埋め込み"
cp -R "$FRAMEWORK_SRC" "$APP/Contents/Frameworks/"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Youyaku" 2>/dev/null || true

if [ ! -f dist/AppIcon.icns ]; then
    echo "==> アイコン生成"
    swift Scripts/MakeIcon.swift dist
    iconutil -c icns dist/Youyaku.iconset -o dist/AppIcon.icns
fi
cp dist/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# ---- 署名 ----
if [ "$MODE" = "dist" ]; then
    # 配布ビルド: Developer ID Application 証明書で署名し、Hardened Runtime + タイムスタンプを付与する
    # (どちらも公証(notarization)の必須要件)。証明書は環境変数 YOUYAKU_DIST_IDENTITY で明示指定も可。
    DIST_ID="${YOUYAKU_DIST_IDENTITY:-}"
    if [ -z "$DIST_ID" ]; then
        # 複数の Developer ID Application 証明書がある場合は取り違えを避けるため明示指定を要求する
        DID_COUNT=$(security find-identity -v -p codesigning 2>/dev/null | grep -c 'Developer ID Application') || true
        if [ "${DID_COUNT:-0}" -gt 1 ]; then
            echo "!! Developer ID Application 証明書が複数あります。YOUYAKU_DIST_IDENTITY で明示指定してください:" >&2
            security find-identity -v -p codesigning 2>/dev/null | grep 'Developer ID Application' >&2
            exit 1
        fi
        DIST_ID=$(security find-identity -v -p codesigning 2>/dev/null \
            | grep -o '"Developer ID Application:[^"]*"' | head -1 | tr -d '"')
    fi
    if [ -z "$DIST_ID" ]; then
        echo "!! 配布ビルドには Developer ID Application 証明書が必要です。" >&2
        echo "   Apple Developer Program 登録後、Developer ID 証明書をキーチェーンに追加してください。" >&2
        echo "   明示指定する場合: YOUYAKU_DIST_IDENTITY='Developer ID Application: 名前 (TEAMID)' ./build.sh --dist" >&2
        exit 1
    fi
    echo "==> 配布署名(Developer ID + Hardened Runtime): $DIST_ID"
    # inside-out に署名する(埋め込みフレームワーク → アプリ本体の順)。
    codesign --force --options runtime --timestamp \
        --sign "$DIST_ID" "$APP/Contents/Frameworks/llama.framework"
    codesign --force --options runtime --timestamp \
        --entitlements "Youyaku.entitlements" \
        --sign "$DIST_ID" "$APP"
    codesign --verify --strict --verbose=2 "$APP"
    # rpath 検証: これが無いと公証は通っても起動時に dyld: Library not loaded で落ちる(最も切り分けにくい失敗)
    if ! otool -l "$APP/Contents/MacOS/Youyaku" | grep -q "@executable_path/../Frameworks"; then
        echo "!! rpath(@executable_path/../Frameworks)が見つかりません。埋め込みフレームワークを読めず起動に失敗します。" >&2
        exit 1
    fi
    echo "==> 署名検証 OK"

    echo "==> DMG 生成 + 公証"
    # make-dmg.sh が同じ証明書を使うよう明示的に引き継ぐ
    export YOUYAKU_DIST_IDENTITY="$DIST_ID"
    ./Scripts/make-dmg.sh "$APP"
else
    # 開発ビルド: ローカル署名証明書があればそれを使う(再ビルドしてもアクセシビリティ等の許可が維持される)。
    # なければ ad-hoc 署名(再ビルドごとに許可の再設定が必要)
    CERT_NAME="Youyaku Local Signing"
    SIGN_KEYCHAIN="$HOME/Library/Keychains/youyaku-codesign.keychain-db"
    SIGN_PASS_FILE="$HOME/.config/youyaku/keychain-pass"
    SIGN_ID="-"
    if [ -f "$SIGN_PASS_FILE" ] && security find-identity -v -p codesigning "$SIGN_KEYCHAIN" 2>/dev/null | grep -q "$CERT_NAME"; then
        security unlock-keychain -p "$(cat "$SIGN_PASS_FILE")" "$SIGN_KEYCHAIN" 2>/dev/null || true
        SIGN_ID="$CERT_NAME"
        echo "==> 署名: $CERT_NAME(再ビルドしても許可が維持されます)"
    else
        echo "==> 署名: ad-hoc(再ビルドごとにアクセシビリティ許可の再設定が必要)"
        echo "    恒久化するには一度だけ実行: ./Scripts/setup-signing.sh"
    fi
    codesign --force --sign "$SIGN_ID" "$APP/Contents/Frameworks/llama.framework"
    codesign --force --sign "$SIGN_ID" "$APP"
fi

echo "==> 完成: $APP"
