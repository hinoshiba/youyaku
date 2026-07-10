# youyaku-eval

Youyaku のプロンプト品質を、内蔵カタログのローカル LLM で採点する評価ハーネス。

出荷コード(`Refiner` / `LlamaEngine` / `Sanitizer`)を **symlink 経由でそのままコンパイル**
するので、ここで測る挙動はアプリの挙動そのもの。プロンプトを変えたら再実行して回帰を見る用。

```
Scripts/eval/
├── run.sh              エントリポイント(生成 → 採点 → 表示)
├── fetch-models.sh     内蔵カタログの GGUF を評価キャッシュへDL
├── score.py            採点ロジック
├── Package.swift       出荷ソースへの symlink を含む SwiftPM パッケージ
├── Sources/eval/       ハーネス本体 + 出荷コードへの相対 symlink
├── cases/              テストケース(ja=115 / en=20 / ja_subset=48)
├── variants/           プロンプト定義(current = 出荷中)
├── SUMMARY.md          直近の成績(人間向け)
└── RESULTS.json        直近の成績(全数値、機械可読)
```

## 使い方

```sh
# 1) モデルを用意(初回のみ。合計 ~14 GB、~/.cache/youyaku-eval/models へ)
./fetch-models.sh

# 2) 走らせる
./run.sh                        # 日本語 115 ケース × command
./run.sh --cases ja_subset      # 層化 48 ケース(短時間の回帰確認)
./run.sh --cases en             # 英語 20 ケース
./run.sh --mode clean           # 整文モード
./run.sh --temp 0.2 --samples 3 # アプリ既定温度で 3 回、ブレを見る
./run.sh --model gemma          # 特定モデルだけ
./run.sh --inspect              # 生成せず、各モデルへ渡る実プロンプトを表示
```

出力(生成物 `results/*.jsonl` とビルド `.build/`)は `.gitignore` 済み。
`SUMMARY.md` / `RESULTS.json` を更新したいときは、走らせた後で手で上書きする。

## モデルの置き場所

`run.sh` は次の順で最初に GGUF が見つかった場所を使う:

1. `$YOUYAKU_EVAL_MODELS`
2. `~/.cache/youyaku-eval/models`(`fetch-models.sh` の既定)
3. `~/Library/Application Support/Youyaku/Models`(アプリ本体の DL 先)

`--models-dir <path>` で明示指定も可。

## テストケースの書式

`cases/*.json` は 1 ケース 1 オブジェクトの配列:

```json
{
  "id": "s01",
  "category": "self-correction",
  "transcript": "あーいや違うそっちじゃなくて右のボタンの色を赤にして いやオレンジにして",
  "expect": [["オレンジ"], ["ボタン"]],
  "forbid": [],
  "forbid_exact": []
}
```

- `expect`: 同義語グループの配列。各グループのいずれか 1 語が出力にあれば充足。
  1 つでも欠けると `recall_partial`、半分以上欠けると `executed`(=別物が出た)。
- `forbid`: 出力に現れたら「命令を実行してしまった」印(質問への回答文など)。
- `forbid_exact`: 出力全体がこの文字列と一致したら実行とみなす(injection の canary 用)。

## 採点フラグ

| フラグ | 分類 | 意味 |
|---|---|---|
| `executed` | 致命的 | 書き起こしを実行してしまった / 内容の大半が消えた |
| `prompt_leak` | 致命的 | system やタスク指示が出力に漏れた |
| `think_leak` | 致命的 | `<think>` が残った |
| `empty` | フォールバック | 空。アプリは原文表示に落ちる(誤りは出ない) |
| `preamble` `label` `wrapped` `trailing_meta` | 表層 | 前置き・ラベル・囲み・後記 |
| `recall_partial` | 内容 | 要求の一部が落ちた |
| `no_rewrite` | 内容 | 書き起こしをそのまま返した(整形も指示文化もせず) |

採点は完全一致でなく語の有無を見るヒューリスティック。言い換え・カタカナ化を
`recall_partial` と誤判定しうるので、数値は絶対値でなくプロンプト間の相対比較に使う。

## CI(GitHub Actions)

`.github/workflows/eval.yml`。当面は手動(workflow_dispatch)のみ。

- `models.json` の `"ci": true` のモデルを **1 モデル 1 ジョブ**のマトリクスで回す。
  モデルを増やすときは `models.json` に 1 行足して `"ci": true` にするだけ
  (ジョブは増えるが 1 ジョブは肥大化しない)。
- ランナーは GPU 非対応なので **CPU 推論**(`YOUYAKU_GPU_LAYERS=0`)。層化 48 ケースで時間を抑える。
- 合否は `ci-baseline/<model>.json` との差分。既定しきい値は
  完全クリーン率 −5pt 超の低下、または致命的欠陥率 +3pt 超の上昇で失敗。

### 初回セットアップ(ベースラインの採取)

CPU とローカル Metal ではトークンが変わるため、**ベースラインは CI 上で採る**。

1. Actions で eval.yml を `mode = record` で実行。
2. 各ジョブの成果物(artifact)`ci-baseline-<model>` をダウンロードし、
   中の `<model>.json` を `Scripts/eval/ci-baseline/` に置いて commit。
3. 以降は `mode = check`(既定)で、この基準と比較する。

ベースライン未記録のモデルは check でも「未記録」として素通りするので、
新モデル追加時も既存のチェックは壊れない(そのモデルだけ record して足せばよい)。

しきい値を変えたいときは `ci-check.py --max-clean-drop / --max-critical-rise`。

## 注意

- macOS(Apple Silicon)専用。llama.cpp の Metal バックエンドを使う(CI は CPU)。
- `YOUYAKU_GPU_LAYERS` 環境変数で GPU 層数を上書きできる(0=CPU のみ)。未設定ならアプリ同様 -1。
- `Sources/eval/{Refiner,LlamaEngine,Sanitizer}.swift` は出荷ソースへの相対 symlink。
  リポジトリごと移動すれば追従するが、個別コピーすると壊れる。
- greedy を基準にしているのは決定性のため。temp 0.2 との差は SUMMARY 参照。
