#!/usr/bin/env python3
"""Run one prompt for several passes per config on a launched llama-server.

The prompt is the quicksort prompt of the PrismML GB10 document. The script
reuses the server launch and the /completion client of spec_bench.py (same
directory) and writes <out>/single.json, which fill_placeholders.py merges
into placeholders.json. It launches one server per config, one at a time,
and stops only the process it started. Standard library only.

Usage: single_prompt_bench.py --out <results_dir> [--configs baseline,dspark-v1,dspark-v2]
       [--add-config NAME=DRAFTER:NMAX] [--server-url NAME=URL] [--repeats 3] [--n-predict 256]
"""

import argparse
import datetime
import json
import os
import socket
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import spec_bench as sb  # noqa: E402

SINGLE_ID = sb.SINGLE_ID
DEFAULT_PROMPT = sb.SINGLE_PROMPT


def utc_now():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_args(argv):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--bin-dir", "--binary-dir", dest="bin_dir", default="bin/cuda",
                   help="directory with llama-server and its libraries (default: bin/cuda)")
    p.add_argument("--model", default=sb.DEFAULT_MODEL, help="target model GGUF")
    p.add_argument("--drafter-v1", default=sb.DEFAULT_DRAFTER_V1, help="DSpark v1 drafter GGUF (config dspark-v1)")
    p.add_argument("--drafter-v2", default=sb.DEFAULT_DRAFTER_V2, help="DSpark v2 drafter GGUF (config dspark-v2)")
    p.add_argument("--configs", default=None,
                   help="comma-separated configs to run (default: every config spec_bench.py defines)")
    p.add_argument("--add-config", action="append", default=[], metavar="NAME=DRAFTER:NMAX",
                   help="add a drafter config, as in spec_bench.py")
    p.add_argument("--server-url", action="append", default=[], metavar="NAME=URL",
                   help="use a running server for config NAME instead of launching one (repeatable)")
    p.add_argument("--server-extra", default="", help="extra llama-server flags, as one quoted string")
    p.add_argument("--prompt", default=DEFAULT_PROMPT, help="the prompt text (default: the quicksort prompt)")
    p.add_argument("--repeats", type=int, default=3, help="passes per config (default: 3)")
    p.add_argument("--n-predict", type=int, default=256, help="token budget per pass (default: 256)")
    p.add_argument("--seed", type=int, default=42, help="sampling seed (default: 42)")
    p.add_argument("--host", default="127.0.0.1", help="bind address for launched servers")
    p.add_argument("--port", type=int, default=8099, help="port for launched servers (default: 8099)")
    p.add_argument("--ctx", type=int, default=16384, help="context size for launched servers (default: 16384)")
    p.add_argument("--load-timeout", type=int, default=600, help="seconds to wait for /health (default: 600)")
    p.add_argument("--request-timeout", type=int, default=900, help="seconds per request (default: 900)")
    p.add_argument("--warmup-tokens", type=int, default=16,
                   help="tokens of one unrecorded warm-up request per server; 0 disables (default: 16)")
    p.add_argument("--allow-busy-gpu", action="store_true",
                   help="launch servers although other processes use the GPU (numbers are then not publishable)")
    p.add_argument("--note", default=None, help="free text stored in single.json")
    p.add_argument("--out", required=True, help="results directory; single.json and server logs go here")
    args = p.parse_args(argv)
    if args.repeats < 1:
        p.error("--repeats must be at least 1")
    return args


def bench_args(args):
    """Build the spec_bench argument namespace, so paths, configs and server flags match the main run."""
    argv = [
        "--bin-dir", args.bin_dir, "--model", args.model,
        "--drafter-v1", args.drafter_v1, "--drafter-v2", args.drafter_v2,
        "--host", args.host, "--port", str(args.port), "--ctx", str(args.ctx),
        "--server-extra", args.server_extra, "--seed", str(args.seed),
        "--load-timeout", str(args.load_timeout), "--request-timeout", str(args.request_timeout),
        "--no-power", "--no-single", "--out", args.out,
    ]
    for item in args.add_config:
        argv += ["--add-config", item]
    for item in args.server_url:
        argv += ["--server-url", item]
    if args.configs:
        argv += ["--configs", args.configs]
    return sb.parse_args(argv)


def summarize_record(record):
    """Per config: one rate per attempted pass (None for a failed pass), mean and counters from the successful ones."""
    ok = [r for r in record["rows"] if r["error"] is None]
    drafted = sum(r["draft_n"] or 0 for r in ok)
    accepted = sum(r["draft_n_accepted"] or 0 for r in ok)
    generated = sum(r["predicted_n"] or 0 for r in ok)
    record.update({
        "passes": sb.positional_passes(record["rows"]),
        "mean_tok_s": sb.mean(r["tok_s"] for r in ok),
        "predicted_n": generated,
        "drafted": drafted,
        "accepted": accepted,
        "accept_rate": (accepted / drafted) if drafted else None,
        "tokens_per_step": sb.tokens_per_step(generated, accepted),
        "speedup": None,
    })


def run_config(args, bargs, name, out_dir, base_outputs):
    """Run every pass against one config. Return (record, outputs per pass)."""
    cfg = sb.CONFIGS[name]
    record = {
        "name": name,
        "column": cfg["column"],
        "mode": "remote" if name in bargs.remote else "launched",
        "url": bargs.remote.get(name),
        "drafter": None,
        "drafter_metadata": None,
        "spec_draft_n_max": cfg["n_max"],
        "server_args": None,
        "props": None,
        "load_seconds": None,
        "rows": [],
        "identical_to_baseline": None,
        "started_utc": utc_now(),
        "error": None,
    }
    outputs = {}
    print("\n=== %s (%s) ===" % (name, record["mode"]))
    server = None
    try:
        if record["mode"] == "launched":
            url = "http://%s:%d" % (bargs.host, bargs.port)
            bin_dir = sb.resolve_path(bargs.bin_dir)
            required = [os.path.join(bin_dir, "llama-server"), sb.resolve_path(bargs.model)]
            if cfg["drafter"] is not None:
                required.append(sb.drafter_path(bargs, cfg))
            for path in required:
                if not os.path.isfile(path):
                    raise sb.BenchError("missing file: %s" % path)
            if cfg["drafter"] is not None:
                record["drafter"] = sb.display_path(required[2])
                record["drafter_metadata"] = sb.read_drafter_metadata(required[2])
            if sb.port_in_use(bargs.host, bargs.port):
                raise sb.BenchError("something already listens on %s:%d; the tool never stops "
                                    "a server it did not start" % (bargs.host, bargs.port))
            command = sb.server_command(bargs, cfg, 1)
            env = dict(os.environ)
            env["LD_LIBRARY_PATH"] = bin_dir + (":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else "")
            record["server_args"] = [sb.display_path(c) for c in command]
            print("  command: %s" % " ".join(record["server_args"]))
            server = sb.LaunchedServer(command, env, os.path.join(out_dir, "single-server-%s.log" % name))
            started = time.monotonic()
            server.start()
            sb.wait_for_health(url, bargs.load_timeout, server)
            record["load_seconds"] = round(time.monotonic() - started, 1)
            print("  healthy after %.1f s" % record["load_seconds"])
        else:
            url = bargs.remote[name]
            sb.wait_for_health(url, bargs.load_timeout)
        record["url"] = url
        record["props"] = sb.fetch_props(url)
        print("  server build %s, model %s, slots %s" % (
            record["props"]["build_info"], record["props"]["model_path"], record["props"]["total_slots"]))
        if args.warmup_tokens > 0:
            sb.warm_up(url, args.warmup_tokens, args.request_timeout)
        prompt = {"id": SINGLE_ID, "prompt": args.prompt}
        for pass_no in range(1, args.repeats + 1):
            if server is not None and not server.alive():
                raise sb.BenchError("llama-server exited during the run; log: %s" % sb.log_excerpt(server.log_path))
            row = {"pass": pass_no, "error": None}
            try:
                result, output = sb.run_completion(url, prompt, args.n_predict, args.seed, args.request_timeout)
            except sb.REQUEST_ERRORS as exc:
                result = {"error": "%s: %s" % (type(exc).__name__, exc)}
                output = None
            row.update(result)
            record["rows"].append(row)
            if output is not None:
                outputs[pass_no] = output
            line = "  pass %d: " % pass_no
            if row["error"] is not None:
                line += "ERROR %s" % row["error"]
            else:
                line += "%4d tok  %7.2f tok/s" % (row["predicted_n"] or 0, row["tok_s"] or 0.0)
                if row["draft_n"]:
                    line += "  accept %.3f (%d/%d)  %.2f tok/step" % (
                        (row["draft_n_accepted"] or 0) / row["draft_n"], row["draft_n_accepted"] or 0,
                        row["draft_n"], row.get("tokens_per_step") or 0.0)
                base = base_outputs.get(pass_no)
                if base is not None:
                    index, unit, _, _ = sb.compare_outputs(base, output)
                    line += "  identical" if index is None else "  differs at %s %d" % (unit, index)
            print(line)
            sys.stdout.flush()
    except sb.CONFIG_ERRORS as exc:
        record["error"] = sb.config_error_text(exc)
        print("  ERROR: %s" % record["error"])
    finally:
        if server is not None:
            server.stop()
    record["finished_utc"] = utc_now()
    summarize_record(record)
    return record, outputs


def identical_to_baseline(base_outputs, outputs):
    """The count "same/compared" over the passes that both the baseline and the config completed, or None.

    Token ids compare when both sides have them; otherwise the text compares.
    The caller runs this after every config, so the order of the configs
    does not matter.
    """
    common = sorted(k for k in outputs if k in base_outputs)
    if not common:
        return None
    same = sum(1 for k in common if sb.compare_outputs(base_outputs[k], outputs[k])[0] is None)
    return "%d/%d" % (same, len(common))


def update_cross_config(data, outputs):
    """Speedup and identity of every drafter config against the baseline, from the runs so far."""
    base = data["configs"].get("baseline")
    base_outputs = outputs.get("baseline") or {}
    for name, entry in data["configs"].items():
        if name == "baseline":
            continue
        entry["speedup"] = None
        if base and base["mean_tok_s"] and entry["mean_tok_s"] is not None:
            entry["speedup"] = entry["mean_tok_s"] / base["mean_tok_s"]
        entry["identical_to_baseline"] = identical_to_baseline(base_outputs, outputs.get(name) or {})


def write_single(out_dir, data, outputs):
    with open(os.path.join(out_dir, "single.json"), "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1)
        f.write("\n")
    dump = [{"config": name, "pass": pass_no, "content": v["content"], "tokens": v["tokens"]}
            for name, by_pass in outputs.items() for pass_no, v in sorted(by_pass.items())]
    with open(os.path.join(out_dir, "single-outputs.json"), "w", encoding="utf-8") as f:
        json.dump(dump, f)
        f.write("\n")


def print_table(data):
    n_pass = data["repeats"]
    print("\nconfig          " + "".join("  pass %d" % i for i in range(1, n_pass + 1)) + "     mean   accept  tok/step  speedup")
    for name in data["config_names"]:
        e = data["configs"].get(name)
        if e is None:
            continue
        if e["error"] and not e["passes"]:
            print("%-16s ERROR %s" % (name, e["error"]))
            continue
        # A failed pass keeps its position and prints as n/a.
        cells = "".join("     n/a" if v is None else "  %6.2f" % v for v in e["passes"])
        cells += "        " * (n_pass - len(e["passes"]))
        accept = "   n/a " if e["accept_rate"] is None else "  %.3f" % e["accept_rate"]
        step = "     n/a" if e["tokens_per_step"] is None else "  %6.2f" % e["tokens_per_step"]
        speedup = "     n/a" if e["speedup"] is None else "  %5.2fx" % e["speedup"]
        print("%-16s%s  %7.2f%s%s%s" % (name, cells, e["mean_tok_s"] or 0.0, accept, step, speedup))


def main(argv=None):
    args = parse_args(argv)
    bargs = bench_args(args)
    out_dir = sb.resolve_path(args.out)
    os.makedirs(out_dir, exist_ok=True)
    launched = [name for name in bargs.config_names if name not in bargs.remote]
    if launched:
        apps = sb.gpu_compute_apps()
        if apps and not args.allow_busy_gpu:
            raise SystemExit("the GPU is in use by: %s. Numbers from a shared GPU are not publishable. "
                             "Wait for an idle GPU or pass --allow-busy-gpu." % ", ".join(a["name"] for a in apps))
    tokens = args.n_predict * args.repeats
    print("single_prompt_bench: configs %s, %d passes x %d tokens each, seed %d, temperature 0"
          % (", ".join(bargs.config_names), args.repeats, args.n_predict, args.seed))
    print("  prompt: %s" % args.prompt)
    print("  ETA about %d min (%d tokens per config at %.0f tok/s plus %.0f s per model load)" % (
        sum((tokens / (sb.ETA_PLAIN_TOK_S if sb.CONFIGS[n]["drafter"] is None else sb.ETA_DRAFT_TOK_S))
            + (sb.ETA_LOAD_S if n in launched else 0.0) for n in bargs.config_names) / 60 + 1,
        tokens, sb.ETA_PLAIN_TOK_S, sb.ETA_LOAD_S))
    print("  output: %s" % sb.display_path(os.path.join(out_dir, "single.json")))
    sys.stdout.flush()

    data = {
        "tool": "single_prompt_bench",
        "schema_version": 1,
        "created_utc": utc_now(),
        "note": args.note,
        "prompt_id": SINGLE_ID,
        "prompt": args.prompt,
        "n_predict": args.n_predict,
        "repeats": args.repeats,
        "seed": args.seed,
        "request": {"endpoint": "/completion", "temperature": 0.0, "cache_prompt": False,
                    "template": "chatml, applied by the client, no system message"},
        "mode": "server-url" if bargs.remote else "launch",
        "config_names": bargs.config_names,
        "environment": sb.probe_environment(bargs),
        "configs": {},
    }
    outputs = {}
    started = time.monotonic()
    try:
        for name in bargs.config_names:
            record, config_outputs = run_config(args, bargs, name, out_dir, outputs.get("baseline", {}))
            data["configs"][name] = record
            outputs[name] = config_outputs
            # Every config that ran so far is compared again, so a baseline
            # that runs after a drafter still gives that drafter its figures.
            update_cross_config(data, outputs)
            write_single(out_dir, data, outputs)
    except KeyboardInterrupt:
        print("\ninterrupted; partial results written")
        write_single(out_dir, data, outputs)
        return 130
    data["elapsed_seconds"] = round(time.monotonic() - started, 1)
    write_single(out_dir, data, outputs)
    print_table(data)
    print("\ndone in %.1f min; wrote %s" % (data["elapsed_seconds"] / 60, sb.display_path(os.path.join(out_dir, "single.json"))))
    failed = [n for n, e in data["configs"].items() if e["error"] or any(r["error"] for r in e["rows"])]
    if failed:
        print("configs with errors: %s" % ", ".join(failed))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
