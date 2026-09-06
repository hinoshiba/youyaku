#!/bin/zsh
# アプリのバージョンを一括で上げる。
#
#   使い方: ./Scripts/bump-version.sh <new-version>   例: ./Scripts/bump-version.sh 1.1.0
#
# 書き換える対象(macOS / iOS で常に同じ版数を保つ):
#   - Info.plist(macOS)  : CFBundleShortVersionString = <new-version>、CFBundleVersion は +1
#   - ios/project.yml     : MARKETING_VERSION / CURRENT_PROJECT_VERSION を macOS 側と同期
#   - ios/Youyaku.xcodeproj: ローカルXcodeで開く追跡済みプロジェクトを再生成
set -euo pipefail
cd "$(dirname "$0")/.."

NEW_VERSION="${1:-}"
if [ -z "$NEW_VERSION" ]; then
    echo "使い方: ./Scripts/bump-version.sh <new-version>   例: ./Scripts/bump-version.sh 1.1.0" >&2
    exit 1
fi
if ! [[ "$NEW_VERSION" =~ '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' ]]; then
    echo "!! バージョンは X.Y.Z 形式で指定してください: $NEW_VERSION" >&2
    exit 1
fi
if ! command -v xcodegen >/dev/null 2>&1; then
    echo "!! 追跡済みiOSプロジェクトの更新にXcodeGenが必要です: brew install xcodegen" >&2
    exit 1
fi

PLIST="Info.plist"
YML="ios/project.yml"

# ---- macOS: Info.plist(PlistBuddy で構造を壊さず書き換える)----
CURRENT_BUILD="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")"
NEW_BUILD=$((CURRENT_BUILD + 1))
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD" "$PLIST"

# ---- iOS: project.yml(YAML は PlistBuddy が使えないため、該当キーの行だけを sed で置換する)----
sed -i '' -E "s|^([[:space:]]*MARKETING_VERSION:).*|\\1 \"${NEW_VERSION}\"|" "$YML"
sed -i '' -E "s|^([[:space:]]*CURRENT_PROJECT_VERSION:).*|\\1 \"${NEW_BUILD}\"|" "$YML"
(cd ios && xcodegen generate)

# ---- 結果表示 ----
echo "==> バージョンを更新しました"
echo "    ${PLIST}:"
echo "      CFBundleShortVersionString = $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
echo "      CFBundleVersion            = $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
echo "    ${YML}:"
grep -E '^[[:space:]]*(MARKETING_VERSION|CURRENT_PROJECT_VERSION):' "$YML" | sed 's/^[[:space:]]*/      /'
