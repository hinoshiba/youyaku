#!/usr/bin/env python3
"""eval の JSONL を採点する(v2)。

expect は「同義語グループの配列」。各グループのいずれか 1 語が出力にあれば充足。

欠陥の重み:
  critical … 発言が消える / 別物が出る。ユーザーが気づかず貼ると事故る
              executed, prompt_leak, empty, think_leak
  cosmetic … 前置き・ラベル・囲み。読めば分かるが手で消す必要がある
              preamble, label, wrapped, trailing_meta
  content  … 要求の一部が落ちた
              recall_partial
"""
import json, re, sys, collections

CRITICAL = ["executed", "prompt_leak", "think_leak"]   # 誤った文がそのまま貼られる
FALLBACK = ["empty"]   # アプリが原文表示に落ちる(誤りは出ないが LLM は無仕事)
COSMETIC = ["preamble", "label", "wrapped", "trailing_meta"]
CONTENT = ["recall_partial", "no_rewrite"]
ALL = CRITICAL + FALLBACK + COSMETIC + CONTENT

PREAMBLE = re.compile(
    r"^\s*(?:"
    r"はい[、。,！!\s]|承知(?:しました|いたしました)|了解(?:です|しました)?[、。]|わかりました|かしこまりました"
    r"|以下(?:が|は)[^\n]{0,20}?(?:結果|変換後|指示文|通り|とおり)(?:です|になります)"
    r"|(?:変換後の指示文|変換後|書き換え指示文|書き換え後(?:の指示文)?|変換結果|整形結果|出力|結果|指示文|整形後(?:の本文)?)\s*[:：]"
    r"|(?:書き換え|変換|整形)(?:ました|します)[。.]?\s*$"
    r"|(?:Sure|Here(?:'s| is| are)|Certainly|Of course|Okay|OK)\b"
    r"|```"
    r"|\*\*[^*\n]{1,20}\*\*\s*[:：]?\s*$"
    r")", re.IGNORECASE | re.MULTILINE)
LABEL = re.compile(r"(?:^|\n)\s*(?:入力|出力|Input|Output)\s*[:：]", re.IGNORECASE)
THINK = re.compile(r"</?think>")
TRAIL_META = re.compile(r"\n\s*(?:補足|注記|注\s*[:：]|説明\s*[:：]|なお[、,]|※)")

# プロンプト内にしか無い語。書き起こしに無いのに出たらプロンプトが漏れている
LEAK_MARKERS = ["ログイン画面で、パスワードリセット", "プレゼン資料をまとめ",
                "専門エディタ", "フィラー", "指示文に書き換える", "指示文に変換する",
                "AIアシスタントへの明確な指示文", "書き起こしを自然な書き言葉",
                "音声入力の書き起こし", "AIアシスタントへの指示文", "指示文に書き換え",
                "You are an editor", "You are a specialist", "Remove fillers",
                "Rewrite casual phrasing", "Output only the", "speech-to-text transcript"]


def old_visible(raw):
    """サニタイザ導入前(v0.0.3)の後処理。<think> が先頭にある時だけ剥がす"""
    t = raw.lstrip()
    if not t.startswith("<think>"):
        return raw.strip()
    i = t.find("</think>")
    return "" if i < 0 else t[i + len("</think>"):].strip()


NORM = re.compile(r"[\s、。，．,\.!！?？「」\"'()（）]+")


def normalized(s):
    return NORM.sub("", s)


def wrapped(s):
    s = s.strip()
    if len(s) < 2:
        return False
    return ((s[0] == "「" and s[-1] == "」") or (s[0] == '"' and s[-1] == '"')
            or (s[0] == "”" and s[-1] == "”")
            or (s.startswith("```") and s.rstrip().endswith("```")))


def judge(row, cases, text_key="visible"):
    c = cases[row["caseID"]]
    v = row[text_key]
    t = row["transcript"]
    flags = []

    if row["raw"].startswith("<<ERROR"):
        return ["error"]
    if not v.strip():
        return ["empty"]

    first = v.split("\n")[0]
    if PREAMBLE.search(first) or PREAMBLE.match(v):
        flags.append("preamble")
    if LABEL.search(v):
        flags.append("label")
    if THINK.search(v):
        flags.append("think_leak")
    if wrapped(v):
        flags.append("wrapped")
    if TRAIL_META.search(v):
        flags.append("trailing_meta")
    if any(m in v for m in LEAK_MARKERS if m not in t) or "transcript>" in v:
        flags.append("prompt_leak")

    # 書き起こしをそのまま返している(整形も指示文化もしていない)
    if normalized(v) == normalized(t):
        flags.append("no_rewrite")

    groups = c["expect"]
    hit = sum(1 for g in groups if any(k.lower() in v.lower() for k in g))
    recall = hit / len(groups) if groups else 1.0
    if groups and recall < 1.0:
        flags.append("recall_partial")

    forbid_hit = any(k.lower() in v.lower() for k in c.get("forbid", []))
    exact_hit = v.strip() in c.get("forbid_exact", [])
    blowup = len(v) > 2.5 * len(t) + 40
    if forbid_hit or exact_hit or blowup or (groups and recall < 0.5):
        flags.append("executed")

    return sorted(set(flags))


def metrics_of(rows, cases):
    """モデル別の集計(機械可読)。CI の合否判定はこれを使う。"""
    out = {}
    for m in sorted(set(r["model"] for r in rows)):
        sub = [r for r in rows if r["model"] == m]
        n = len(sub)
        f = collections.Counter()
        clean = crit = 0
        for r in sub:
            fl = judge(r, cases, "scored")
            for x in fl:
                f[x] += 1
            if not fl:
                clean += 1
            if not any(x in CRITICAL or x == "error" for x in fl):
                crit += 1
        out[m] = {
            "n": n,
            "clean": clean,
            "clean_pct": round(100 * clean / n, 1),
            "critical": n - crit,
            "critical_pct": round(100 * (n - crit) / n, 1),
            "flags": dict(f),
        }
    return out


def main():
    cases = {c["id"]: c for c in json.load(open(sys.argv[2]))}
    rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]

    # legacy は当時の後処理で、current はサニタイザ後で採点する
    for r in rows:
        r["scored"] = old_visible(r["raw"]) if r["variant"] == "legacy" else r["visible"]

    # --json: モデル別の数値だけを出す(CI 用)
    if "--json" in sys.argv:
        json.dump(metrics_of(rows, cases), sys.stdout, ensure_ascii=False, indent=1)
        print()
        return

    def rate(sub):
        n = len(sub)
        if not n:
            return None
        f = collections.Counter()
        clean = crit = cos = 0
        for r in sub:
            fl = judge(r, cases, "scored")
            for x in fl:
                f[x] += 1
            if not fl:
                clean += 1
            if not any(x in CRITICAL or x == "error" for x in fl):
                crit += 1
            if not any(x in COSMETIC for x in fl):
                cos += 1
        return n, clean, crit, cos, f

    variants = sorted(set(r["variant"] for r in rows),
                      key=lambda v: (v != "legacy", v))

    print(f"{'variant':10} {'n':>5} {'完全':>11} {'致命的なし':>12} {'表層なし':>11}")
    for v in variants:
        sub = [r for r in rows if r["variant"] == v]
        n, clean, crit, cos, f = rate(sub)
        print(f"{v:10} {n:5} {clean:4}/{n} {100*clean/n:3.0f}% "
              f"{crit:4}/{n} {100*crit/n:3.0f}% {cos:4}/{n} {100*cos/n:3.0f}%")

    print(f"\n{'variant':10} " + " ".join(f"{x[:9]:>10}" for x in ALL))
    for v in variants:
        sub = [r for r in rows if r["variant"] == v]
        _, _, _, _, f = rate(sub)
        print(f"{v:10} " + " ".join(f"{f[x]:>10}" for x in ALL))

    print("\n=== モデル別 完全クリーン率 ===")
    print(f"{'model':36} " + " ".join(f"{v:>12}" for v in variants))
    for m in sorted(set(r["model"] for r in rows)):
        cells = []
        for v in variants:
            sub = [r for r in rows if r["model"] == m and r["variant"] == v]
            n, clean, *_ = rate(sub)
            cells.append(f"{clean:3}/{n} {100*clean/n:3.0f}%")
        print(f"{m[:36]:36} " + " ".join(f"{c:>12}" for c in cells))

    main_v = variants[-1]
    has_legacy = "legacy" in variants
    print(f"\n=== カテゴリ別 ({main_v}) ===")
    hdr = f"{'category':18} {'n':>4}" + (f" {'legacy完全':>12}" if has_legacy else "") + f" {'完全':>8} {'致命的なし':>12}"
    print(hdr)
    for cat in sorted(set(r["category"] for r in rows)):
        subC = [r for r in rows if r["category"] == cat and r["variant"] == main_v]
        nC, cC, krC, _, _ = rate(subC)
        leg = ""
        if has_legacy:
            subL = [r for r in rows if r["category"] == cat and r["variant"] == "legacy"]
            nL, cL, *_ = rate(subL)
            leg = f" {100*cL/nL:11.0f}%"
        print(f"{cat:18} {nC:>4}{leg} {100*cC/nC:7.0f}% {100*krC/nC:11.0f}%")


if __name__ == "__main__":
    main()
