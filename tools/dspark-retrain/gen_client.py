#!/usr/bin/env python3
# Concurrent self-distillation generation client for llama-server.
# For each prompt: /tokenize the chat-templated user turn -> prompt_ids (token-id
# consistency), then /completion greedy (temp 0) with prompt_ids -> generated token ids.
# Writes {"tokens": prompt_ids + gen_ids, "n_prompt": len(prompt_ids)} per line.
# JSON prompt content is decoded natively by json.loads (fixes the v1 backslash-n bug).
# Submissions are bounded: at most 2 x workers requests are in flight, and no prompt is
# submitted once the accepted count plus the in-flight count reaches max_samples. The
# server therefore generates at most max_samples completions plus the skipped candidates.
#
# Usage: gen_client.py <port> <workers> <n_predict> <out.jsonl> <max_samples> <skip_lines> <prompts.jsonl> [extra_prompts.jsonl ...]
import sys, json, time, threading, urllib.request
from concurrent.futures import ThreadPoolExecutor, wait, FIRST_COMPLETED

port      = int(sys.argv[1])
workers   = int(sys.argv[2])
npred     = int(sys.argv[3])
out_path  = sys.argv[4]
max_samples = int(sys.argv[5])
skip_lines  = int(sys.argv[6])
prompt_files = sys.argv[7:]

BASE = f"http://127.0.0.1:{port}"

def post(path, obj, timeout=600):
    req = urllib.request.Request(BASE+path, data=json.dumps(obj).encode(),
                                 headers={"Content-Type":"application/json"})
    return json.loads(urllib.request.urlopen(req, timeout=timeout).read())

def first_user(line):
    try:
        o = json.loads(line)
    except Exception:
        return None
    if isinstance(o, dict):
        conv = o.get("conversations") or o.get("messages")
        if isinstance(conv, list):
            for m in conv:
                if isinstance(m, dict) and m.get("role") == "user" and m.get("content"):
                    return m["content"]
        if o.get("prompt"): return o["prompt"]
    return None

# collect prompts
prompts = []
seen = 0
for pf in prompt_files:
    with open(pf) as f:
        for line in f:
            seen += 1
            if seen <= skip_lines: continue
            u = first_user(line.rstrip("\n"))
            if not u: continue
            prompts.append(u)
            if len(prompts) >= max_samples * 2:  # oversample; some may be filtered/too long
                break
    if len(prompts) >= max_samples * 2: break
print(f"loaded {len(prompts)} candidate prompts (skip_lines={skip_lines})", flush=True)

lock = threading.Lock()
fout = open(out_path, "w")
counters = {"done":0, "skip":0, "gen_tokens":0}
t0 = time.time()

def work(u):
    ptext = f"<|im_start|>user\n{u}<|im_end|>\n<|im_start|>assistant\n"
    try:
        tk = post("/tokenize", {"content": ptext, "add_special": True})
        pids = tk["tokens"]
        if len(pids) <= 4 or len(pids) > 768:
            with lock: counters["skip"] += 1
            return
        r = post("/completion", {"prompt": pids, "n_predict": npred, "temperature": 0,
                                 "cache_prompt": True, "return_tokens": True})
        gids = r.get("tokens") or []
        if not gids:
            with lock: counters["skip"] += 1
            return
        rec = {"tokens": pids + gids, "n_prompt": len(pids)}
        with lock:
            if counters["done"] >= max_samples:
                return
            fout.write(json.dumps(rec) + "\n"); fout.flush()
            counters["done"] += 1; counters["gen_tokens"] += len(gids)
            d = counters["done"]
            if d % 25 == 0:
                el = time.time() - t0
                print(f"  gen {d} (skip {counters['skip']}) | gen_tok {counters['gen_tokens']} | "
                      f"{counters['gen_tokens']/el:.1f} tok/s aggregate | {el:.1f}s", flush=True)
    except Exception as e:
        with lock: counters["skip"] += 1

def accepted():
    with lock:
        return counters["done"]

window = max(2 * workers, 1)
with ThreadPoolExecutor(max_workers=workers) as ex:
    pending = set()
    for u in prompts:
        # wait for a free slot: the window is full, or the accepted plus in-flight count
        # already covers the cap and a skip must free the slot first
        while accepted() < max_samples and (len(pending) >= window or accepted() + len(pending) >= max_samples):
            _, pending = wait(pending, return_when=FIRST_COMPLETED)
        if accepted() >= max_samples:
            break
        pending.add(ex.submit(work, u))
    wait(pending)

fout.close()
el = time.time() - t0
print(f"=== gen done === samples={counters['done']} skip={counters['skip']} "
      f"gen_tokens={counters['gen_tokens']} time={el:.1f}s aggregate={counters['gen_tokens']/max(el,1e-9):.1f} tok/s")
print(f"out: {out_path}")
