#!/bin/zsh
# Youyaku.app をビルドして dist/ に生成する
set -e
cd "$(dirname "$0")"

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

# ローカル署名証明書があればそれを使う(再ビルドしてもアクセシビリティ等の許可が維持される)。
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

echo "==> 完成: $APP"
