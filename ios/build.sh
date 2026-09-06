#!/bin/zsh
# iOS 版 Youyaku をシミュレータ向けにビルドし、任意で起動する。
# 事前に一度だけ(要管理者パスワード):
#   sudo xcodebuild -license accept
#   sudo xcode-select -s /Applications/Xcode.app
set -euo pipefail
cd "$(dirname "$0")"

DEVICE="${1:-iPhone 16}"

../Scripts/fetch-vendor.sh --ios

echo "==> Xcode プロジェクトを生成(project.yml から)"
xcodegen generate

echo "==> シミュレータ向けビルド: $DEVICE"
xcodebuild \
  -project Youyaku.xcodeproj \
  -scheme Youyaku \
  -configuration Debug \
  -destination "platform=iOS Simulator,name=$DEVICE" \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  build | tail -20

APP=$(find build/Build/Products -name "Youyaku.app" -maxdepth 3 | head -1)
echo "==> 完成: $APP"

if [ "${2:-}" = "run" ]; then
    echo "==> シミュレータを起動してインストール"
    xcrun simctl boot "$DEVICE" 2>/dev/null || true
    open -a Simulator
    sleep 3
    xcrun simctl install booted "$APP"
    xcrun simctl launch booted com.hinoshiba.youyaku
fi
