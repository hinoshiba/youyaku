#!/bin/bash
# 内蔵カタログの GGUF を評価用キャッシュへダウンロードする。
# モデルの定義は models.json が単一の情報源(URL は BuiltinCatalog.swift と一致・SHA 固定)。
#
#   ./fetch-models.sh                 # models.json の全モデル
#   ./fetch-models.sh --ci-only       # "ci": true のモデルだけ
#   ./fetch-models.sh --only gemma    # 名前に "gemma" を含むモデルだけ
#   ./fetch-models.sh --dir /path     # 保存先(既定 ~/.cache/youyaku-eval/models)
set -uo pipefail
cd "$(dirname "$0")"

DEST="$HOME/.cache/youyaku-eval/models"
ONLY=""
CI_ONLY="0"
while [ $# -gt 0 ]; do
  case "$1" in
    --dir)     DEST="$2"; shift 2 ;;
    --only)    ONLY="$2"; shift 2 ;;
    --ci-only) CI_ONLY="1"; shift ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done
mkdir -p "$DEST"

filesize() { stat -f%z "$1" 2>/dev/null || stat -c%s "$1" 2>/dev/null || echo 0; }

# models.json を name<TAB>bytes<TAB>url に展開(python3 は macOS / runner に必ずある)。
# プロセス置換で読むことで while ループを現在のシェルに保ち、失敗時に exit を効かせる。
while IFS=$'\t' read -r name want url; do
  out="$DEST/$name"
  if [ -f "$out" ] && [ "$(filesize "$out")" = "$want" ]; then
    echo "SKIP $name (complete)"; continue
  fi
  echo "GET  $name ($want bytes)"
  curl -fL --retry 5 --retry-delay 3 --retry-all-errors -C - -o "$out" "$url"
  have="$(filesize "$out")"
  if [ "$have" = "$want" ]; then echo "OK   $name"; else
    echo "FAIL $name size=$have want=$want" >&2; exit 1
  fi
done < <(python3 - "$ONLY" "$CI_ONLY" <<'PY'
import json,sys
only, ci_only = sys.argv[1], sys.argv[2] == "1"
for m in json.load(open("models.json")):
    if ci_only and not m.get("ci"): continue
    if only and only not in m["name"]: continue
    print(f'{m["name"]}\t{m["bytes"]}\t{m["url"]}')
PY
)

echo "-> $DEST"
