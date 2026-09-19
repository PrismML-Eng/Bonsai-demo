#!/usr/bin/env python3
"""Build placeholders.json for the benchmark document from a spec_bench run.

The script reads <results_dir>/results.json (schema_version 2) and, when
present, <results_dir>/single.json from single_prompt_bench.py. It writes a
flat map of printed strings, for example "61.5", "52.1%" or "2.06x", that
fill_doc.py substitutes for {{BENCH:key}} markers. It reports every expected
key that the run did not produce. Standard library only.

Usage: fill_placeholders.py <results_dir> [--out FILE] [--single FILE] [--strict]
"""

import argparse
import json
import os
import sys

# Config name in results.json -> short key in the placeholder names.
CONFIG_KEYS = {"baseline": "baseline", "dspark-v1": "v1", "dspark-v2": "v2"}
LABELS = {
    "baseline": "baseline",
    "v1": "DSpark v1 (Ternary-Bonsai-27B drafter, K=4)",
    "v2": "DSpark v2 (K=5)",
}
DRAFTER_KEYS = ("v1", "v2")
SLOT_COUNTS = (1, 2, 4)
SINGLE_PASSES = 3

# Placeholder workload -> (set, category); category None means the whole set.
WORKLOADS = [
    ("code", "matrix", "code"),
    ("math", "matrix", "math"),
    ("reasoning", "matrix", "reasoning"),
    ("chat", "matrix", "chat"),
    ("longform", "matrix", "long-form"),
    ("tool", "tool", None),
    ("agent", "agent", None),
    ("blended", "matrix", None),
    ("long2000", "long", None),
]


def config_key(name):
    return CONFIG_KEYS.get(name, name)


def mean(values):
    values = [v for v in values if v is not None]
    return sum(values) / len(values) if values else None


def tokens_per_step(predicted_n, accepted):
    """Generated tokens per verify step: predicted_n / (predicted_n - accepted)."""
    if not predicted_n:
        return None
    steps = predicted_n - (accepted or 0)
    return (predicted_n / steps) if steps > 0 else None


def fmt_rate(value):
    return "n/a" if value is None else "%.1f" % value


def fmt_step(value):
    return "n/a" if value is None else "%.2f" % value


def fmt_pct(value):
    return "n/a" if value is None else "%.1f%%" % (value * 100.0)


def fmt_x(value):
    return "n/a" if value is None else "%.2fx" % value


def fmt_mj(value):
    return "n/a" if value is None else "%.0f" % value


def expected_keys(drafters=DRAFTER_KEYS, slot_counts=SLOT_COUNTS, passes=SINGLE_PASSES):
    """The full key set a complete run produces, for the missing-key report."""
    keys = ["labels.baseline"] + ["labels.%s" % d for d in drafters]
    for cfg in ("baseline",) + tuple(drafters):
        keys += ["single.%s.p%d" % (cfg, i) for i in range(1, passes + 1)] + ["single.%s.mean" % cfg]
    for d in drafters:
        keys += ["single.%s.speedup" % d, "single.%s.accept" % d, "single.%s.tps_step" % d]
    for w, _, _ in WORKLOADS:
        keys += ["%s.baseline" % w, "%s.baseline.tps" % w]
        for d in drafters:
            keys += ["%s.%s.%s" % (w, d, f) for f in ("tps", "accept", "speedup", "tps_step")]
    for n in slot_counts:
        keys += ["slots.%d.baseline.stream" % n, "slots.%d.baseline.aggregate" % n]
        for d in drafters:
            keys += ["slots.%d.%s.%s" % (n, d, f)
                     for f in ("stream", "aggregate", "accept", "speedup", "aggregate_speedup")]
    keys += ["power.source", "power.idle.w", "power.baseline.w", "power.baseline.mj"]
    for d in drafters:
        keys += ["power.%s.w" % d, "power.%s.mj" % d]
    for d in drafters:
        keys += ["exact.%s.identical" % d, "exact.%s.total" % d]
    return keys


def workload_rows(rows, set_name, category):
    return [r for r in rows if r.get("set") == set_name and (category is None or r.get("category") == category)]


def single_slot_rows(results):
    return [r for r in results.get("results", []) if r.get("error") is None and r.get("slots", 1) == 1]


def workload_keys(by_config, wanted):
    """The (prompt_id, pass) keys of one workload that every config with rows completed.

    A config that has no successful single-slot row at all (a server that
    did not start) takes no part. The baseline rate, every config rate and
    every speedup of the workload cover this one key set, so the printed
    values agree with each other after a partial failure.
    """
    common = None
    for name, current in by_config.items():
        if not current:
            continue
        present = {k for k in current if k in wanted}
        common = present if common is None else common & present
    return sorted(common or ())


def workload_placeholders(results, ph, notes=None):
    """W.baseline, W.<cfg>.tps/accept/speedup/tps_step from the request rows.

    Rates are arithmetic means of tok_s over the prompts and passes that the
    baseline and every config completed (see workload_keys); acceptance and
    tokens per step are aggregated over the same rows. A workload that some
    config did not complete at all is omitted. `notes` receives a line for
    every omitted workload and for every workload whose key set is smaller
    than the baseline set.
    """
    rows = single_slot_rows(results)
    names = results.get("config_names") or sorted({r["config"] for r in rows})
    by_config = {name: {(r["prompt_id"], r["pass"]): r for r in rows if r["config"] == name} for name in names}
    base = by_config.get("baseline", {})
    for w, set_name, category in WORKLOADS:
        wanted = {(r["prompt_id"], r["pass"]) for r in workload_rows(rows, set_name, category)}
        keys = workload_keys(by_config, wanted)
        base_count = sum(1 for k in base if k in wanted)
        if not keys:
            if notes is not None and base_count:
                notes.append("%s: omitted; a config completed none of the %d baseline requests" % (w, base_count))
            continue
        if notes is not None and base_count > len(keys):
            notes.append("%s: values cover the %d of %d baseline requests that every config completed"
                         % (w, len(keys), base_count))
        base_rate = None
        if base:
            base_rate = mean(base[k]["tok_s"] for k in keys)
            ph["%s.baseline" % w] = fmt_rate(base_rate)
            ph["%s.baseline.tps" % w] = fmt_rate(base_rate)
        for name in names:
            if name == "baseline":
                continue
            current = by_config.get(name, {})
            if not current:
                continue
            ck = config_key(name)
            rate = mean(current[k]["tok_s"] for k in keys)
            drafted = sum(current[k].get("draft_n") or 0 for k in keys)
            accepted = sum(current[k].get("draft_n_accepted") or 0 for k in keys)
            generated = sum(current[k].get("predicted_n") or 0 for k in keys)
            ph["%s.%s.tps" % (w, ck)] = fmt_rate(rate)
            ph["%s.%s.accept" % (w, ck)] = fmt_pct((accepted / drafted) if drafted else None)
            ph["%s.%s.tps_step" % (w, ck)] = fmt_step(tokens_per_step(generated, accepted))
            speedup = None
            if base and base_rate and rate is not None:
                speedup = rate / base_rate
            ph["%s.%s.speedup" % (w, ck)] = fmt_x(speedup)


def single_placeholders(single, ph):
    """single.<cfg>.p<i>, mean, and for drafters speedup, accept and tps_step.

    `passes` holds one position per attempted pass; a failed pass is None
    and prints as n/a in its own position. The mean and the speedup come
    from the successful passes. A config with no successful pass is skipped.
    """
    configs = single.get("configs") if isinstance(single.get("configs"), dict) else single
    entries = {}
    for name, entry in (configs or {}).items():
        if not isinstance(entry, dict) or not entry.get("passes"):
            continue
        passes = list(entry["passes"])
        values = [p for p in passes if p is not None]
        if not values:
            continue
        entries[name] = {
            "passes": passes,
            "mean": mean(values),
            "accepted": entry.get("accepted") or 0,
            "drafted": entry.get("drafted") or 0,
            "predicted_n": entry.get("predicted_n") or 0,
        }
    base = entries.get("baseline")
    for name, e in entries.items():
        ck = config_key(name)
        for i, value in enumerate(e["passes"], 1):
            ph["single.%s.p%d" % (ck, i)] = fmt_rate(value)
        ph["single.%s.mean" % ck] = fmt_rate(e["mean"])
        if name == "baseline":
            continue
        ph["single.%s.speedup" % ck] = fmt_x((e["mean"] / base["mean"]) if base and base["mean"] else None)
        ph["single.%s.accept" % ck] = fmt_pct((e["accepted"] / e["drafted"]) if e["drafted"] else None)
        ph["single.%s.tps_step" % ck] = fmt_step(tokens_per_step(e["predicted_n"], e["accepted"]))


def slot_placeholders(results, ph):
    """slots.<N>.<cfg>.stream/aggregate, and accept/speedup for drafters.

    speedup is the per-stream (decode-only) ratio against the baseline at the
    same slot count; aggregate_speedup is the wall-clock throughput ratio.
    """
    entries = {(e["config"], e["slots"]): e for e in results.get("multi_slot") or []}
    for (name, slots), e in sorted(entries.items(), key=lambda kv: (kv[0][1], kv[0][0])):
        ck = config_key(name)
        # The error key records a server refusal and also the first request
        # error of a run that completed in part, so a partial run stays visible.
        if e.get("error"):
            ph["slots.%d.%s.error" % (slots, ck)] = str(e["error"])
        if not e.get("ok"):
            continue
        ph["slots.%d.%s.stream" % (slots, ck)] = fmt_rate(e.get("per_stream_tok_s"))
        ph["slots.%d.%s.aggregate" % (slots, ck)] = fmt_rate(e.get("aggregate_tok_s"))
        if name == "baseline":
            continue
        ph["slots.%d.%s.accept" % (slots, ck)] = fmt_pct(e.get("accept_rate"))
        base = entries.get(("baseline", slots))
        stream = aggregate = None
        if base and base.get("per_stream_tok_s") and e.get("per_stream_tok_s") is not None:
            stream = e["per_stream_tok_s"] / base["per_stream_tok_s"]
        if base and base.get("aggregate_tok_s") and e.get("aggregate_tok_s") is not None:
            aggregate = e["aggregate_tok_s"] / base["aggregate_tok_s"]
        ph["slots.%d.%s.speedup" % (slots, ck)] = fmt_x(stream)
        ph["slots.%d.%s.aggregate_speedup" % (slots, ck)] = fmt_x(aggregate)


def power_placeholders(results, ph):
    host = (results.get("environment") or {}).get("hostname") or "the benchmark host"
    ph["power.source"] = ("nvidia-smi --query-gpu=power.draw sampled at 1 Hz by a background thread on %s "
                          "while the server ran; mean W over the generation phase, and mJ/token = mean W / "
                          "(generated tokens per wall second) x 1000." % host)
    records = [c for c in results.get("configs") or [] if c.get("slots") == 1 and c.get("power")
               and not c["power"].get("unavailable") and c["power"].get("mean_w") is not None]
    if not records:
        return
    idle = next((c["power"].get("idle_w") for c in records if c["name"] == "baseline"),
                records[0]["power"].get("idle_w"))
    ph["power.idle.w"] = fmt_rate(idle)
    for c in records:
        ck = config_key(c["name"])
        ph["power.%s.w" % ck] = fmt_rate(c["power"].get("mean_w"))
        ph["power.%s.mj" % ck] = fmt_mj(c["power"].get("energy_mj_per_token"))


def exact_placeholders(results, ph):
    for name, report in ((results.get("exactness") or {}).get("configs") or {}).items():
        ck = config_key(name)
        ph["exact.%s.identical" % ck] = str(report.get("identical"))
        ph["exact.%s.total" % ck] = str(report.get("compared"))


def build(results, single=None, notes=None):
    """The placeholder map from a results.json object and an optional single.json object.

    `notes`, when given, receives one line per workload whose values cover
    fewer requests than the baseline completed.
    """
    ph = {}
    defined = results.get("configs_defined") or {}
    for name in results.get("config_names") or []:
        ck = config_key(name)
        # A config added with --add-config takes the column label the run recorded.
        column = (defined.get(name) or {}).get("column") if name != "baseline" else None
        ph["labels.%s" % ck] = LABELS.get(ck) or column or name
    workload_placeholders(results, ph, notes)
    if single is None:
        single = results.get("single")
    if single:
        single_placeholders(single, ph)
    slot_placeholders(results, ph)
    power_placeholders(results, ph)
    exact_placeholders(results, ph)
    return ph


def load_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def parse_args(argv):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("results_dir", help="output directory of a spec_bench run (holds results.json)")
    p.add_argument("--out", default=None, help="output file (default: <results_dir>/placeholders.json)")
    p.add_argument("--single", default=None,
                   help="single.json from single_prompt_bench.py (default: <results_dir>/single.json when present)")
    p.add_argument("--strict", action="store_true", help="exit 1 when an expected key is missing")
    return p.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    results_path = os.path.join(args.results_dir, "results.json")
    if not os.path.isfile(results_path):
        print("fill_placeholders: %s not found" % results_path, file=sys.stderr)
        return 2
    results = load_json(results_path)
    if results.get("schema_version") != 2:
        print("fill_placeholders: warning: results.json schema_version is %r, expected 2"
              % results.get("schema_version"), file=sys.stderr)
    single = None
    single_path = args.single or os.path.join(args.results_dir, "single.json")
    if os.path.isfile(single_path):
        single = load_json(single_path)
        print("fill_placeholders: single prompt data from %s" % single_path)
    elif results.get("single"):
        print("fill_placeholders: single prompt data from results.json")
    else:
        print("fill_placeholders: no single prompt data")
    notes = []
    ph = build(results, single, notes)
    out = args.out or os.path.join(args.results_dir, "placeholders.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(ph, f, indent=1, sort_keys=True)
        f.write("\n")
    missing = [k for k in expected_keys() if k not in ph]
    na = sorted(k for k, v in ph.items() if v == "n/a")
    print("fill_placeholders: wrote %d keys to %s" % (len(ph), out))
    for line in notes:
        print("fill_placeholders: partial workload %s" % line)
    if na:
        print("fill_placeholders: %d keys are n/a: %s" % (len(na), ", ".join(na)))
    if missing:
        print("fill_placeholders: %d expected keys missing: %s" % (len(missing), ", ".join(missing)))
        return 1 if args.strict else 0
    print("fill_placeholders: every expected key is present")
    return 0


if __name__ == "__main__":
    sys.exit(main())
