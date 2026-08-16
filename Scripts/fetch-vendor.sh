#!/bin/zsh
# ビルドに必要な公式ビルド済みバイナリ(llama.cpp / Sparkle)を取得する。
# `--ios` を指定した場合は iOS ビルドに不要な Sparkle を取得しない。
# 再取得可能なバイナリのため git にはコミットせず、このスクリプトで取り寄せる。
#
# いずれも「リリースタグ + SHA-256」でピン留めする。GitHub のリリース資産は権限者が後から
# 差し替え可能なため、タグ固定だけでは同一性を担保できない。真正性は SHA-256 照合で担保する。
# 更新する場合は URL(タグ)・SHA-256・バージョンファイルの3点セットを揃えること(docs/RELEASE.md 参照)。
set -e
cd "$(dirname "$0")/.."

MODE="${1:-all}"
if [ "$MODE" != "all" ] && [ "$MODE" != "--ios" ]; then
    echo "使い方: $0 [--ios]" >&2
    exit 2
fi

# llama.cpp(推論エンジン)。更新時は Sources/Youyaku/LLM/LlamaEngine.swift が使う API との整合を確認する。
LLAMA_VERSION="b9859"
LLAMA_SHA256="1fcf5b1ba2fd0890c5bbbc5932e1d1893f495e3de3a13331d05384f3c6e25620"

# Sparkle(直販版の自動更新)。SPM 用の zip には Sparkle.xcframework と、
# リリース時に使う署名/appcast 生成ツール(bin/)の両方が入っている。
SPARKLE_VERSION="2.9.4"
SPARKLE_SHA256="cb6fdbdc8884f15d62a616e79face92b08322410fd2d425edc6596ccbf4ba3b0"

DL_DIR="$(mktemp -d -t youyaku-vendor)"
trap 'rm -rf "$DL_DIR"' EXIT

# 資産をダウンロードして SHA-256 を照合し、zip として妥当かまで確認する。
#   fetch_asset <URL> <期待するSHA-256> <出力パス>
fetch_asset() {
    local url="$1" expected="$2" out="$3"
    curl -fL --retry 3 -o "$out" "$url"

    # SHA-256 照合(ダウンロード物がピン留めした資産と一致するか検証する)
    local actual
    actual="$(shasum -a 256 "$out" | awk '{print $1}')"
    if [ "$actual" != "$expected" ]; then
        echo "!! SHA-256 が一致しません。改竄または上流のリリース資産差し替えの可能性があります。" >&2
        echo "   対象  : $url" >&2
        echo "   期待値: $expected" >&2
        echo "   実測値: $actual" >&2
        exit 1
    fi

    # zip として妥当か簡易チェック(HTML エラーページ等を弾く)
    if ! unzip -t "$out" >/dev/null 2>&1; then
        echo "!! ダウンロードしたファイルが壊れています。URL を確認してください: $url" >&2
        exit 1
    fi
}

# ---- llama.cpp ----
FRAMEWORK="Vendor/build-apple/llama.xcframework"
HEADER="${FRAMEWORK}/macos-arm64_x86_64/llama.framework/Headers/llama.h"
VERSION_FILE="Vendor/build-apple/.llama-version"

fetch_llama() {
    if [ -f "$HEADER" ]; then
        if [ ! -f "$VERSION_FILE" ]; then
            # .llama-version 導入前に取得した Vendor への救済: 現行版とみなして記録する
            printf '%s\n' "$LLAMA_VERSION" > "$VERSION_FILE"
        fi
        if [ "$(cat "$VERSION_FILE")" = "$LLAMA_VERSION" ]; then
            echo "==> llama.xcframework は取得済み (${LLAMA_VERSION})"
            return 0
        fi
        echo "==> llama.xcframework のバージョンが古い ($(cat "$VERSION_FILE") → ${LLAMA_VERSION})。再取得する"
    fi

    local asset="llama-${LLAMA_VERSION}-xcframework.zip"
    local url="https://github.com/ggml-org/llama.cpp/releases/download/${LLAMA_VERSION}/${asset}"

    echo "==> llama.xcframework (${LLAMA_VERSION}, 約 242MB) をダウンロード"
    mkdir -p Vendor
    fetch_asset "$url" "$LLAMA_SHA256" "$DL_DIR/$asset"

    echo "==> 展開"
    rm -rf "$FRAMEWORK"
    unzip -q -o "$DL_DIR/$asset" -d Vendor

    if [ ! -f "$HEADER" ]; then
        echo "!! 展開後に想定した構造が見つかりません: $HEADER" >&2
        exit 1
    fi

    # 取得済み判定に使うバージョンを記録(ヘッダ存在だけではタグ更新時に取りこぼすため)
    printf '%s\n' "$LLAMA_VERSION" > "$VERSION_FILE"
    echo "==> 完了: $FRAMEWORK"
}

# ---- Sparkle ----
#   Vendor/Sparkle.xcframework … アプリに埋め込むフレームワーク(Package.swift の binaryTarget)
#   Vendor/sparkle-bin/        … generate_keys / sign_update(鍵生成と appcast の EdDSA 署名に使う)
SPARKLE_FRAMEWORK="Vendor/Sparkle.xcframework"
SPARKLE_BINARY="${SPARKLE_FRAMEWORK}/macos-arm64_x86_64/Sparkle.framework/Versions/B/Sparkle"
SPARKLE_VERSION_FILE="Vendor/.sparkle-version"

fetch_sparkle() {
    if [ -f "$SPARKLE_BINARY" ] && [ -f "$SPARKLE_VERSION_FILE" ] \
        && [ "$(cat "$SPARKLE_VERSION_FILE")" = "$SPARKLE_VERSION" ]; then
        echo "==> Sparkle.xcframework は取得済み (${SPARKLE_VERSION})"
        return 0
    fi

    local asset="Sparkle-for-Swift-Package-Manager.zip"
    local url="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/${asset}"

    echo "==> Sparkle (${SPARKLE_VERSION}, 約 11MB) をダウンロード"
    mkdir -p Vendor
    fetch_asset "$url" "$SPARKLE_SHA256" "$DL_DIR/$asset"

    echo "==> 展開"
    local extract="$DL_DIR/sparkle"
    rm -rf "$extract"
    unzip -q -o "$DL_DIR/$asset" -d "$extract"
    if [ ! -f "$extract/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework/Versions/B/Sparkle" ] \
        || [ ! -x "$extract/bin/sign_update" ]; then
        echo "!! 展開後に想定した構造が見つかりません: $extract" >&2
        exit 1
    fi

    rm -rf "$SPARKLE_FRAMEWORK" Vendor/sparkle-bin Vendor/sparkle-LICENSE
    mv "$extract/Sparkle.xcframework" "$SPARKLE_FRAMEWORK"
    mv "$extract/bin" Vendor/sparkle-bin
    # 帰属表示の原本。THIRD_PARTY_LICENSES.txt の記載を更新するときに突き合わせる
    mv "$extract/LICENSE" Vendor/sparkle-LICENSE

    printf '%s\n' "$SPARKLE_VERSION" > "$SPARKLE_VERSION_FILE"
    echo "==> 完了: $SPARKLE_FRAMEWORK"
}

fetch_llama
if [ "$MODE" != "--ios" ]; then
    fetch_sparkle
fi
