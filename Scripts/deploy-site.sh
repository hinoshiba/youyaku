#!/bin/zsh
# サイト(http_dist)を Cloudflare Workers へデプロイする。
#
#   使い方: ./Scripts/deploy-site.sh [--allow-missing-dmg]
#
# wrangler はローカルの http_dist をそのまま配信するため、DMG が手元に無い状態で
# deploy すると「公開中の DMG がサイトから消える」。それを防ぐガードを通してから deploy する。
set -euo pipefail
cd "$(dirname "$0")/.."

ALLOW_MISSING_DMG=0
if [ "${1:-}" = "--allow-missing-dmg" ]; then
    ALLOW_MISSING_DMG=1
fi

DMG="http_dist/download/Youyaku.dmg"
VERSION_TXT="http_dist/download/version.txt"

# ---- 1. DMG 消失ガード ----
if [ ! -f "$DMG" ] || [ ! -f "$VERSION_TXT" ]; then
    if [ "$ALLOW_MISSING_DMG" = "1" ]; then
        echo "==> 警告: $DMG / $VERSION_TXT が揃っていませんが、--allow-missing-dmg 指定のため続行します。"
    else
        echo "!! $DMG または $VERSION_TXT がありません。" >&2
        echo "   このまま deploy すると公開中の DMG がサイトから消えます(wrangler はローカルの http_dist を配信するため)。" >&2
        echo "   先に YOUYAKU_NOTARY_PROFILE を設定して ./build.sh --dist で配置するか、" >&2
        echo "   意図的に DMG なしで公開する場合は --allow-missing-dmg を付けて再実行してください。" >&2
        exit 1
    fi
fi

# ---- 1.5. 問い合わせ先プレースホルダの公開ブロック ----
# privacy.html の連絡先が未設定のまま一般公開しないための機械的ガード。
# 身内限定公開など意図的に続行する場合のみ YOUYAKU_ALLOW_PLACEHOLDER=1 を設定する。
if grep -q 'contact-placeholder' http_dist/privacy.html 2>/dev/null; then
    if [ "${YOUYAKU_ALLOW_PLACEHOLDER:-}" = "1" ]; then
        echo "==> 警告: privacy.html の問い合わせ先がプレースホルダのままですが、YOUYAKU_ALLOW_PLACEHOLDER=1 のため続行します。"
    else
        echo "!! privacy.html の問い合わせ先がプレースホルダのままです。" >&2
        echo "   公開前に実際の連絡先へ差し替えてください(App Store のサポート要件・特商法対応の観点でも必須)。" >&2
        echo "   意図的に続行する場合は YOUYAKU_ALLOW_PLACEHOLDER=1 を設定して再実行してください。" >&2
        exit 1
    fi
fi

# ---- 2. Cloudflare Workers の 25 MiB 制限チェック ----
if [ -f "$DMG" ]; then
    DMG_BYTES=$(stat -f%z "$DMG" 2>/dev/null || echo 0)
    LIMIT=$((25 * 1024 * 1024))
    if [ "${DMG_BYTES:-0}" -gt "$LIMIT" ]; then
        echo "!! $DMG が $((DMG_BYTES / 1024 / 1024)) MiB あり、Cloudflare Workers の静的アセット上限(1 ファイル 25 MiB)を超えています。" >&2
        echo "   deploy が失敗するため中止します。GitHub Releases 等の外部ホスティングへの移行を検討してください(docs/RELEASE.md 参照)。" >&2
        exit 1
    fi
fi

# ---- 3. deploy(package.json でバージョン固定した wrangler を使う)----
if [ ! -d node_modules/wrangler ]; then
    echo "==> wrangler を導入(npm install)"
    npm install
fi
echo "==> wrangler deploy"
npx wrangler deploy
