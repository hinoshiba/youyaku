#!/bin/zsh
# Koe.app をビルドして dist/ に生成する
set -e
cd "$(dirname "$0")"

echo "==> ベンダー依存(llama.xcframework)を確認"
./Scripts/fetch-vendor.sh

echo "==> Swift ビルド"
swift build -c release

APP=dist/Koe.app
FRAMEWORK_SRC=Vendor/build-apple/llama.xcframework/macos-arm64_x86_64/llama.framework
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

cp .build/release/Koe "$APP/Contents/MacOS/Koe"
cp Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> llama.framework を埋め込み"
cp -R "$FRAMEWORK_SRC" "$APP/Contents/Frameworks/"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Koe" 2>/dev/null || true

if [ ! -f dist/AppIcon.icns ]; then
    echo "==> アイコン生成"
    swift Scripts/MakeIcon.swift dist
    iconutil -c icns dist/Koe.iconset -o dist/AppIcon.icns
fi
cp dist/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "==> 署名(ad-hoc)"
codesign --force --sign - "$APP/Contents/Frameworks/llama.framework"
codesign --force --sign - "$APP"

echo "==> 完成: $APP"
