#!/bin/zsh
# Sparkle(アプリ内アップデート)の EdDSA 署名鍵を作成する。**リリース担当者が一度だけ**実行する。
#
#   ./Scripts/setup-sparkle-keys.sh
#
# 秘密鍵はログインキーチェーンに保存され、リポジトリには入らない。表示された公開鍵を
# Info.plist の SUPublicEDKey に貼ると、アプリはその鍵で署名された DMG しか受け付けなくなる。
#
# ★ 秘密鍵は必ずバックアップすること。失うと、既存の利用者へアップデートを配れなくなる
#   (公開鍵を変えた新版を配っても、旧版のアプリはそれを検証できず更新できない)。
set -e
cd "$(dirname "$0")/.."

GENERATE_KEYS="Vendor/sparkle-bin/generate_keys"
if [ ! -x "$GENERATE_KEYS" ]; then
    echo "==> Sparkle のツールを取得"
    ./Scripts/fetch-vendor.sh
fi

echo "==> 署名鍵を確認/作成(キーチェーンへのアクセスを求められたら許可してください)"
# generate_keys は鍵が無ければ作り、あれば既存の公開鍵を表示する(冪等)
"$GENERATE_KEYS"

echo
echo "----------------------------------------------------------------------"
echo "上に表示された <string>...</string> の公開鍵を Info.plist に反映してください:"
echo
echo "  /usr/libexec/PlistBuddy -c \"Set :SUPublicEDKey <公開鍵>\" Info.plist"
echo
echo "現在の Info.plist の値:"
echo "  SUPublicEDKey = $(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Info.plist 2>/dev/null || echo '(未設定)')"
echo
echo "★ 秘密鍵のバックアップを忘れずに(失うとアップデートを配れなくなります):"
echo "    $GENERATE_KEYS -x sparkle-private-key.txt   # 書き出したら安全な場所へ移し、削除する"
echo "----------------------------------------------------------------------"
