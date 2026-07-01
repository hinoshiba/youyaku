#!/bin/zsh
# llama.cpp の公式ビルド済み xcframework を取得する。
# 再取得可能なバイナリのため git にはコミットせず、このスクリプトで取り寄せる。
set -e
cd "$(dirname "$0")/.."

# llama.cpp のリリースタグ(GitHub のリリース資産はタグ単位で不変)。
# 更新する場合は Sources/Koe/LLM/LlamaEngine.swift が使う API との整合を確認すること。
LLAMA_VERSION="b9859"
ASSET="llama-${LLAMA_VERSION}-xcframework.zip"
URL="https://github.com/ggml-org/llama.cpp/releases/download/${LLAMA_VERSION}/${ASSET}"

FRAMEWORK="Vendor/build-apple/llama.xcframework"
HEADER="${FRAMEWORK}/macos-arm64_x86_64/llama.framework/Headers/llama.h"

if [ -f "$HEADER" ]; then
    echo "==> llama.xcframework は取得済み (${LLAMA_VERSION})"
    exit 0
fi

echo "==> llama.xcframework (${LLAMA_VERSION}, 約 242MB) をダウンロード"
mkdir -p Vendor
TMP="$(mktemp -t koe-llama).zip"
trap 'rm -f "$TMP"' EXIT

curl -fL --retry 3 -o "$TMP" "$URL"

# zip として妥当か簡易チェック(HTML エラーページ等を弾く)
if ! unzip -t "$TMP" >/dev/null 2>&1; then
    echo "!! ダウンロードしたファイルが壊れています。URL を確認してください: $URL" >&2
    exit 1
fi

echo "==> 展開"
rm -rf "$FRAMEWORK"
unzip -q -o "$TMP" -d Vendor

if [ ! -f "$HEADER" ]; then
    echo "!! 展開後に想定した構造が見つかりません: $HEADER" >&2
    exit 1
fi

echo "==> 完了: $FRAMEWORK"
