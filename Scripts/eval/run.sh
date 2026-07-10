#!/bin/bash
# Youyaku プロンプト評価ハーネス。
# 出荷コード(Refiner / LlamaEngine / Sanitizer)をそのままコンパイルして、
# 内蔵カタログの GGUF モデルで書き起こし→整形の品質を採点する。
#
# 使い方:
#   ./run.sh                     # 日本語 115 ケース × command モード
#   ./run.sh --cases en          # 英語 20 ケース
#   ./run.sh --cases ja_subset   # 層化 48 ケース(短時間)
#   ./run.sh --mode clean        # 整文モード
#   ./run.sh --temp 0.2 --samples 3   # 既定温度で 3 回、ブレを見る
#   ./run.sh --model gemma       # ファイル名に "gemma" を含むモデルだけ
#   ./run.sh --inspect           # 生成せず、各モデルへ渡る実プロンプトを表示
#
# モデルの置き場所(先に見つかった方を使う。--models-dir で上書き可):
#   1. $YOUYAKU_EVAL_MODELS
#   2. ~/.cache/youyaku-eval/models          (このハーネス用の退避先)
#   3. ~/Library/Application Support/Youyaku/Models  (アプリ本体のDL先)
set -euo pipefail

cd "$(dirname "$0")"

CASES="ja"
MODE="command"
TEMP="0.0"
SAMPLES="1"
MODEL_FILTER=""
MODELS_DIR=""
PREMISE=""
INSPECT="0"
MAX_TOKENS="768"
OUT=""
METRICS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --cases)      CASES="$2"; shift 2 ;;
    --mode)       MODE="$2"; shift 2 ;;
    --temp)       TEMP="$2"; shift 2 ;;
    --samples)    SAMPLES="$2"; shift 2 ;;
    --model)      MODEL_FILTER="$2"; shift 2 ;;
    --models-dir) MODELS_DIR="$2"; shift 2 ;;
    --premise)    PREMISE="$2"; shift 2 ;;
    --max-tokens) MAX_TOKENS="$2"; shift 2 ;;
    --out)        OUT="$2"; shift 2 ;;
    --metrics)    METRICS="$2"; shift 2 ;;   # モデル別の数値を JSON で書き出す(CI 用)
    --inspect)    INSPECT="1"; shift ;;
    -h|--help)    sed -n '2,26p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

# モデルディレクトリの決定
if [ -z "$MODELS_DIR" ]; then
  for d in "${YOUYAKU_EVAL_MODELS:-}" \
           "$HOME/.cache/youyaku-eval/models" \
           "$HOME/Library/Application Support/Youyaku/Models"; do
    if [ -n "$d" ] && ls "$d"/*.gguf >/dev/null 2>&1; then MODELS_DIR="$d"; break; fi
  done
fi
if [ -z "$MODELS_DIR" ] || ! ls "$MODELS_DIR"/*.gguf >/dev/null 2>&1; then
  echo "GGUF モデルが見つかりません。" >&2
  echo "  ./fetch-models.sh で内蔵カタログをダウンロードするか、--models-dir で場所を指定してください。" >&2
  exit 1
fi

CASE_FILE="cases/${CASES}.json"
[ -f "$CASE_FILE" ] || { echo "ケースファイルがありません: $CASE_FILE" >&2; exit 1; }

# ロケールはケースセットに追従(en は英語プロンプトを出させる)
LOCALE="ja-JP"; [ "$CASES" = "en" ] && LOCALE="en-US"

echo "== youyaku-eval =="
echo "  models : $MODELS_DIR ($(ls "$MODELS_DIR"/*.gguf | wc -l | tr -d ' ') 個)"
echo "  cases  : $CASE_FILE / mode=$MODE / locale=$LOCALE / temp=$TEMP x$SAMPLES"
[ -n "$MODEL_FILTER" ] && echo "  filter : $MODEL_FILTER"
[ -n "$PREMISE" ] && echo "  premise: $PREMISE"

swift build -c release >/dev/null
BIN=.build/release/eval

if [ "$INSPECT" = "1" ]; then
  "$BIN" --inspect-prompt --models-dir "$MODELS_DIR"
  exit 0
fi

if [ -z "$OUT" ]; then
  mkdir -p results
  STAMP="$(date +%Y%m%d-%H%M%S)"
  OUT="results/${CASES}-${MODE}-t${TEMP}-${STAMP}.jsonl"
fi
mkdir -p "$(dirname "$OUT")"

ARGS=(--cases "$CASE_FILE" --variants variants/current.json
      --mode "$MODE" --locale "$LOCALE" --sanitize
      --temp "$TEMP" --samples "$SAMPLES" --max-tokens "$MAX_TOKENS"
      --models-dir "$MODELS_DIR" --out "$OUT")
[ -n "$MODEL_FILTER" ] && ARGS+=(--only-model "$MODEL_FILTER")
[ -n "$PREMISE" ] && ARGS+=(--premise "$PREMISE")

"$BIN" "${ARGS[@]}"

echo
echo "== 採点 =="
python3 score.py "$OUT" "$CASE_FILE"

if [ -n "$METRICS" ]; then
  python3 score.py "$OUT" "$CASE_FILE" --json > "$METRICS"
  echo "メトリクス: $METRICS"
fi
echo
echo "生出力: $OUT"
