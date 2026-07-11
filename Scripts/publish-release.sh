#!/bin/zsh
# 公証済み DMG を GitHub Releases へ公開する(タグ v<version> にアセット Youyaku.dmg を上げる)。
#
# 既定の運用は docs/RELEASE.md「リリースごとの手順」のとおり GitHub Web UI での手動アップロード。
# このスクリプトは gh CLI が使える環境向けの任意の自動化で、同じことをコマンドで行う。
#
#   使い方: ./Scripts/publish-release.sh [--clobber]
#           --clobber … 同名アセットが既にあるとき上書きする(既定は中止)
#
# 事前に ./build.sh --dist(要 YOUYAKU_NOTARY_PROFILE)で DMG と appcast.xml を作っておくこと。
# 実行順の理由は docs/RELEASE.md「リリースごとの手順」を参照:
#   アセットを先に公開してから appcast.xml を push することで、
#   「更新は見えるのに DMG が 404」という時間帯を作らない。
set -e
cd "$(dirname "$0")/.."

CLOBBER=""
if [ "$1" = "--clobber" ]; then
    CLOBBER="--clobber"
fi

APP_NAME="Youyaku"
GITHUB_REPO="hinoshiba/youyaku"   # Scripts/make-dmg.sh の GITHUB_REPO と一致させること

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
TAG="v${VERSION}"
DMG="dist/${APP_NAME}-${VERSION}.dmg"

if ! command -v gh >/dev/null 2>&1; then
    echo "!! gh(GitHub CLI)が必要です: brew install gh && gh auth login" >&2
    exit 1
fi

if [ ! -f "$DMG" ]; then
    echo "!! DMG がありません: $DMG" >&2
    echo "   先に公証込みのビルドを実行してください: YOUYAKU_NOTARY_PROFILE=... ./build.sh --dist" >&2
    exit 1
fi

# 未公証の DMG は macOS 15 以降で起動できない。取り違えて公開しないよう、ここでも確認する
if ! xcrun stapler validate "$DMG" >/dev/null 2>&1; then
    echo "!! $DMG に公証チケットが staple されていません(公証されていない DMG は配布できません)。" >&2
    exit 1
fi

# 非公開リポジトリの Releases アセットは認証なしでダウンロードできない。
# Sparkle の更新もサイトのダウンロードボタンも 404 になるため、公開前に気づけるようにする。
# (問い合わせ自体に失敗したときに「公開リポジトリだった」と勘違いして進まないよう、ここで止める)
if ! IS_PRIVATE=$(gh repo view "$GITHUB_REPO" --json isPrivate --jq .isPrivate 2>/dev/null); then
    echo "!! $GITHUB_REPO の情報を取得できませんでした。gh auth login を確認してください。" >&2
    exit 1
fi
if [ "$IS_PRIVATE" = "true" ]; then
    echo "!! $GITHUB_REPO は非公開リポジトリです。Releases のアセットは匿名ダウンロードできません。" >&2
    echo "   このまま公開しても、アプリ内アップデートとサイトのダウンロードボタンは 404 になります。" >&2
    echo "   リポジトリを公開してから実行してください(docs/RELEASE.md「配布物の置き場所」)。" >&2
    exit 1
fi

# タグは push 済みのコミットに付ける(未 push の SHA には作れない)
HEAD_SHA=$(git rev-parse HEAD)
if ! git branch -r --contains "$HEAD_SHA" 2>/dev/null | grep -q .; then
    echo "!! HEAD($HEAD_SHA)がまだ push されていません。先に push してください。" >&2
    echo "   タグ $TAG はこのコミットに付きます。" >&2
    exit 1
fi

# アセット名は版に依らず Youyaku.dmg で固定する(タグが版を分けるため)。
# こうするとサイトは /releases/latest/download/Youyaku.dmg という固定リンクを使える。
STAGE="dist/release"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp "$DMG" "$STAGE/${APP_NAME}.dmg"

if gh release view "$TAG" --repo "$GITHUB_REPO" >/dev/null 2>&1; then
    echo "==> 既存のリリース $TAG にアセットをアップロード"
    if [ -z "$CLOBBER" ] \
        && gh release view "$TAG" --repo "$GITHUB_REPO" --json assets --jq '.assets[].name' | grep -qx "${APP_NAME}.dmg"; then
        echo "!! $TAG には既に ${APP_NAME}.dmg があります。" >&2
        echo "   appcast.xml の EdDSA 署名は DMG のバイト列に紐づくため、差し替えると公開済みのフィードが検証に失敗します。" >&2
        echo "   意図的に差し替える場合のみ: ./Scripts/publish-release.sh --clobber" >&2
        exit 1
    fi
    gh release upload "$TAG" "$STAGE/${APP_NAME}.dmg" --repo "$GITHUB_REPO" $CLOBBER
else
    echo "==> リリース $TAG を作成(タグは $HEAD_SHA に付く)"
    gh release create "$TAG" "$STAGE/${APP_NAME}.dmg" \
        --repo "$GITHUB_REPO" \
        --target "$HEAD_SHA" \
        --title "$TAG" \
        --notes "Youyaku $VERSION"
fi

rm -rf "$STAGE"

echo "==> 公開しました: https://github.com/${GITHUB_REPO}/releases/download/${TAG}/${APP_NAME}.dmg"
echo
echo "次: appcast.xml を commit して push すると、既存利用者のアプリ内アップデートに反映されます。"
echo "  git add http_dist/download/appcast.xml http_dist/download/version.txt"
echo "  git commit -m \"リリース $TAG\" && git push"
