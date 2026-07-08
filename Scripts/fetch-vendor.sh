#!/bin/zsh
# llama.cpp の公式ビルド済み xcframework を取得する。
# 再取得可能なバイナリのため git にはコミットせず、このスクリプトで取り寄せる。
set -e
cd "$(dirname "$0")/.."

# llama.cpp のリリースタグ。GitHub のリリース資産は権限者が後から差し替え可能なため、
# タグ固定だけでは同一性を担保できない。真正性は下の SHA-256 照合で担保する。
# 更新する場合は Sources/Youyaku/LLM/LlamaEngine.swift が使う API との整合を確認のうえ、
# URL(タグ)・LLAMA_SHA256・.llama-version の3点セットを揃えること(docs/RELEASE.md 参照)。
LLAMA_VERSION="b9859"
ASSET="llama-${LLAMA_VERSION}-xcframework.zip"
URL="https://github.com/ggml-org/llama.cpp/releases/download/${LLAMA_VERSION}/${ASSET}"
# 上記リリース資産の SHA-256(取得時に実測した値で固定。改竄・差し替え検知用)
LLAMA_SHA256="1fcf5b1ba2fd0890c5bbbc5932e1d1893f495e3de3a13331d05384f3c6e25620"

FRAMEWORK="Vendor/build-apple/llama.xcframework"
HEADER="${FRAMEWORK}/macos-arm64_x86_64/llama.framework/Headers/llama.h"
VERSION_FILE="Vendor/build-apple/.llama-version"

if [ -f "$HEADER" ]; then
    if [ ! -f "$VERSION_FILE" ]; then
        # .llama-version 導入前に取得した Vendor への救済: 現行版とみなして記録する
        printf '%s\n' "$LLAMA_VERSION" > "$VERSION_FILE"
    fi
    if [ "$(cat "$VERSION_FILE")" = "$LLAMA_VERSION" ]; then
        echo "==> llama.xcframework は取得済み (${LLAMA_VERSION})"
        exit 0
    fi
    echo "==> llama.xcframework のバージョンが古い ($(cat "$VERSION_FILE") → ${LLAMA_VERSION})。再取得する"
fi

echo "==> llama.xcframework (${LLAMA_VERSION}, 約 242MB) をダウンロード"
mkdir -p Vendor
DL_DIR="$(mktemp -d -t youyaku-llama)"
trap 'rm -rf "$DL_DIR"' EXIT
TMP="$DL_DIR/$ASSET"

curl -fL --retry 3 -o "$TMP" "$URL"

# SHA-256 照合(ダウンロード物がピン留めした資産と一致するか検証する)
ACTUAL_SHA256="$(shasum -a 256 "$TMP" | awk '{print $1}')"
if [ "$ACTUAL_SHA256" != "$LLAMA_SHA256" ]; then
    echo "!! SHA-256 が一致しません。改竄または上流のリリース資産差し替えの可能性があります。" >&2
    echo "   期待値: $LLAMA_SHA256" >&2
    echo "   実測値: $ACTUAL_SHA256" >&2
    exit 1
fi

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

# 取得済み判定に使うバージョンを記録(ヘッダ存在だけではタグ更新時に取りこぼすため)
printf '%s\n' "$LLAMA_VERSION" > "$VERSION_FILE"
echo "==> 完了: $FRAMEWORK"
