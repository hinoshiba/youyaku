#!/usr/bin/env python3
"""CI 用: 今回のメトリクスをコミット済みベースラインと比べ、劣化していれば非ゼロ終了する。

  # 比較(既定)。ベースラインが無ければ「未記録」として素通り(初回用)
  python3 ci-check.py --model NAME --metrics metrics.json --baseline-dir ci-baseline

  # 記録。今回の数値をベースラインとして書き出す(CI 上で採り、コミットする)
  python3 ci-check.py --model NAME --metrics metrics.json --baseline-dir ci-baseline --record

判定(既定しきい値):
  - 完全クリーン率が    --max-clean-drop  ポイント超で低下 → 失敗
  - 致命的欠陥率が      --max-critical-rise ポイント超で上昇 → 失敗

ベースラインは CPU・ランナー依存で決まるため、必ず CI 上で --record して得たものを使う
(ローカルの Metal 実行とはトークンが変わり、そのままでは誤検知する)。
"""
import argparse, json, os, sys


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--metrics", required=True)
    ap.add_argument("--baseline-dir", required=True)
    ap.add_argument("--record", action="store_true")
    ap.add_argument("--max-clean-drop", type=float, default=5.0)
    ap.add_argument("--max-critical-rise", type=float, default=3.0)
    args = ap.parse_args()

    metrics = json.load(open(args.metrics))
    if args.model not in metrics:
        print(f"::error::metrics に {args.model} が無い(生成が空?)")
        return 1
    cur = metrics[args.model]

    os.makedirs(args.baseline_dir, exist_ok=True)
    bpath = os.path.join(args.baseline_dir, args.model + ".json")

    if args.record:
        json.dump(cur, open(bpath, "w"), ensure_ascii=False, indent=1)
        print(f"記録: {bpath}  clean={cur['clean_pct']}%  critical={cur['critical_pct']}%")
        return 0

    if not os.path.exists(bpath):
        print(f"::warning::{args.model} のベースライン未記録。--record で採取して commit してください。")
        print(f"今回: clean={cur['clean_pct']}%  critical={cur['critical_pct']}%  (n={cur['n']})")
        return 0

    base = json.load(open(bpath))
    clean_drop = base["clean_pct"] - cur["clean_pct"]
    crit_rise = cur["critical_pct"] - base["critical_pct"]

    print(f"model     : {args.model}  (n={cur['n']})")
    print(f"clean     : {base['clean_pct']:5}% -> {cur['clean_pct']:5}%  (Δ {-clean_drop:+.1f}pt, 許容 -{args.max_clean_drop})")
    print(f"critical  : {base['critical_pct']:5}% -> {cur['critical_pct']:5}%  (Δ {crit_rise:+.1f}pt, 許容 +{args.max_critical_rise})")

    fail = []
    if clean_drop > args.max_clean_drop:
        fail.append(f"完全クリーン率が {clean_drop:.1f}pt 低下(許容 {args.max_clean_drop})")
    if crit_rise > args.max_critical_rise:
        fail.append(f"致命的欠陥率が {crit_rise:.1f}pt 上昇(許容 {args.max_critical_rise})")

    if fail:
        for m in fail:
            print(f"::error title=Youyaku eval regression ({args.model})::{m}")
        return 1
    print("OK (回帰なし)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
