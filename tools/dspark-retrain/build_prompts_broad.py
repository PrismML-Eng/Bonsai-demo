#!/usr/bin/env python3
"""build_prompts_broad.py - assemble a broad-mix prompt set for self-distillation.

Output: <out.jsonl> with one record per line:
    {"id": "<source>_<n>", "category": "<cat>", "messages": [{"role": "user", "content": ...}]}
and <out>.counts.json with the per-source / per-category counts.

Categories and targets (default total 2500):
    math       25%  gsm8k train + MATH (hendrycks) + template word problems (fallback)
    reasoning  25%  Open-Platypus (non-math sources) + ARC-Challenge + LogiQA + StrategyQA + templates
    chat       20%  no_robots + dolly-15k + ultrachat first turns
    code       15%  CodeAlpaca-20k (offset, deduped vs the batch1 prompts) + Evol-Instruct-Code
    longform   15%  ultrachat long first turns + no_robots Generation + dolly creative + templates

Every HF source is optional: a failed download logs a warning and the category is
filled from the other sources of that category, then from templates.

usage: build_prompts_broad.py <out.jsonl> [--total 2500] [--seed 0] [--dedupe f1.jsonl ...]
"""
import argparse
import json
import os
import random
import re
import sys
import time

os.environ.setdefault("HF_HUB_DISABLE_PROGRESS_BARS", "1")
os.environ.setdefault("HF_DATASETS_DISABLE_PROGRESS_BARS", "1")

MIN_CHARS = 20
MAX_CHARS = 2000   # gen_client skips prompts > 768 tokens; 2000 chars is safely below


def log(*a):
    print(*a, file=sys.stderr, flush=True)


def norm(s: str) -> str:
    return re.sub(r"\s+", " ", s.strip().lower())


def ok_text(s) -> bool:
    if not isinstance(s, str):
        return False
    s = s.strip()
    if len(s) < MIN_CHARS or len(s) > MAX_CHARS:
        return False
    if "<|im_start|>" in s or "<|im_end|>" in s:
        return False
    return True


def try_load(name, *args, **kw):
    from datasets import load_dataset
    t0 = time.time()
    try:
        d = load_dataset(name, *args, **kw)
        log(f"[load] {name} {args} {kw.get('split', '')}: ok ({time.time() - t0:.0f}s)")
        return d
    except Exception as e:
        log(f"[load] {name} {args}: FAILED: {type(e).__name__}: {str(e)[:200]}")
        return None


COT_SUFFIX = [
    "",
    "",
    " Show your reasoning step by step.",
    " Think step by step and give the final answer.",
    " Explain your work.",
    " Solve this step by step.",
]


class Pool:
    """Collects (source, category, text) candidates with global dedupe."""

    def __init__(self, seen):
        self.seen = seen
        self.by_source = {}

    def add(self, source, cat, text):
        if not ok_text(text):
            return False
        k = norm(text)
        if k in self.seen:
            return False
        self.seen.add(k)
        self.by_source.setdefault((cat, source), []).append(text)
        return True


# --------------------------------------------------------------------------- sources
def src_gsm8k(pool, rng, want):
    d = try_load("openai/gsm8k", "main", split="train")
    if d is None:
        return
    idx = list(range(len(d)))
    rng.shuffle(idx)
    n = 0
    for i in idx:
        if n >= want:
            break
        q = d[i]["question"].strip()
        if pool.add("gsm8k", "math", q + rng.choice(COT_SUFFIX)):
            n += 1


def src_math(pool, rng, want):
    subjects = ["algebra", "counting_and_probability", "geometry", "intermediate_algebra",
                "number_theory", "prealgebra", "precalculus"]
    rows = []
    for s in subjects:
        d = try_load("EleutherAI/hendrycks_math", s, split="train")
        if d is None:
            continue
        for r in d:
            lvl = str(r.get("level", ""))
            if lvl in ("Level 1", "Level 2", "Level 3"):
                rows.append(r["problem"])
    if not rows:
        d = try_load("lighteval/MATH", "all", split="train")
        if d is not None:
            rows = [r["problem"] for r in d if str(r.get("level", "")) in ("Level 1", "Level 2", "Level 3")]
    rng.shuffle(rows)
    n = 0
    for p in rows:
        if n >= want:
            break
        if pool.add("hendrycks_math", "math", p.strip() + rng.choice(COT_SUFFIX)):
            n += 1


def src_platypus(pool, rng, want_reason, want_math):
    d = try_load("garage-bAInd/Open-Platypus", split="train")
    if d is None:
        return
    idx = list(range(len(d)))
    rng.shuffle(idx)
    n_r = n_m = 0
    for i in idx:
        if n_r >= want_reason and n_m >= want_math:
            break
        r = d[i]
        src = str(r.get("data_source", ""))
        text = (r.get("instruction") or "").strip()
        if r.get("input"):
            text = (r["input"].strip() + "\n\n" + text).strip()
        if "MATH" in src or "PRM800K" in src:
            if n_m < want_math and pool.add("platypus_math", "math", text):
                n_m += 1
        elif any(k in src for k in ("reclor", "scienceqa", "scibench", "theoremqa", "ARB", "airoboros", "guanaco", "tigerbot")):
            if n_r < want_reason and pool.add("platypus_reason", "reasoning", text):
                n_r += 1


def src_arc(pool, rng, want):
    d = try_load("allenai/ai2_arc", "ARC-Challenge", split="train")
    if d is None:
        return
    idx = list(range(len(d)))
    rng.shuffle(idx)
    n = 0
    for i in idx:
        if n >= want:
            break
        r = d[i]
        ch = r["choices"]
        opts = "\n".join(f"{l}. {t}" for l, t in zip(ch["label"], ch["text"]))
        text = f"{r['question'].strip()}\n{opts}\nWhich option is correct? Explain your reasoning, then state the answer."
        if pool.add("arc_challenge", "reasoning", text):
            n += 1


def src_logiqa(pool, rng, want):
    d = try_load("lucasmccabe/logiqa", split="train")
    if d is None:
        return
    idx = list(range(len(d)))
    rng.shuffle(idx)
    n = 0
    for i in idx:
        if n >= want:
            break
        r = d[i]
        opts = "\n".join(f"{chr(65 + j)}. {o}" for j, o in enumerate(r["options"]))
        text = f"{r['context'].strip()}\n\n{r['query'].strip()}\n{opts}\nReason through the options step by step and pick one."
        if pool.add("logiqa", "reasoning", text):
            n += 1


def src_strategyqa(pool, rng, want):
    d = try_load("ChilleD/StrategyQA", split="train")
    if d is None:
        return
    idx = list(range(len(d)))
    rng.shuffle(idx)
    n = 0
    for i in idx:
        if n >= want:
            break
        q = d[i]["question"].strip()
        text = q + " Answer yes or no, and explain the chain of facts that leads to your answer."
        if pool.add("strategyqa", "reasoning", text):
            n += 1


def src_no_robots(pool, rng, want_chat, want_long):
    d = try_load("HuggingFaceH4/no_robots", split="train")
    if d is None:
        return
    idx = list(range(len(d)))
    rng.shuffle(idx)
    n_c = n_l = 0
    for i in idx:
        if n_c >= want_chat and n_l >= want_long:
            break
        r = d[i]
        msgs = r["messages"]
        if not msgs or msgs[0]["role"] != "user":
            continue
        text = msgs[0]["content"].strip()
        cat = r.get("category", "")
        if cat in ("Generation",) and n_l < want_long:
            if pool.add("no_robots_gen", "longform", text):
                n_l += 1
        elif cat in ("Open QA", "Brainstorm", "Chat", "Rewrite", "Summarize", "Classify", "Closed QA", "Extract") and n_c < want_chat:
            if pool.add("no_robots", "chat", text):
                n_c += 1


def src_dolly(pool, rng, want_chat, want_long):
    d = try_load("databricks/databricks-dolly-15k", split="train")
    if d is None:
        return
    idx = list(range(len(d)))
    rng.shuffle(idx)
    n_c = n_l = 0
    for i in idx:
        if n_c >= want_chat and n_l >= want_long:
            break
        r = d[i]
        text = r["instruction"].strip()
        if r.get("context"):
            text = f"{r['context'].strip()}\n\n{text}"
        cat = r.get("category", "")
        if cat in ("creative_writing", "brainstorming") and n_l < want_long:
            if pool.add("dolly_creative", "longform", text):
                n_l += 1
        elif n_c < want_chat:
            if pool.add("dolly", "chat", text):
                n_c += 1


def src_ultrachat(pool, rng, want_chat, want_long, scan=6000):
    from datasets import load_dataset
    try:
        d = load_dataset("HuggingFaceH4/ultrachat_200k", split="train_sft", streaming=True)
        d = d.shuffle(seed=rng.randint(0, 10 ** 6), buffer_size=2000)
    except Exception as e:
        log(f"[load] ultrachat_200k: FAILED: {e}")
        return
    n_c = n_l = 0
    t0 = time.time()
    try:
        for k, r in enumerate(d):
            if k >= scan or (n_c >= want_chat and n_l >= want_long):
                break
            msgs = r["messages"]
            if not msgs or msgs[0]["role"] != "user":
                continue
            text = msgs[0]["content"].strip()
            # long-form: writing / essay style requests; chat: the rest
            if len(text) >= 120 and re.search(r"\b(write|essay|article|story|guide|blog|report|describe in detail|explain in detail|create a|compose|draft)\b", text, re.I):
                if n_l < want_long and pool.add("ultrachat_long", "longform", text):
                    n_l += 1
            elif n_c < want_chat and pool.add("ultrachat", "chat", text):
                n_c += 1
        log(f"[load] ultrachat_200k streaming: ok chat={n_c} long={n_l} ({time.time() - t0:.0f}s)")
    except Exception as e:
        log(f"[load] ultrachat_200k stream: FAILED mid-way: {e} chat={n_c} long={n_l}")


def src_codealpaca(pool, rng, want, offset=5000):
    d = try_load("sahil2801/CodeAlpaca-20k", split="train")
    if d is None:
        return
    idx = list(range(offset, len(d)))
    rng.shuffle(idx)
    n = 0
    for i in idx:
        if n >= want:
            break
        r = d[i]
        text = r["instruction"].strip()
        if r.get("input"):
            text = f"{text}\n{r['input'].strip()}"
        if pool.add("codealpaca_fresh", "code", text):
            n += 1


def src_evol_code(pool, rng, want):
    d = try_load("nickrosh/Evol-Instruct-Code-80k-v1", split="train")
    if d is None:
        return
    idx = list(range(len(d)))
    rng.shuffle(idx)
    n = 0
    for i in idx:
        if n >= want:
            break
        if pool.add("evol_code", "code", d[i]["instruction"].strip()):
            n += 1


# --------------------------------------------------------------------------- templates (fallback + a small fixed share)
NAMES = ["Alice", "Ben", "Chloe", "Dan", "Elena", "Farid", "Grace", "Hiro", "Ines", "Jamal", "Kira", "Leo", "Maya", "Noor", "Omar", "Priya"]
ITEMS = ["apples", "notebooks", "tickets", "cupcakes", "marbles", "stickers", "bottles of water", "pencils", "books", "t-shirts"]
CITIES = ["Lyon", "Osaka", "Denver", "Lagos", "Porto", "Austin", "Delhi", "Seoul", "Perth", "Quito"]


def tmpl_math(rng):
    t = rng.randrange(8)
    n1, n2 = rng.choice(NAMES), rng.choice(NAMES)
    while n2 == n1:
        n2 = rng.choice(NAMES)
    it = rng.choice(ITEMS)
    if t == 0:
        a, b, c = rng.randint(12, 90), rng.randint(2, 9), rng.randint(3, 40)
        return f"{n1} has {a} {it}. She gives {b} {it} to each of her {c // 4 + 1} friends and then buys {c} more. How many {it} does {n1} have now?"
    if t == 1:
        s1, s2, d = rng.choice([40, 50, 60, 70, 80, 90]), rng.choice([45, 55, 65, 75, 100, 110]), rng.choice([180, 240, 300, 360, 420])
        return f"Two cars start {d} km apart and drive toward each other at {s1} km/h and {s2} km/h. How long until they meet, and how far does each car travel? Show your reasoning step by step."
    if t == 2:
        p, r, y = rng.choice([1000, 2500, 5000, 8000]), rng.choice([3, 4, 5, 6, 8]), rng.choice([2, 3, 5])
        return f"{n1} invests ${p} at {r}% annual interest, compounded yearly. How much money will {n1} have after {y} years? Round to the nearest cent and explain each step."
    if t == 3:
        w, l = rng.randint(3, 25), rng.randint(3, 25)
        return f"A rectangular garden is {w} m wide and {l} m long. A path 1 m wide runs around the outside of the garden. What is the area of the path? Explain your work."
    if t == 4:
        a, b = rng.randint(2, 12), rng.randint(2, 12)
        return f"A bakery sells muffins in boxes of {a} and cookies in bags of {b}. {n1} needs the same number of muffins and cookies for a party. What is the smallest number of each she must buy, and how many boxes and bags is that? Think step by step."
    if t == 5:
        x, y, z = rng.randint(10, 99), rng.randint(10, 99), rng.randint(2, 9)
        return f"The sum of two numbers is {x + y}. One number is {z} more than the other, and their product is {x * y}. Is that consistent? Find the two numbers if a solution exists, and show the algebra."
    if t == 6:
        h, m = rng.randint(1, 12), rng.choice([0, 15, 20, 30, 40, 45])
        return f"What is the angle between the hour hand and the minute hand of a clock at {h}:{m:02d}? Show the calculation."
    a, b, c = rng.randint(2, 30), rng.randint(2, 30), rng.randint(2, 30)
    return f"{n1} can paint a room in {a} hours, {n2} in {b} hours, and a third painter in {c} hours. How long will it take all three working together? Explain your reasoning step by step."


def tmpl_reasoning(rng):
    t = rng.randrange(6)
    a, b, c, d = rng.sample(NAMES, 4)
    if t == 0:
        return f"{a}, {b}, {c} and {d} sit in a row of four seats. {a} is not at either end. {b} sits immediately to the left of {c}. {d} is not next to {a}. List every possible seating order and explain how you eliminated the others."
    if t == 1:
        return f"On an island, knights always tell the truth and knaves always lie. {a} says: '{b} is a knave.' {b} says: 'At least one of us is a knight.' What are {a} and {b}? Reason step by step."
    if t == 2:
        seq = [rng.randint(1, 5)]
        step = rng.randint(2, 4)
        for _ in range(4):
            seq.append(seq[-1] * step + rng.randint(0, 2))
        return f"What is the next number in the sequence {', '.join(map(str, seq))}, ...? Explain the rule you found and check it against every term."
    if t == 3:
        return f"All {rng.choice(['engineers', 'bakers', 'sailors', 'poets'])} in a town are {rng.choice(['early risers', 'left-handed', 'tea drinkers'])}. Some {rng.choice(['early risers', 'left-handed people', 'tea drinkers'])} are {rng.choice(['musicians', 'gardeners', 'chess players'])}. {a} is a {rng.choice(['musician', 'gardener', 'chess player'])}. Can we conclude anything about whether {a} is an {rng.choice(['engineer', 'early riser'])}? Explain the logic carefully."
    if t == 4:
        return f"Three boxes are labeled 'apples', 'oranges' and 'mixed', and every label is wrong. You may take one fruit from one box without looking inside. Which box do you pick, and how do you relabel all three correctly? Explain the reasoning."
    return f"{a} is older than {b}. {c} is younger than {b} but older than {d}. {rng.choice(NAMES)} is the same age as {c}. Rank all the people mentioned from oldest to youngest and say which relationships are uncertain."


LONG_TOPICS = [
    "how public-key cryptography works", "the causes of the French Revolution", "how vaccines train the immune system",
    "the water cycle", "how a compiler turns source code into machine code", "why the sky is blue",
    "the history of the printing press", "how neural networks learn from data", "the rules of chess for a beginner",
    "how to start a vegetable garden on a balcony", "the differences between TCP and UDP", "how black holes form",
    "how inflation affects savings", "the plot structure of a classic tragedy", "how a bill becomes a law",
    "how to prepare for a marathon in 16 weeks", "the basics of photography exposure", "how git branching works",
    "what happens during a solar eclipse", "how to negotiate a salary", "the life cycle of a star",
    "how recommendation systems work", "the pros and cons of remote work", "how to write a good cover letter",
    "the theory of plate tectonics", "how DNS resolves a domain name", "how the stock market works",
    "the health effects of sleep deprivation", "how to make sourdough bread", "the history of the internet",
]


def tmpl_longform(rng):
    t = rng.randrange(6)
    topic = rng.choice(LONG_TOPICS)
    if t == 0:
        return f"Write a detailed, well-structured explanation of {topic} for a curious high-school student. Use headings and give at least three concrete examples."
    if t == 1:
        return f"Write a 500-word blog post about {topic}. Open with a hook, cover the key ideas, and end with practical takeaways."
    if t == 2:
        return f"Compare and contrast {topic} with {rng.choice(LONG_TOPICS)}. Discuss at least four points of comparison and summarize which is more important to understand first and why."
    if t == 3:
        return f"Write a short story (about 400 words) set in {rng.choice(CITIES)} about a character who unexpectedly learns {topic}. Include dialogue and a clear ending."
    if t == 4:
        return f"Create a step-by-step tutorial on {topic}. Number the steps, explain why each step matters, and list common mistakes at the end."
    return f"Write a persuasive essay arguing that everyone should understand {topic}. Address at least two counterarguments."


def fill_templates(pool, rng, cat, gen, want):
    n = 0
    tries = 0
    while n < want and tries < want * 20:
        tries += 1
        if pool.add(f"template_{cat}", cat, gen(rng)):
            n += 1


# --------------------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--total", type=int, default=2500)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--dedupe", nargs="*", default=[])
    args = ap.parse_args()
    rng = random.Random(args.seed)

    seen = set()
    n_dd = 0
    for p in args.dedupe:
        with open(p) as f:
            for line in f:
                try:
                    o = json.loads(line)
                except Exception:
                    continue
                conv = o.get("conversations") or o.get("messages") or []
                for m in conv:
                    if isinstance(m, dict) and m.get("role") == "user" and m.get("content"):
                        seen.add(norm(m["content"]))
                        n_dd += 1
    log(f"[dedupe] {n_dd} existing prompts loaded from {args.dedupe}")

    T = args.total
    target = {"math": round(T * 0.25), "reasoning": round(T * 0.25), "chat": round(T * 0.20),
              "code": round(T * 0.15), "longform": T - round(T * 0.25) * 2 - round(T * 0.20) - round(T * 0.15)}
    log(f"[target] {target}")
    pool = Pool(seen)

    # oversample each source a little (x1.15) so the final per-category cut is exact
    ov = 1.15
    src_gsm8k(pool, rng, int(target["math"] * 0.60 * ov))
    src_math(pool, rng, int(target["math"] * 0.30 * ov))
    src_platypus(pool, rng, int(target["reasoning"] * 0.45 * ov), int(target["math"] * 0.10 * ov))
    src_arc(pool, rng, int(target["reasoning"] * 0.15 * ov))
    src_logiqa(pool, rng, int(target["reasoning"] * 0.15 * ov))
    src_strategyqa(pool, rng, int(target["reasoning"] * 0.10 * ov))
    src_no_robots(pool, rng, int(target["chat"] * 0.45 * ov), int(target["longform"] * 0.25 * ov))
    src_dolly(pool, rng, int(target["chat"] * 0.30 * ov), int(target["longform"] * 0.15 * ov))
    src_ultrachat(pool, rng, int(target["chat"] * 0.25 * ov), int(target["longform"] * 0.45 * ov))
    src_codealpaca(pool, rng, int(target["code"] * 0.70 * ov))
    src_evol_code(pool, rng, int(target["code"] * 0.30 * ov))
    # a small fixed template share for reasoning/longform (puzzle styles absent from the HF sets)
    fill_templates(pool, rng, "reasoning", tmpl_reasoning, int(target["reasoning"] * 0.15))
    fill_templates(pool, rng, "longform", tmpl_longform, int(target["longform"] * 0.15))

    # assemble per category: round-robin over the sources of that category, then top up from templates
    gens = {"math": tmpl_math, "reasoning": tmpl_reasoning, "longform": tmpl_longform}
    out = []
    counts = {}
    for cat, want in target.items():
        srcs = {s: list(v) for (c, s), v in pool.by_source.items() if c == cat}
        for v in srcs.values():
            rng.shuffle(v)
        chosen = []
        while len(chosen) < want and any(srcs.values()):
            for s in list(srcs):
                if srcs[s] and len(chosen) < want:
                    chosen.append((s, srcs[s].pop()))
        if len(chosen) < want:
            if cat in gens:
                fill_templates(pool, rng, cat, gens[cat], want - len(chosen))
                extra = pool.by_source.get((cat, f"template_{cat}"), [])
                used = {t for _, t in chosen}
                for t in extra:
                    if len(chosen) >= want:
                        break
                    if t not in used:
                        chosen.append((f"template_{cat}", t))
            else:
                log(f"[warn] category {cat}: only {len(chosen)}/{want} (no template generator)")
        for s, t in chosen:
            out.append({"category": cat, "source": s, "text": t})
            counts.setdefault(cat, {}).setdefault(s, 0)
            counts[cat][s] += 1

    rng.shuffle(out)
    with open(args.out, "w") as f:
        for i, r in enumerate(out):
            rec = {"id": f"{r['source']}_{i}", "category": r["category"], "source": r["source"],
                   "messages": [{"role": "user", "content": r["text"]}]}
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
    summary = {"total": len(out), "target": target, "per_category": {c: sum(v.values()) for c, v in counts.items()},
               "per_source": counts, "dedupe_against": n_dd,
               "avg_chars": sum(len(r["text"]) for r in out) / max(1, len(out))}
    with open(args.out + ".counts.json", "w") as f:
        json.dump(summary, f, indent=2)
    log(json.dumps(summary, indent=2))
    log(f"[done] wrote {len(out)} prompts -> {args.out}")


if __name__ == "__main__":
    main()
