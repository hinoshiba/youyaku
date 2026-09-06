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

# Sparkle(アプリ内アップデート)の公開鍵が入っていない配布物は、更新機構が死んだまま出回る。
# 長いビルドと公証を走らせる前にここで止める(開発ビルドは鍵なしでも動く。更新機構が無効になるだけ)。
if [ "$MODE" = "dist" ]; then
    PUBLIC_ED_KEY=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" Info.plist 2>/dev/null) || PUBLIC_ED_KEY=""
    if [ -z "$PUBLIC_ED_KEY" ] || [ "$PUBLIC_ED_KEY" = "REPLACE_WITH_SPARKLE_PUBLIC_ED_KEY" ]; then
        echo "!! Info.plist の SUPublicEDKey が未設定です。アプリ内アップデートの署名検証ができません。" >&2
        echo "   初回のみ次を実行し、出力された公開鍵で Info.plist の SUPublicEDKey を置き換えてください:" >&2
        echo "     ./Scripts/setup-sparkle-keys.sh" >&2
        exit 1
    fi
fi

echo "==> ベンダー依存(llama.xcframework / Sparkle.xcframework)を確認"
./Scripts/fetch-vendor.sh

echo "==> Swift ビルド"
if [ "$MODE" = "dist" ]; then
    # 配布ビルドは universal(arm64 + x86_64)。Intel Mac でも動く DMG を作る。
    # --arch を複数指定すると成果物は .build/apple/Products/Release/ に置かれる。
    swift build -c release --arch arm64 --arch x86_64
    BIN=.build/apple/Products/Release/Youyaku
else
    # 開発ビルドはホストのアーキテクチャのみ(速い)
    swift build -c release
    BIN=.build/release/Youyaku
fi

APP=dist/Youyaku.app
FRAMEWORK_SRC=Vendor/build-apple/llama.xcframework/macos-arm64_x86_64/llama.framework
SPARKLE_SRC=Vendor/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework
SPARKLE_FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

cp "$BIN" "$APP/Contents/MacOS/Youyaku"

if [ "$MODE" = "dist" ]; then
    # universal 検証: 片アーキテクチャだけの成果物を配布しないためのガード
    ARCHS=$(lipo -archs "$APP/Contents/MacOS/Youyaku")
    case "$ARCHS" in
        *arm64*x86_64*|*x86_64*arm64*) echo "==> universal 検証 OK: $ARCHS" ;;
        *)
            echo "!! universal ビルドになっていません(含まれるアーキテクチャ: $ARCHS)。" >&2
            echo "   配布ビルドは arm64 と x86_64 の両方を含む必要があります。" >&2
            exit 1
            ;;
    esac
fi
cp Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# 第三者ライセンス表記を同梱(llama.cpp MIT 等の表示義務を満たす)
cp THIRD_PARTY_LICENSES.txt "$APP/Contents/Resources/THIRD_PARTY_LICENSES.txt"

echo "==> llama.framework を埋め込み"
cp -R "$FRAMEWORK_SRC" "$APP/Contents/Frameworks/"

echo "==> Sparkle.framework を埋め込み"
cp -R "$SPARKLE_SRC" "$APP/Contents/Frameworks/"
# XPC サービスは App Sandbox 下のアプリ専用(Sparkle の Sandboxing.md)。本アプリは非サンドボックスなので
# 同梱しない。残すと署名・公証の対象が増えるだけで、更新時には使われない。
rm -rf "$SPARKLE_FRAMEWORK/Versions/B/XPCServices" "$SPARKLE_FRAMEWORK/XPCServices"

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
    echo "==> 配布署名(Developer ID + Hardened Runtime)"
    # inside-out に署名する(埋め込みフレームワークの中の実行ファイル → フレームワーク → アプリ本体の順)。
    # Sparkle.framework は中に実行ファイル(Autoupdate)とアプリ(Updater.app)を抱えており、
    # 先にそれらを署名しないとフレームワークの署名が壊れる(公証も通らない)。
    codesign --force --options runtime --timestamp \
        --sign "$DIST_ID" "$SPARKLE_FRAMEWORK/Versions/B/Autoupdate"
    codesign --force --options runtime --timestamp \
        --sign "$DIST_ID" "$SPARKLE_FRAMEWORK/Versions/B/Updater.app"
    codesign --force --options runtime --timestamp \
        --sign "$DIST_ID" "$SPARKLE_FRAMEWORK"
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
    # Credential-free by default. An already-installed development identity may
    # be selected explicitly when stable local permissions are needed.
    SIGN_ID="${YOUYAKU_DEV_IDENTITY:--}"
    echo "==> 開発用署名"
    codesign --force --sign "$SIGN_ID" "$SPARKLE_FRAMEWORK/Versions/B/Autoupdate"
    codesign --force --sign "$SIGN_ID" "$SPARKLE_FRAMEWORK/Versions/B/Updater.app"
    codesign --force --sign "$SIGN_ID" "$SPARKLE_FRAMEWORK"
    codesign --force --sign "$SIGN_ID" "$APP/Contents/Frameworks/llama.framework"
    codesign --force --sign "$SIGN_ID" "$APP"
fi

echo "==> 完成: $APP"
