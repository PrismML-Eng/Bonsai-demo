#!/usr/bin/env python3
"""Speculative decoding benchmark for llama-server: speed, tool calls, agent turns, slots, power.

The tool starts one llama-server per configuration and slot count (a baseline
with no drafter, then the DSpark v2 drafter), sends the same prompts at
temperature 0, and records the decode timings and draft counters that the
server returns. The matrix and long prompts go to /completion with a
client-side ChatML template. The tool and agent prompts go to
/v1/chat/completions with a tools list and the server's own template. With
more than one slot the tool fires prompts concurrently in waves. While a
server runs, a background thread samples the GPU power draw with nvidia-smi.
It then compares every drafter output with the baseline output.

The tool uses the Python standard library only. See README.md in this
directory for usage, the output format and the definition of exactness.
"""

import argparse
import collections
import datetime
import hashlib
import json
import os
import platform
import re
import shlex
import socket
import struct
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import fill_placeholders  # noqa: E402  (the placeholder map has one producer)


def find_demo_dir():
    """The demo directory is the nearest ancestor that holds setup.sh and scripts/."""
    env = os.environ.get("BONSAI_DEMO_DIR")
    if env:
        return os.path.abspath(env)
    d = HERE
    for _ in range(8):
        if os.path.isfile(os.path.join(d, "setup.sh")) and os.path.isdir(os.path.join(d, "scripts")):
            return d
        parent = os.path.dirname(d)
        if parent == d:
            break
        d = parent
    return os.getcwd()


DEMO_DIR = find_demo_dir()

DEFAULT_MODEL = "models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-PQ2_0.gguf"
# The v1 file is PrismML's Ternary-Bonsai-27B drafter (header name
# Bonsai-27B-dspark, block size 4). The runtime clamps n-max to its block size.
DEFAULT_DRAFTER_V1 = "models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-dspark-dflash-Q4_0.gguf"
DEFAULT_DRAFTER_V2 = "models/bonsai2-gguf/27B/Ternary-Bonsai-2-27B-dspark-dflash-v2-Q4_K_M.gguf"

# Benchmark configurations, in run order. "drafter" is None for no drafter,
# "v1" for the --drafter-v1 file, "v2" for the --drafter-v2 file, or "path"
# for a file given with --add-config. "column" is the table header used in
# the markdown summary.
CONFIGS = {
    "baseline": {"drafter": None, "n_max": None, "column": "no drafter"},
    "dspark-v1": {"drafter": "v1", "n_max": 4, "column": "DSpark v1 (Ternary-Bonsai-27B drafter, K=4)"},
    "dspark-v2": {"drafter": "v2", "n_max": 5, "column": "DSpark v2 (K=5)"},
}
# The single prompt of the PrismML GB10 document, run for several passes.
SINGLE_ID = "single-quicksort"
SINGLE_PROMPT = "Implement quicksort in Python with type hints, tests, and a concise complexity explanation"
CATEGORY_ORDER = ["code", "math", "reasoning", "chat", "long-form"]
# Prompt sets that go to /v1/chat/completions with a tools list.
CHAT_SETS = ("tool", "agent")
# The prompts that every multi-slot run fires concurrently, in waves.
CONCURRENCY_IDS = ["code-01", "code-02", "chat-01", "chat-02",
                   "reasoning-01", "reasoning-02", "tool-01", "tool-02"]
REASONING_EFFORTS = ("template", "xhigh", "medium", "low")

# Assumptions behind the ETA that the tool prints before the run. The ETA is
# an upper bound: n_predict is a cap and many answers stop early.
ETA_PLAIN_TOK_S = 30.0
ETA_DRAFT_TOK_S = 60.0
ETA_PREFILL_TOK_S = 250.0
ETA_LOAD_S = 60.0
ETA_REQUEST_OVERHEAD_S = 1.0
# Rough templated prompt length per set, for the prefill part of the ETA.
ETA_PREFIX_TOKENS = {"matrix": 80, "long": 100, "tool": 870, "agent": 3200, "single": 40}

POWER_INTERVAL_S = 1.0

# GGUF header value types.
GGUF_SCALAR = {
    0: "B", 1: "b", 2: "H", 3: "h", 4: "I", 5: "i", 6: "f", 7: "?",
    10: "Q", 11: "q", 12: "d",
}
GGUF_STRING = 8
GGUF_ARRAY = 9
DRAFTER_KEYS = ("general.architecture", "general.name", "dflash.block_size",
                "dflash.block_count", "dspark.dspark.block_size")


class BenchError(Exception):
    """A configuration could not run. The tool records it and continues."""


class HttpError(Exception):
    """An HTTP error answer. The body usually carries the server's message."""

    def __init__(self, code, body):
        Exception.__init__(self, "HTTP %d: %s" % (code, body))
        self.code = code
        self.body = body


# ---------------------------------------------------------------------------
# Small helpers


def utc_now():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def sha256_text(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def mean(values):
    values = [v for v in values if v is not None]
    return sum(values) / len(values) if values else None


def fmt_minutes(seconds):
    return "%d min" % (int(seconds) // 60 + 1)


def resolve_path(path):
    """Resolve a relative path against the demo directory, like the shell scripts do."""
    if os.path.isabs(path):
        return path
    return os.path.join(DEMO_DIR, path)


def display_path(path):
    """Show a path inside the demo directory relative to it."""
    if path.startswith(DEMO_DIR + os.sep):
        return os.path.relpath(path, DEMO_DIR)
    return path


def file_record(path):
    """Path, size and SHA-256 of a model file, for the results header."""
    return {"path": display_path(path), "bytes": os.path.getsize(path), "sha256": sha256_file(path)}


def run_quiet(args, env=None, timeout=30):
    """Run a command and return its combined output, or an empty string."""
    try:
        proc = subprocess.run(
            args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env,
            timeout=timeout, check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return ""
    return proc.stdout.decode("utf-8", "replace").strip()


def chat_prompt(text):
    """Apply the ChatML template that Bonsai 2 uses, with no system message.

    The client applies the template so every server sees the same bytes.
    A server started with different --chat-template-kwargs would otherwise
    change the prompt through /apply-template.
    """
    return "<|im_start|>user\n" + text + "<|im_end|>\n<|im_start|>assistant\n"


def first_diff(a, b):
    """Return the index of the first position where two sequences differ.

    Return None when the sequences are identical. When one is a prefix of
    the other, return the length of the shorter one.
    """
    n = min(len(a), len(b))
    for i in range(n):
        if a[i] != b[i]:
            return i
    if len(a) == len(b):
        return None
    return n


def gguf_metadata(path, prefixes):
    """Read GGUF header keys that start with one of the given prefixes.

    The function reads only the key/value header, not the tensor data.
    Array values are reported by their length.
    """
    found = {}
    with open(path, "rb") as f:

        def read(fmt):
            return struct.unpack("<" + fmt, f.read(struct.calcsize(fmt)))[0]

        def read_string():
            return f.read(read("Q")).decode("utf-8", "replace")

        def read_value(value_type):
            if value_type in GGUF_SCALAR:
                return read(GGUF_SCALAR[value_type])
            if value_type == GGUF_STRING:
                return read_string()
            if value_type == GGUF_ARRAY:
                element_type = read("I")
                count = read("Q")
                if element_type in GGUF_SCALAR:
                    f.seek(struct.calcsize(GGUF_SCALAR[element_type]) * count, os.SEEK_CUR)
                else:
                    for _ in range(count):
                        read_value(element_type)
                return "array[%d]" % count
            raise ValueError("unknown GGUF value type %d" % value_type)

        if f.read(4) != b"GGUF":
            raise ValueError("%s is not a GGUF file" % path)
        read("I")  # format version
        read("Q")  # tensor count
        n_kv = read("Q")
        for _ in range(n_kv):
            key = read_string()
            value = read_value(read("I"))
            if any(key.startswith(p) for p in prefixes):
                found[key] = value
    return found


def read_drafter_metadata(path):
    """The drafter header keys, or a BenchError that names the file and the defect."""
    try:
        return gguf_metadata(path, DRAFTER_KEYS)
    except (OSError, ValueError, struct.error) as exc:
        raise BenchError("cannot read the GGUF header of %s: %s" % (display_path(path), exc))


def drafter_block_size(metadata):
    """The drafter block size: dflash.block_size, else dspark.dspark.block_size, else None."""
    for key in ("dflash.block_size", "dspark.dspark.block_size"):
        value = (metadata or {}).get(key)
        if isinstance(value, int):
            return value
    return None


# ---------------------------------------------------------------------------
# HTTP


def http_json(url, body=None, timeout=30):
    data = None
    headers = {}
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        text = exc.read().decode("utf-8", "replace")[:600]
        raise HttpError(exc.code, text.strip())


REQUEST_ERRORS = (urllib.error.URLError, socket.timeout, ValueError, OSError, HttpError, KeyError, TypeError)
# Errors of one configuration run outside a request (/props, warm-up, a bad
# GGUF header, a server that does not start). The tool records them in the
# config record and continues with the next configuration.
CONFIG_ERRORS = (BenchError, struct.error) + REQUEST_ERRORS


def config_error_text(exc):
    """The error text of a config record: the BenchError message, or the type and message."""
    if isinstance(exc, BenchError):
        return str(exc)
    return "%s: %s" % (type(exc).__name__, exc)


def port_in_use(host, port):
    try:
        with socket.create_connection((host, port), timeout=1):
            return True
    except OSError:
        return False


def fetch_props(url):
    props = http_json(url + "/props", timeout=30)
    settings = props.get("default_generation_settings") or {}
    caps = props.get("chat_template_caps") or {}
    return {
        "build_info": props.get("build_info"),
        "model_path": props.get("model_path"),
        "model_alias": props.get("model_alias"),
        "total_slots": props.get("total_slots"),
        "n_ctx": settings.get("n_ctx"),
        "supports_tools": caps.get("supports_tools"),
    }


# ---------------------------------------------------------------------------
# GPU power sampling


def parse_gpu_sample(line):
    """Parse one nvidia-smi csv line: power.draw, utilization.gpu, memory.used.

    A field can be "[N/A]" (for example memory.used on a unified memory
    GPU); such a field becomes None.
    """
    cols = [c.strip() for c in line.split(",")]
    if len(cols) < 3:
        return None

    def number(text, cast):
        try:
            return cast(text)
        except ValueError:
            return None

    return {"power_w": number(cols[0], float), "util_pct": number(cols[1], int),
            "memory_mib": number(cols[2], int)}


def sample_gpu(gpu_index):
    out = run_quiet(["nvidia-smi", "-i", str(gpu_index),
                     "--query-gpu=power.draw,utilization.gpu,memory.used",
                     "--format=csv,noheader,nounits"], timeout=10)
    if not out:
        return None
    return parse_gpu_sample(out.splitlines()[0])


class PowerSampler(threading.Thread):
    """Sample the GPU at a fixed interval in the background, tagged with a phase.

    The main thread sets `phase` to "idle" (model loaded, no requests),
    "warmup" or "generation". The thread stops on its own when nvidia-smi
    is missing or fails.
    """

    def __init__(self, gpu_index, interval=POWER_INTERVAL_S):
        threading.Thread.__init__(self, daemon=True)
        self.gpu_index = gpu_index
        self.interval = interval
        self.phase = "idle"
        self.samples = []
        self.available = None
        self._stop_event = threading.Event()
        self._lock = threading.Lock()

    def run(self):
        while not self._stop_event.is_set():
            sample = sample_gpu(self.gpu_index)
            if sample is None:
                self.available = False
                return
            self.available = True
            sample["phase"] = self.phase
            sample["t"] = time.monotonic()
            with self._lock:
                self.samples.append(sample)
            self._stop_event.wait(self.interval)

    def stop(self):
        self._stop_event.set()
        self.join(timeout=15)
        with self._lock:
            return list(self.samples)


def energy_mj_per_token(mean_w, tok_s):
    """Energy per generated token in millijoules: mean watts / tokens per second * 1000."""
    if mean_w is None or not tok_s:
        return None
    return mean_w / tok_s * 1000.0


def power_summary(samples, tokens, generation_seconds):
    """Reduce the samples of one server run to idle and generation figures."""
    idle = [s for s in samples if s["phase"] == "idle" and s["power_w"] is not None]
    gen = [s for s in samples if s["phase"] == "generation" and s["power_w"] is not None]
    tok_s_wall = (tokens / generation_seconds) if generation_seconds and tokens else None
    mean_w = mean(s["power_w"] for s in gen)
    return {
        "idle_samples": len(idle),
        "idle_w": mean(s["power_w"] for s in idle),
        "generation_samples": len(gen),
        "mean_w": mean_w,
        "max_w": max(s["power_w"] for s in gen) if gen else None,
        "util_pct_mean": mean(s["util_pct"] for s in gen),
        "memory_mib_max": max([s["memory_mib"] for s in gen if s["memory_mib"] is not None] or [None]),
        "tokens": tokens,
        "generation_seconds": round(generation_seconds, 1),
        "tok_s_wall": tok_s_wall,
        "energy_mj_per_token": energy_mj_per_token(mean_w, tok_s_wall),
    }


# ---------------------------------------------------------------------------
# Server lifecycle


class LaunchedServer:
    """One llama-server process. The tool stops only the process it started."""

    def __init__(self, command, env, log_path):
        self.command = command
        self.env = env
        self.log_path = log_path
        self.log = None
        self.proc = None

    def start(self):
        self.log = open(self.log_path, "wb")
        self.proc = subprocess.Popen(
            self.command, stdout=self.log, stderr=subprocess.STDOUT,
            stdin=subprocess.DEVNULL, env=self.env,
        )
        print("  started llama-server pid %d, log %s" % (self.proc.pid, display_path(self.log_path)))

    def alive(self):
        return self.proc is not None and self.proc.poll() is None

    def stop(self):
        if self.proc is not None and self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=30)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait()
            print("  stopped llama-server pid %d (exit %s)" % (self.proc.pid, self.proc.returncode))
        if self.log is not None:
            self.log.close()
            self.log = None


LOG_ERROR_WORDS = ("error", "fail", "abort", "assert", "invalid", "not supported", "unsupported", "cannot")


def log_excerpt(path, limit=6):
    """The last log lines that look like an error, or the last lines of the log."""
    try:
        with open(path, "rb") as f:
            lines = f.read().decode("utf-8", "replace").splitlines()
    except OSError:
        return ""
    lines = [ln.strip() for ln in lines if ln.strip()]
    hits = [ln for ln in lines if any(w in ln.lower() for w in LOG_ERROR_WORDS)]
    picked = hits[-limit:] if hits else lines[-limit:]
    return " | ".join(picked)


def wait_for_health(url, timeout, server=None):
    """Poll /health until the server answers ok, or fail.

    A server answers 503 while it loads the model. When the tool launched
    the server, an early exit of the process ends the wait at once.
    """
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if server is not None and not server.alive():
            raise BenchError(
                "llama-server exited with code %d before it was ready; log: %s"
                % (server.proc.returncode, log_excerpt(server.log_path) or display_path(server.log_path))
            )
        try:
            health = http_json(url + "/health", timeout=5)
            if health.get("status") == "ok":
                return
        except (urllib.error.URLError, socket.timeout, ConnectionError, ValueError, HttpError):
            pass
        time.sleep(1)
    raise BenchError("%s did not answer /health with status ok within %d s" % (url, timeout))


def drafter_path(args, cfg):
    if cfg["drafter"] == "v1":
        return resolve_path(args.drafter_v1)
    if cfg["drafter"] == "v2":
        return resolve_path(args.drafter_v2)
    if cfg["drafter"] == "path":
        return resolve_path(cfg["path"])
    return None


def server_command(args, cfg, slots=1):
    """Build the llama-server command line for a configuration and slot count."""
    command = [
        os.path.join(resolve_path(args.bin_dir), "llama-server"),
        "-m", resolve_path(args.model),
        "--host", args.host,
        "--port", str(args.port),
        "-ngl", "999",
        "-fa", "on",
        "-c", str(args.ctx),
        "-np", str(slots),
        "--jinja",
    ]
    if cfg["drafter"] is not None:
        command += [
            "-md", drafter_path(args, cfg),
            "--spec-type", "draft-dspark",
            "--spec-draft-n-max", str(cfg["n_max"]),
            "-ngld", "999",
        ]
    return command + shlex.split(args.server_extra)


# ---------------------------------------------------------------------------
# Requests


def tokens_per_step(predicted_n, accepted):
    """Generated tokens per verify step.

    Every step yields exactly one target-sampled token plus the accepted
    draft tokens, so steps = predicted_n - accepted. Without a drafter the
    figure is 1.0.
    """
    if not predicted_n:
        return None
    steps = predicted_n - (accepted or 0)
    return (predicted_n / steps) if steps > 0 else None


def draft_counters_present(row):
    """Whether a response carried draft counters: True, False, or None when unknown.

    Only a response with server timings can answer. A wall-timed chat row
    (no timings) and a failed request leave the state unknown. Presence is
    the test, not a nonzero value: a drafter that drafted nothing on a short
    answer still reports draft_n 0.
    """
    if row.get("error") is not None or row.get("timings_source") != "timings":
        return None
    return row.get("draft_n") is not None


def timings_row(timings):
    return {
        "prompt_n": timings.get("prompt_n"),
        "prompt_ms": timings.get("prompt_ms"),
        "predicted_n": timings.get("predicted_n"),
        "predicted_ms": timings.get("predicted_ms"),
        "tok_s": timings.get("predicted_per_second"),
        "draft_n": timings.get("draft_n"),
        "draft_n_accepted": timings.get("draft_n_accepted"),
        "tokens_per_step": tokens_per_step(timings.get("predicted_n"), timings.get("draft_n_accepted")),
    }


def run_completion(url, prompt, n_predict, seed, timeout):
    """Send one /completion request and return (row, output)."""
    body = {
        "prompt": chat_prompt(prompt["prompt"]),
        "n_predict": n_predict,
        "temperature": 0.0,
        "seed": seed,
        "cache_prompt": False,
        "return_tokens": True,
    }
    started = time.monotonic()
    resp = http_json(url + "/completion", body, timeout=timeout)
    wall_ms = (time.monotonic() - started) * 1000.0
    # A server that ignores return_tokens sends no token ids. The output
    # then keeps tokens as None and the exactness check compares the text.
    tokens = resp.get("tokens")
    if not isinstance(tokens, list):
        tokens = None
    content = resp.get("content") or ""
    row = timings_row(resp.get("timings") or {})
    row.update({
        "endpoint": "completion",
        "timings_source": "timings",
        "finish_reason": resp.get("stop_type"),
        "truncated": resp.get("truncated"),
        "output_tokens": None if tokens is None else len(tokens),
        "output_chars": len(content),
        "output_sha256": sha256_text(content),
        "tokens_sha256": None if tokens is None else sha256_text(",".join(str(t) for t in tokens)),
        "wall_ms": round(wall_ms, 1),
        "error": None,
    })
    return row, {"tokens": tokens, "content": content}


def compare_outputs(a, b):
    """Compare two outputs. Return (first_diff index or None, unit, length a, length b).

    Outputs with token ids on both sides compare by token id. Otherwise
    (chat outputs, or a server that returned no ids) they compare as text.
    """
    if a["tokens"] is not None and b["tokens"] is not None:
        return first_diff(a["tokens"], b["tokens"]), "token", len(a["tokens"]), len(b["tokens"])
    return first_diff(a["content"], b["content"]), "char", len(a["content"]), len(b["content"])


def chat_messages(prompt, data):
    """Build the messages and tools of a chat request for a tool or agent prompt."""
    if prompt["set"] == "tool":
        return [{"role": "user", "content": prompt["prompt"]}], data["tools"]
    call = prompt["tool_call"]
    messages = [
        {"role": "system", "content": "\n".join(data["agent_system"])},
        {"role": "user", "content": prompt["prompt"]},
        {"role": "assistant", "content": "", "tool_calls": [{
            "id": "call_1", "type": "function",
            "function": {"name": call["name"], "arguments": json.dumps(call["arguments"])}}]},
        {"role": "tool", "tool_call_id": "call_1", "name": call["name"],
         "content": "\n".join(prompt["tool_result"])},
    ]
    return messages, data["agent_tools"]


def chat_body(messages, tools, n_predict, seed, reasoning_effort):
    body = {
        "messages": messages,
        "tools": tools,
        "tool_choice": "auto",
        "max_tokens": n_predict,
        "temperature": 0.0,
        "seed": seed,
        "cache_prompt": False,
        "stream": False,
    }
    if reasoning_effort != "template":
        body["chat_template_kwargs"] = {"reasoning_effort": reasoning_effort}
    return body


def parse_arguments(value):
    """Tool call arguments as a dict, and whether they were well formed."""
    if isinstance(value, dict):
        return value, True
    if isinstance(value, str):
        try:
            parsed = json.loads(value)
        except ValueError:
            return None, False
        return (parsed, True) if isinstance(parsed, dict) else (parsed, False)
    return None, False


TOOL_CALL_BLOCK = re.compile(r"<tool_call>(.*?)</tool_call>", re.S)
FUNCTION_BLOCK = re.compile(r"<function=([^>\s]+)>(.*?)</function>", re.S)
PARAMETER_BLOCK = re.compile(r"<parameter=([^>\s]+)>\n?(.*?)\n?</parameter>", re.S)


def parse_tool_calls(message):
    """Return the tool calls in a chat completion message.

    The server returns structured `tool_calls` when its parser understood the
    output. Otherwise the raw text may still hold `<tool_call>` blocks, as
    JSON or as the `<function=name><parameter=k>v</parameter></function>`
    form of the Bonsai 2 template; those are parsed here as a fallback.
    Each record has name, arguments, well_formed and source.
    """
    calls = []
    for call in message.get("tool_calls") or []:
        function = call.get("function") or {}
        name = function.get("name")
        arguments, ok = parse_arguments(function.get("arguments"))
        calls.append({"name": name, "arguments": arguments,
                      "well_formed": ok and isinstance(name, str) and bool(name),
                      "source": "structured"})
    if calls:
        return calls
    content = message.get("content") or ""
    for block in TOOL_CALL_BLOCK.findall(content):
        block = block.strip()
        try:
            parsed = json.loads(block)
        except ValueError:
            parsed = None
        if isinstance(parsed, dict):
            arguments, ok = parse_arguments(parsed.get("arguments"))
            name = parsed.get("name")
            calls.append({"name": name, "arguments": arguments,
                          "well_formed": ok and isinstance(name, str) and bool(name),
                          "source": "text-json"})
            continue
        functions = FUNCTION_BLOCK.findall(block)
        if not functions:
            calls.append({"name": None, "arguments": None, "well_formed": False, "source": "text-unparsed"})
        for name, inner in functions:
            arguments = {k: v for k, v in PARAMETER_BLOCK.findall(inner)}
            calls.append({"name": name, "arguments": arguments, "well_formed": True, "source": "text-xml"})
    return calls


def tool_call_valid(calls, known_names):
    """True when there is at least one call, every call is well formed and names a known tool."""
    if not calls:
        return False
    return all(c["well_formed"] and c["name"] in known_names for c in calls)


def run_chat(url, prompt, data, n_predict, seed, timeout, reasoning_effort, hash_template):
    """Send one /v1/chat/completions request and return (row, output).

    Speed comes from the `timings` object that this llama-server build adds
    to chat completions. When a build omits it, the row falls back to
    `usage.completion_tokens` over the request wall time and says so in
    `timings_source`.
    """
    messages, tools = chat_messages(prompt, data)
    body = chat_body(messages, tools, n_predict, seed, reasoning_effort)
    templated_sha256 = None
    if hash_template:
        # The templated prompt is hashed so the exactness report can tell a
        # changed output from a changed prompt (a different server template).
        template_body = {"messages": messages, "tools": tools}
        if "chat_template_kwargs" in body:
            template_body["chat_template_kwargs"] = body["chat_template_kwargs"]
        try:
            templated_sha256 = sha256_text(http_json(url + "/apply-template", template_body, timeout=60)["prompt"])
        except REQUEST_ERRORS:
            templated_sha256 = None
    started = time.monotonic()
    resp = http_json(url + "/v1/chat/completions", body, timeout=timeout)
    wall_ms = (time.monotonic() - started) * 1000.0
    choice = (resp.get("choices") or [{}])[0]
    message = choice.get("message") or {}
    content = message.get("content") or ""
    reasoning = message.get("reasoning_content") or ""
    calls = parse_tool_calls(message)
    usage = resp.get("usage") or {}
    timings = resp.get("timings")
    if timings:
        row = timings_row(timings)
        row["timings_source"] = "timings"
    else:
        n = usage.get("completion_tokens")
        row = {"prompt_n": usage.get("prompt_tokens"), "prompt_ms": None, "predicted_n": n,
               "predicted_ms": round(wall_ms, 1), "tok_s": (n / wall_ms * 1000.0) if n and wall_ms else None,
               "draft_n": None, "draft_n_accepted": None, "tokens_per_step": tokens_per_step(n, None),
               "timings_source": "wall"}
    # The text that exactness compares: reasoning, answer and tool calls.
    text = reasoning + "\n<answer>\n" + content + "\n<tool_calls>\n" + json.dumps(
        [{"name": c["name"], "arguments": c["arguments"]} for c in calls], sort_keys=True)
    known = {t["function"]["name"] for t in tools}
    row.update({
        "endpoint": "chat",
        "finish_reason": choice.get("finish_reason"),
        "truncated": choice.get("finish_reason") == "length",
        "output_tokens": usage.get("completion_tokens"),
        "output_chars": len(content),
        "reasoning_chars": len(reasoning),
        "output_sha256": sha256_text(text),
        "tokens_sha256": None,
        "templated_sha256": templated_sha256,
        "tool_calls": [c["name"] for c in calls],
        "tool_call_sources": sorted({c["source"] for c in calls}),
        "tool_call_valid": tool_call_valid(calls, known),
        "tool_call_expected": (prompt.get("expect_tool") in [c["name"] for c in calls]) if prompt.get("expect_tool") else None,
        "wall_ms": round(wall_ms, 1),
        "error": None,
    })
    return row, {"tokens": None, "content": text}


def warm_up(url, n_tokens, timeout):
    body = {
        "prompt": chat_prompt("Reply with the word ready."),
        "n_predict": n_tokens,
        "temperature": 0.0,
        "cache_prompt": False,
    }
    http_json(url + "/completion", body, timeout=timeout)


def run_prompt(args, url, prompt, data, name, slots, pass_no, wave):
    """Run one prompt on the endpoint of its set. Errors become a row with `error`."""
    row = {
        "config": name, "slots": slots, "prompt_id": prompt["id"], "category": prompt["category"],
        "set": prompt["set"], "pass": pass_no, "wave": wave, "n_predict": prompt["n_predict"],
    }
    output = {"tokens": None, "content": ""}
    try:
        if prompt["set"] in CHAT_SETS:
            result, output = run_chat(url, prompt, data, prompt["n_predict"], args.seed,
                                      args.request_timeout, args.reasoning_effort, hash_template=(slots == 1))
        else:
            result, output = run_completion(url, prompt, prompt["n_predict"], args.seed, args.request_timeout)
    except REQUEST_ERRORS as exc:
        result = {"endpoint": "chat" if prompt["set"] in CHAT_SETS else "completion",
                  "error": "%s: %s" % (type(exc).__name__, exc)}
    row.update(result)
    return row, output


def run_wave(args, url, batch, data, name, slots, pass_no, wave):
    """Fire one request per prompt in the batch at the same time. Return rows, outputs, wall seconds."""
    results = [None] * len(batch)

    def worker(i, prompt):
        results[i] = run_prompt(args, url, prompt, data, name, slots, pass_no, wave)

    threads = [threading.Thread(target=worker, args=(i, p), daemon=True) for i, p in enumerate(batch)]
    started = time.monotonic()
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    wall = time.monotonic() - started
    return [r[0] for r in results], [r[1] for r in results], wall


# ---------------------------------------------------------------------------
# Summary


def group_definitions(prompts):
    """Return (label, predicate) pairs for the summary rows, in table order."""
    groups = []
    matrix = [p for p in prompts if p["set"] == "matrix"]
    long_set = [p for p in prompts if p["set"] == "long"]
    for category in CATEGORY_ORDER:
        if any(p["category"] == category for p in matrix):
            groups.append((category, lambda p, c=category: p["set"] == "matrix" and p["category"] == c))
    for set_name in CHAT_SETS:
        if any(p["set"] == set_name for p in prompts):
            groups.append((set_name, lambda p, s=set_name: p["set"] == s))
    if matrix:
        groups.append(("blended (%d prompts)" % len(matrix), lambda p: p["set"] == "matrix"))
    if long_set:
        budgets = "/".join(str(n) for n in sorted({p["n_predict"] for p in long_set}))
        label = "long-form (%d prompts, %s tokens)" % (len(long_set), budgets)
        groups.append((label, lambda p: p["set"] == "long"))
    return groups


def index_rows(rows, name, slots=1):
    """Map (prompt_id, pass) to the row of one configuration and slot count, errors excluded."""
    return {
        (r["prompt_id"], r["pass"]): r
        for r in rows if r["config"] == name and r.get("slots", 1) == slots and r["error"] is None
    }


def weighted_rate(rows):
    """Total generated tokens divided by total decode time, in tokens per second."""
    ms = sum(r["predicted_ms"] or 0.0 for r in rows)
    return (sum(r["predicted_n"] or 0 for r in rows) / ms * 1000.0) if ms else None


def summarize(prompts, rows, config_names):
    """Build the per-configuration workload tables from the single-slot rows."""
    by_id = {p["id"]: p for p in prompts}
    groups = group_definitions(prompts)
    base = index_rows(rows, "baseline") if "baseline" in config_names else {}
    tables = {}
    for name in config_names:
        if name == "baseline":
            continue
        current = index_rows(rows, name)
        table = []
        for label, predicate in groups:
            keys = sorted(k for k in current if k[0] in by_id and predicate(by_id[k[0]]))
            if base:
                keys = [k for k in keys if k in base]
            if not keys:
                continue
            drafted = sum(current[k]["draft_n"] or 0 for k in keys)
            accepted = sum(current[k]["draft_n_accepted"] or 0 for k in keys)
            generated = sum(current[k]["predicted_n"] or 0 for k in keys)
            entry = {
                "workload": label,
                "prompts": len(keys),
                "with_drafter_tok_s": mean(current[k]["tok_s"] for k in keys),
                "with_drafter_weighted_tok_s": weighted_rate([current[k] for k in keys]),
                "with_drafter_prompt_n": mean(current[k]["prompt_n"] for k in keys),
                "with_drafter_tokens_per_step": tokens_per_step(generated, accepted),
                "drafted": drafted,
                "accepted": accepted,
                "accept_rate": (accepted / drafted) if drafted else None,
                "no_drafter_tok_s": None,
                "no_drafter_weighted_tok_s": None,
                "no_drafter_tokens_per_step": None,
                "speedup": None,
            }
            if base:
                entry["no_drafter_tok_s"] = mean(base[k]["tok_s"] for k in keys)
                entry["no_drafter_weighted_tok_s"] = weighted_rate([base[k] for k in keys])
                entry["no_drafter_tokens_per_step"] = tokens_per_step(
                    sum(base[k]["predicted_n"] or 0 for k in keys),
                    sum(base[k]["draft_n_accepted"] or 0 for k in keys))
                if entry["no_drafter_tok_s"]:
                    entry["speedup"] = entry["with_drafter_tok_s"] / entry["no_drafter_tok_s"]
            table.append(entry)
        tables[name] = table

    baseline_only = None
    if base:
        baseline_only = []
        for label, predicate in groups:
            keys = sorted(k for k in base if k[0] in by_id and predicate(by_id[k[0]]))
            if keys:
                baseline_only.append({
                    "workload": label,
                    "prompts": len(keys),
                    "no_drafter_tok_s": mean(base[k]["tok_s"] for k in keys),
                    "no_drafter_weighted_tok_s": weighted_rate([base[k] for k in keys]),
                    "no_drafter_prompt_n": mean(base[k]["prompt_n"] for k in keys),
                    "no_drafter_tokens_per_step": tokens_per_step(
                        sum(base[k]["predicted_n"] or 0 for k in keys),
                        sum(base[k]["draft_n_accepted"] or 0 for k in keys)),
                })
    return {"tables": tables, "baseline": baseline_only}


def long_form_table(prompts, rows, config_names):
    """One entry per long prompt: baseline rate, every drafter rate, acceptance and speedup."""
    long_ids = [p["id"] for p in prompts if p["set"] == "long"]
    indexed = {name: index_rows(rows, name) for name in config_names}
    entries = []
    for pid in long_ids:
        entry = {"prompt_id": pid, "configs": {}}
        base = indexed.get("baseline", {}).get((pid, 1))
        for name in config_names:
            r = indexed[name].get((pid, 1))
            if r is None:
                continue
            item = {"tok_s": r["tok_s"], "predicted_n": r["predicted_n"],
                    "accept_rate": (r["draft_n_accepted"] or 0) / r["draft_n"] if r["draft_n"] else None,
                    "tokens_per_step": tokens_per_step(r["predicted_n"], r["draft_n_accepted"]),
                    "speedup": None}
            if base is not None and name != "baseline" and base["tok_s"]:
                item["speedup"] = (r["tok_s"] or 0.0) / base["tok_s"]
            entry["configs"][name] = item
        entries.append(entry)
    return entries


def tool_call_summary(rows, config_names):
    """Per configuration: how many tool prompts produced a well-formed call for a known tool."""
    report = {}
    for name in config_names:
        tool_rows = [r for r in rows if r["config"] == name and r.get("slots", 1) == 1
                     and r["set"] == "tool" and r["error"] is None]
        finish = collections.Counter(r.get("finish_reason") for r in tool_rows)
        sources = collections.Counter(s for r in tool_rows for s in (r.get("tool_call_sources") or []))
        report[name] = {
            "prompts": len(tool_rows),
            "valid": sum(1 for r in tool_rows if r.get("tool_call_valid")),
            "expected_tool": sum(1 for r in tool_rows if r.get("tool_call_expected")),
            "valid_rate": (sum(1 for r in tool_rows if r.get("tool_call_valid")) / len(tool_rows)) if tool_rows else None,
            "finish_reasons": dict(finish),
            "sources": dict(sources),
            "wall_timed": sum(1 for r in tool_rows if r.get("timings_source") == "wall"),
        }
    return report


def slot_summary(rows, config_records, subset_ids):
    """One entry per (config, slots) run: per-stream and aggregate rates over the subset prompts."""
    entries = []
    for rec in config_records:
        name, slots = rec["name"], rec["slots"]
        selected = [r for r in rows if r["config"] == name and r.get("slots", 1) == slots
                    and r["prompt_id"] in subset_ids]
        ok = [r for r in selected if r["error"] is None]
        tokens = sum(r["predicted_n"] or 0 for r in ok)
        if slots == 1:
            wall_s = sum((r["wall_ms"] or 0.0) for r in ok) / 1000.0
        else:
            wall_s = rec.get("wave_seconds") or 0.0
        drafted = sum(r["draft_n"] or 0 for r in ok)
        accepted = sum(r["draft_n_accepted"] or 0 for r in ok)
        first_error = next((r["error"] for r in selected if r["error"] is not None), None)
        # draft_fields: True when a response carried draft counters, False
        # when the server timings carried none, None when every response
        # was wall timed (no timings, so the state is unknown).
        states = [s for s in (draft_counters_present(r) for r in ok) if s is not None]
        draft_fields = any(states) if states else None
        entries.append({
            "config": name,
            "slots": slots,
            "prompts": len(selected),
            "ok": len(ok),
            "errors": len(selected) - len(ok),
            "per_stream_tok_s": mean(r["tok_s"] for r in ok),
            "aggregate_tok_s": (tokens / wall_s) if wall_s and tokens else None,
            "tokens": tokens,
            "wall_seconds": round(wall_s, 1),
            "drafted": drafted,
            "accepted": accepted,
            "accept_rate": (accepted / drafted) if drafted else None,
            "tokens_per_step": tokens_per_step(tokens, accepted),
            "draft_fields": draft_fields,
            "error": rec["error"] or first_error,
        })
    return entries


def positional_passes(rows):
    """One rate per attempted pass, in pass order. A failed pass holds None."""
    passes = [None] * max([r["pass"] for r in rows] or [0])
    for r in rows:
        if r["error"] is None:
            passes[r["pass"] - 1] = r.get("tok_s")
    return passes


def single_summary(rows, config_names, single_id=SINGLE_ID):
    """Per config: the decode rate of every pass of the single prompt, the mean, acceptance and speedup.

    `passes` keeps one position per attempted pass; a failed pass is None.
    The mean, the counters and the speedup come from the successful passes.
    """
    report = {}
    for name in config_names:
        attempted = [r for r in rows if r["config"] == name and r.get("slots", 1) == 1
                     and r["prompt_id"] == single_id]
        if not attempted:
            continue
        ok = [r for r in attempted if r["error"] is None]
        drafted = sum(r["draft_n"] or 0 for r in ok)
        accepted = sum(r["draft_n_accepted"] or 0 for r in ok)
        generated = sum(r["predicted_n"] or 0 for r in ok)
        report[name] = {
            "passes": positional_passes(attempted),
            "mean_tok_s": mean(r["tok_s"] for r in ok),
            "predicted_n": generated,
            "drafted": drafted,
            "accepted": accepted,
            "accept_rate": (accepted / drafted) if drafted else None,
            "tokens_per_step": tokens_per_step(generated, accepted),
            "speedup": None,
        }
    base = report.get("baseline")
    for name, entry in report.items():
        if name != "baseline" and base and base["mean_tok_s"] and entry["mean_tok_s"] is not None:
            entry["speedup"] = entry["mean_tok_s"] / base["mean_tok_s"]
    return report


def exactness(rows, outputs, config_names, repeats):
    """Compare every drafter output with the baseline output for the same prompt and pass.

    /completion outputs compare by token id; chat outputs compare by text
    (reasoning, answer and tool calls) because the chat endpoint returns no
    token ids. The unit of `first_diff` is recorded per difference.
    """
    if "baseline" not in config_names:
        return None
    base = index_rows(rows, "baseline")
    compare = compare_outputs
    report = {"configs": {}, "baseline_passes_identical": None}
    for name in config_names:
        if name == "baseline":
            continue
        current = index_rows(rows, name)
        keys = sorted(k for k in current if k in base)
        diffs = []
        for key in keys:
            a = outputs[("baseline", 1) + key]
            b = outputs[(name, 1) + key]
            index, unit, len_a, len_b = compare(a, b)
            if index is not None:
                diff = {"prompt_id": key[0], "pass": key[1], "first_diff": index, "unit": unit,
                        "baseline_length": len_a, "config_length": len_b}
                ta, tb = base[key].get("templated_sha256"), current[key].get("templated_sha256")
                if ta and tb and ta != tb:
                    diff["templated_prompt_differs"] = True
                diffs.append(diff)
        report["configs"][name] = {
            "compared": len(keys),
            "identical": len(keys) - len(diffs),
            "diffs": diffs,
        }
    if repeats > 1 or any(pass_no > 1 for (_, pass_no) in base):
        # A baseline that changes between passes would make the comparison
        # above meaningless, so the report says whether it was stable.
        unstable = []
        for (prompt_id, pass_no) in sorted(base):
            if pass_no == 1 or (prompt_id, 1) not in base:
                continue
            a = outputs[("baseline", 1, prompt_id, 1)]
            b = outputs[("baseline", 1, prompt_id, pass_no)]
            index, unit, _, _ = compare(a, b)
            if index is not None:
                unstable.append({"prompt_id": prompt_id, "pass": pass_no, "first_diff": index, "unit": unit})
        report["baseline_passes_identical"] = not unstable
        report["baseline_unstable"] = unstable
    return report


def fmt_rate(value):
    return "n/a" if value is None else "%.2f" % value


def fmt_accept(entry):
    if not entry["drafted"]:
        return "n/a"
    return "%.3f (%d/%d)" % (entry["accept_rate"], entry["accepted"], entry["drafted"])


def fmt_speedup(value):
    return "n/a" if value is None else "**%.2fx**" % value


def fmt_watts(value):
    return "n/a" if value is None else "%.1f" % value


def render_markdown(header, summary, exact, configs, rows, extras):
    config_names = header["config_names"]
    env = header["environment"]
    lines = ["# Speculative decoding benchmark", ""]
    if header["note"]:
        lines += ["Note: %s" % header["note"], ""]
    lines += [
        "Generated %s on %s (%s, driver %s, CUDA %s). llama-server %s, build %s."
        % (header["created_utc"], env["hostname"], env["gpu_name"] or "unknown GPU",
           env["driver_version"] or "?", env["cuda_version"] or "?",
           env["llama_server_version"] or "version unknown", header.get("build_info") or "?"),
        "",
        "Prompts: %s. Passes per prompt: %d. Slots: %s. Rates are arithmetic means of the "
        "server decode-only `predicted_per_second`; acceptance is aggregated "
        "accepted/drafted tokens; speedup is the ratio of the two means over the "
        "same prompts. The tool and agent rows come from `/v1/chat/completions` "
        "with a tools list and the server template (reasoning effort: %s); the other "
        "rows come from `/completion` with a client-side ChatML template.%s"
        % (header["prompt_summary"], header["repeats"],
           ", ".join(str(s) for s in header["slots"]), header["reasoning_effort"],
           (" The single quicksort prompt runs %d passes at %d tokens on every single-slot server."
            % (header["single"]["repeats"], header["single"]["n_predict"])) if header.get("single") else ""),
        "",
    ]
    # The tool writes the summary after every run, so runs that did not
    # happen yet are absent from the config records.
    single = {c["name"]: c for c in configs if c["slots"] == 1}
    drafters = [n for n in config_names if n != "baseline"]
    for name in drafters:
        cfg = single.get(name)
        lines += ["## Workload matrix: %s" % name, ""]
        if cfg is None:
            lines += ["Not run yet.", ""]
            continue
        if cfg["error"]:
            lines += ["Not run: %s" % cfg["error"], ""]
            continue
        lines += [
            "| workload | no drafter | %s | accept | tok/step | speedup |" % CONFIGS[name]["column"],
            "| --- | ---: | ---: | ---: | ---: | ---: |",
        ]
        for entry in summary["tables"].get(name, []):
            lines.append("| %s | %s | %s | %s | %s | %s |" % (
                entry["workload"], fmt_rate(entry["no_drafter_tok_s"]),
                fmt_rate(entry["with_drafter_tok_s"]), fmt_accept(entry),
                fmt_rate(entry["with_drafter_tokens_per_step"]), fmt_speedup(entry["speedup"])))
        lines.append("")
        agent = next((e for e in summary["tables"].get(name, []) if e["workload"] == "agent"), None)
        if agent and agent.get("with_drafter_prompt_n"):
            lines += ["The agent prompts carry a mean prefix of %d tokens (system prompt, tools, task, "
                      "one tool result) before generation starts." % round(agent["with_drafter_prompt_n"]), ""]
    if summary["baseline"] and not drafters:
        lines += ["## Workload matrix: baseline", "", "| workload | no drafter |", "| --- | ---: |"]
        for entry in summary["baseline"]:
            lines.append("| %s | %s |" % (entry["workload"], fmt_rate(entry["no_drafter_tok_s"])))
        lines.append("")

    if drafters and any(summary["tables"].get(n) for n in drafters):
        lines += ["`tok/step` is generated tokens per verify step, predicted_n / (predicted_n - accepted); "
                  "a server without a drafter is at 1.00.", ""]

    long_entries = extras.get("long_form") or []
    if long_entries:
        head = "| prompt | no drafter |"
        sep = "| --- | ---: |"
        for name in drafters:
            head += " %s | accept | tok/step | speedup |" % CONFIGS[name]["column"]
            sep += " ---: | ---: | ---: | ---: |"
        lines += ["## Long-form prompts", "", "Per prompt, pass 1, tokens per second.", "", head, sep]
        for entry in long_entries:
            base = entry["configs"].get("baseline")
            line = "| %s | %s |" % (entry["prompt_id"], fmt_rate(base["tok_s"]) if base else "n/a")
            for name in drafters:
                item = entry["configs"].get(name)
                if item is None:
                    line += " n/a | n/a | n/a | n/a |"
                    continue
                accept = "n/a" if item["accept_rate"] is None else "%.3f" % item["accept_rate"]
                line += " %s | %s | %s | %s |" % (fmt_rate(item["tok_s"]), accept,
                                                 fmt_rate(item["tokens_per_step"]), fmt_speedup(item["speedup"]))
            lines.append(line)
        lines.append("")

    single = extras.get("single") or {}
    if single:
        n_pass = max(len(e["passes"]) for e in single.values())
        head = "| config |" + "".join(" pass %d |" % i for i in range(1, n_pass + 1)) + " mean | accept | tok/step | speedup |"
        sep = "| --- |" + " ---: |" * n_pass + " ---: | ---: | ---: | ---: |"
        lines += ["## Single prompt", "",
                  "The quicksort prompt of the PrismML GB10 document (%d tokens, %d passes), tokens per second per pass."
                  % (header.get("single", {}).get("n_predict") or 0, n_pass), "", head, sep]
        for name in config_names:
            e = single.get(name)
            if e is None:
                continue
            cells = [fmt_rate(v) for v in e["passes"]] + ["n/a"] * (n_pass - len(e["passes"]))
            accept = "n/a" if e["accept_rate"] is None else "%.3f (%d/%d)" % (e["accept_rate"], e["accepted"], e["drafted"])
            lines.append("| %s | %s | %s | %s | %s | %s |" % (
                name, " | ".join(cells), fmt_rate(e["mean_tok_s"]), accept,
                fmt_rate(e["tokens_per_step"]), fmt_speedup(e["speedup"])))
        lines.append("")

    if exact is not None:
        lines += [
            "## Exactness", "",
            "Each drafter output is compared with the baseline output for the same "
            "prompt and pass. `/completion` outputs are identical when their token id "
            "sequences are equal; chat outputs (reasoning, answer, tool calls) are "
            "compared as text because that endpoint returns no token ids. For a "
            "different output the table lists the 0-based index of the first "
            "differing token or character; when one output is a prefix of the "
            "other, the index equals the shorter length.", "",
            "| config | identical | first difference |",
            "| --- | ---: | --- |",
        ]
        for name, report in exact["configs"].items():
            detail = "; ".join(
                "%s%s: %s %d%s" % (d["prompt_id"], "" if header["repeats"] == 1 else " pass %d" % d["pass"],
                                   d["unit"], d["first_diff"],
                                   " (templated prompt differs)" if d.get("templated_prompt_differs") else "")
                for d in report["diffs"])
            lines.append("| %s | %d/%d | %s |" % (name, report["identical"], report["compared"], detail))
        lines.append("")
        if exact["baseline_passes_identical"] is not None:
            state = "identical" if exact["baseline_passes_identical"] else "NOT identical"
            lines += ["Baseline outputs across passes: %s." % state, ""]

    tools = extras.get("tool_calls") or {}
    if any(v["prompts"] for v in tools.values()):
        lines += [
            "## Tool calls", "",
            "A tool prompt is valid when the answer holds at least one well-formed call "
            "(a name from the tools list and a JSON object of arguments). `expected` counts "
            "the answers that call the tool the prompt asks for. `structured` means the "
            "server returned `tool_calls`; `text-*` means the call was parsed from the text.", "",
            "| config | valid | expected | finish reasons | source |",
            "| --- | ---: | ---: | --- | --- |",
        ]
        for name in config_names:
            t = tools.get(name)
            if not t or not t["prompts"]:
                continue
            finish = ", ".join("%s %d" % (k, v) for k, v in sorted(t["finish_reasons"].items(), key=lambda kv: str(kv[0])))
            source = ", ".join("%s %d" % (k, v) for k, v in sorted(t["sources"].items()))
            lines.append("| %s | %d/%d | %d/%d | %s | %s |" % (
                name, t["valid"], t["prompts"], t["expected_tool"], t["prompts"], finish, source or "none"))
        lines.append("")
        if any(t["wall_timed"] for t in tools.values()):
            lines += ["Some chat responses carried no `timings`; their rate is completion tokens "
                      "over wall time, prefill included.", ""]

    slot_entries = extras.get("slots") or []
    if any(e["slots"] > 1 for e in slot_entries) or len(header["slots"]) > 1:
        lines += [
            "## Multi-slot", "",
            "Each run fires the same %d prompts (%s) in waves of `slots` concurrent requests. "
            "`per stream` is the mean decode rate that each request saw; `aggregate` is generated "
            "tokens over the wall time of all waves, prefill included. The `slots 1` row uses the "
            "same prompts from the single-slot run." % (len(extras.get("subset_ids") or []),
                                                          ", ".join(extras.get("subset_ids") or [])), "",
            "| config | slots | prompts | per stream tok/s | aggregate tok/s | accept | result |",
            "| --- | ---: | ---: | ---: | ---: | ---: | --- |",
        ]
        for e in slot_entries:
            if e["error"] and not e["ok"]:
                result = "ERROR: %s" % e["error"]
            elif e["errors"]:
                result = "%d of %d requests failed: %s" % (e["errors"], e["prompts"], e["error"])
            elif CONFIGS.get(e["config"], {}).get("drafter") and e["draft_fields"] is False:
                result = "no draft counters in the responses (speculation not engaged)"
            elif CONFIGS.get(e["config"], {}).get("drafter") and e["draft_fields"] is None:
                result = "ok (wall timed, no draft counters available)"
            else:
                result = "ok"
            accept = "n/a" if e["accept_rate"] is None else "%.3f" % e["accept_rate"]
            # `prompts` counts the attempted requests; `result` says how many failed.
            lines.append("| %s | %d | %d | %s | %s | %s | %s |" % (
                e["config"], e["slots"], e["prompts"], fmt_rate(e["per_stream_tok_s"]),
                fmt_rate(e["aggregate_tok_s"]), accept, result))
        lines.append("")

    powered = [c for c in configs if c.get("power")]
    if powered:
        lines += [
            "## Power", "",
            "`nvidia-smi` sampled at 1 Hz on %s. Idle is the mean draw over %d s with the model "
            "loaded and no request in flight. Mean and max cover the generation phase. "
            "`gen tok/s` is generated tokens over the wall time of that phase, prefill included, "
            "and mJ/token is mean W / gen tok/s x 1000.%s" % (
                env["hostname"], header["power_idle_s"],
                " In server-url mode the samples come from the client host, which may not run the server."
                if header["mode"] == "server-url" else ""), "",
            "| config | slots | idle W | mean W | max W | util % | tokens | gen tok/s | mJ/token |",
            "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
        ]
        for c in powered:
            p = c["power"]
            if p.get("unavailable"):
                lines.append("| %s | %d | n/a | n/a | n/a | n/a | n/a | n/a | %s |" % (c["name"], c["slots"], p["unavailable"]))
                continue
            lines.append("| %s | %d | %s | %s | %s | %s | %d | %s | %s |" % (
                c["name"], c["slots"], fmt_watts(p["idle_w"]), fmt_watts(p["mean_w"]), fmt_watts(p["max_w"]),
                "n/a" if p["util_pct_mean"] is None else "%.0f" % p["util_pct_mean"], p["tokens"],
                fmt_rate(p["tok_s_wall"]), fmt_watts(p["energy_mj_per_token"])))
        lines.append("")

    failed = [r for r in rows if r["error"] is not None]
    if failed:
        lines += ["## Errors", ""]
        for r in failed:
            lines.append("- %s slots %d %s pass %d: %s" % (r["config"], r.get("slots", 1), r["prompt_id"], r["pass"], r["error"]))
        lines.append("")

    lines += ["## Configuration", ""]
    for cfg in configs:
        props = cfg["props"] or {}
        label = "`%s` slots %d" % (cfg["name"], cfg["slots"])
        if cfg["mode"] == "launched" and cfg["server_args"]:
            lines.append("- %s: `%s`" % (label, " ".join(cfg["server_args"])))
        elif cfg["mode"] == "launched":
            lines.append("- %s: not started" % label)
        else:
            lines.append("- %s: remote server %s (not launched by the tool; its flags are its own)"
                         % (label, cfg["url"]))
        if props:
            load = "" if cfg.get("load_seconds") is None else ", load %s s" % cfg["load_seconds"]
            lines.append("  build %s, model `%s`, slots %s, n_ctx %s%s"
                         % (props.get("build_info"), props.get("model_path"),
                            props.get("total_slots"), props.get("n_ctx"), load))
        if cfg["drafter_metadata"]:
            lines.append("  drafter metadata: %s" % json.dumps(cfg["drafter_metadata"], sort_keys=True))
        if cfg["error"]:
            lines.append("  error: %s" % cfg["error"])
    apps = env["gpu_compute_apps"]
    lines += [
        "- GPU: %s" % (env.get("gpu_smi_line") or "nvidia-smi not found"),
        "- GPU processes at start: %s" % (
            ", ".join("%s (%s)" % (a["name"], a["used_memory"]) for a in apps) if apps else "none"),
        "- Matrix and long prompts: POST /completion, temperature 0, seed %d, cache_prompt false, "
        "ChatML template applied by the client, no system message" % header["seed"],
        "- Tool and agent prompts: POST /v1/chat/completions, temperature 0, seed %d, cache_prompt false, "
        "tools list with tool_choice auto, server template (--jinja)" % header["seed"],
        "- Draft counters: `timings.draft_n` and `timings.draft_n_accepted` from each response",
        "",
    ]
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Environment


def gpu_compute_apps():
    """Return the compute processes that nvidia-smi reports on the GPU."""
    apps = []
    out = run_quiet(["nvidia-smi", "--query-compute-apps=pid,process_name,used_memory",
                     "--format=csv,noheader"])
    for line in out.splitlines():
        cols = [c.strip() for c in line.split(",")]
        if len(cols) >= 2 and cols[0].isdigit():
            apps.append({"pid": int(cols[0]), "name": cols[1],
                         "used_memory": cols[2] if len(cols) > 2 else None})
    return apps


def probe_environment(args):
    bin_dir = resolve_path(args.bin_dir)
    env = dict(os.environ)
    env["LD_LIBRARY_PATH"] = bin_dir + (":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else "")
    smi_line = run_quiet(["nvidia-smi", "--query-gpu=name,driver_version", "--format=csv,noheader"])
    smi = run_quiet(["nvidia-smi", "--query-gpu=name,driver_version,utilization.gpu",
                     "--format=csv,noheader,nounits"])
    gpu_name = driver = utilization = None
    cols = [c.strip() for c in smi.splitlines()[0].split(",")] if smi else []
    if len(cols) >= 3:
        gpu_name, driver = cols[0], cols[1]
        utilization = int(cols[2]) if cols[2].isdigit() else None
    cuda_version = None
    for line in run_quiet(["nvidia-smi"]).splitlines():
        if "CUDA Version:" in line:
            cuda_version = line.split("CUDA Version:")[1].split("|")[0].strip()
            break
    nvcc = None
    for line in run_quiet(["nvcc", "--version"]).splitlines():
        if "release" in line:
            nvcc = line.strip()
    server_bin = os.path.join(bin_dir, "llama-server")
    version = None
    if os.path.isfile(server_bin):
        out = run_quiet([server_bin, "--version"], env=env)
        version = out.splitlines()[0].strip() if out else None
    return {
        "hostname": socket.gethostname(),
        "platform": platform.platform(),
        "python": platform.python_version(),
        "gpu_name": gpu_name,
        "driver_version": driver,
        "gpu_smi_line": smi_line.splitlines()[0].strip() if smi_line else None,
        "cuda_version": cuda_version,
        "nvcc": nvcc,
        "gpu_utilization_pct": utilization,
        "gpu_compute_apps": gpu_compute_apps(),
        "llama_server": display_path(server_bin) if os.path.isfile(server_bin) else None,
        "llama_server_version": version,
    }


# ---------------------------------------------------------------------------
# CLI


def parse_server_url(value):
    if "=" not in value:
        raise argparse.ArgumentTypeError("expected NAME=URL, got %r" % value)
    name, url = value.split("=", 1)
    if name not in CONFIGS:
        raise argparse.ArgumentTypeError("unknown config %r (choose from %s)" % (name, ", ".join(CONFIGS)))
    return name, url.rstrip("/")


def parse_add_config(value):
    """NAME=DRAFTER:NMAX adds a drafter configuration with the given draft length."""
    if "=" not in value or ":" not in value.split("=", 1)[1]:
        raise argparse.ArgumentTypeError("expected NAME=DRAFTER:NMAX, got %r" % value)
    name, rest = value.split("=", 1)
    path, n_max = rest.rsplit(":", 1)
    if not name or name in ("baseline",) or not path or not n_max.isdigit():
        raise argparse.ArgumentTypeError("expected NAME=DRAFTER:NMAX, got %r" % value)
    return name, {"drafter": "path", "path": path, "n_max": int(n_max), "column": "+ %s (K=%s)" % (name, n_max)}


def parse_slots(value):
    try:
        slots = [int(s) for s in value.split(",") if s.strip()]
    except ValueError:
        raise argparse.ArgumentTypeError("expected a comma-separated list of slot counts, got %r" % value)
    if not slots or any(s < 1 for s in slots):
        raise argparse.ArgumentTypeError("slot counts must be positive integers, got %r" % value)
    return slots


def parse_args(argv):
    p = argparse.ArgumentParser(
        description="Benchmark llama-server speculative decoding: baseline vs the DSpark v2 drafter, "
                    "over chat, code, math, reasoning, long-form, tool-call and agent prompts, "
                    "with multi-slot concurrency, GPU power and an output exactness check.")
    p.add_argument("--bin-dir", "--binary-dir", dest="bin_dir", default="bin/cuda",
                   help="directory with llama-server and its libraries (default: bin/cuda)")
    p.add_argument("--model", default=DEFAULT_MODEL, help="target model GGUF")
    p.add_argument("--drafter-v1", default=DEFAULT_DRAFTER_V1,
                   help="DSpark v1 drafter GGUF, the Ternary-Bonsai-27B drafter with block size 4 (config dspark-v1)")
    p.add_argument("--drafter-v2", default=DEFAULT_DRAFTER_V2,
                   help="DSpark v2 drafter GGUF (config dspark-v2)")
    p.add_argument("--configs", default=None,
                   help="comma-separated subset of the configs (default: every config, %s, plus every "
                        "--add-config; with --server-url, the named configs)" % ",".join(CONFIGS))
    p.add_argument("--add-config", action="append", type=parse_add_config, default=[], metavar="NAME=DRAFTER:NMAX",
                   help="add a drafter config with its own draft length, for example dspark-v2-k7=path.gguf:7")
    p.add_argument("--server-url", action="append", default=[], metavar="NAME=URL",
                   help="use a running server for config NAME instead of launching one "
                        "(repeatable; sets --configs to the named configs unless given)")
    p.add_argument("--server-extra", default="",
                   help="extra llama-server flags for every launched server, as one quoted string")
    p.add_argument("--slots", type=parse_slots, default=[1],
                   help="comma-separated server slot counts; each count is a separate server launch "
                        "with -np N and N concurrent requests (default: 1)")
    p.add_argument("--slot-prompt-ids", default=",".join(CONCURRENCY_IDS),
                   help="prompt ids that the multi-slot runs fire in waves (default: %s)" % ",".join(CONCURRENCY_IDS))
    p.add_argument("--prompts", default=os.path.join(HERE, "prompts.json"), help="prompt set JSON")
    p.add_argument("--prompt-ids", default=None, help="comma-separated prompt ids to run")
    p.add_argument("--categories", default=None, help="comma-separated categories to run")
    p.add_argument("--limit", type=int, default=None, help="run only the first N selected prompts")
    p.add_argument("--n-predict", type=int, default=None,
                   help="override n_predict for the matrix, tool and agent sets (default: from prompts.json)")
    p.add_argument("--n-predict-long", type=int, default=None,
                   help="override n_predict for the long set (default: from prompts.json)")
    p.add_argument("--repeats", type=int, default=1, help="passes per prompt (default: 1)")
    p.add_argument("--single-prompt", default=SINGLE_PROMPT,
                   help="text of the single prompt that every single-slot server runs for --single-repeats passes")
    p.add_argument("--single-repeats", type=int, default=3, help="passes of the single prompt (default: 3)")
    p.add_argument("--single-n-predict", type=int, default=256, help="token budget of the single prompt (default: 256)")
    p.add_argument("--no-single", action="store_true", help="skip the single prompt passes")
    p.add_argument("--seed", type=int, default=42, help="sampling seed sent with every request (default: 42)")
    p.add_argument("--reasoning-effort", choices=REASONING_EFFORTS, default="template",
                   help="chat_template_kwargs.reasoning_effort for the chat requests; "
                        "'template' keeps the template default, xhigh on Bonsai 2 (default: template)")
    p.add_argument("--host", default="127.0.0.1", help="bind address for launched servers")
    p.add_argument("--port", type=int, default=8099, help="port for launched servers (default: 8099)")
    p.add_argument("--ctx", type=int, default=16384,
                   help="context size for launched servers; llama-server divides it over the slots (default: 16384)")
    p.add_argument("--load-timeout", type=int, default=600, help="seconds to wait for /health (default: 600)")
    p.add_argument("--request-timeout", type=int, default=900, help="seconds per request (default: 900)")
    p.add_argument("--warmup-tokens", type=int, default=16,
                   help="tokens of one unrecorded warm-up request per server; 0 disables (default: 16)")
    p.add_argument("--power-idle-s", type=int, default=10,
                   help="seconds of idle power sampling before the first request of a server (default: 10)")
    p.add_argument("--no-power", action="store_true", help="do not sample GPU power with nvidia-smi")
    p.add_argument("--gpu-index", type=int, default=0, help="GPU index for nvidia-smi power sampling (default: 0)")
    p.add_argument("--allow-busy-gpu", action="store_true",
                   help="launch servers although other processes use the GPU (numbers are then not publishable)")
    p.add_argument("--plan-only", action="store_true",
                   help="print the plan with the ETA and the server commands, then exit without a run")
    p.add_argument("--out", default=None,
                   help="output directory (default: <tool dir>/results/<UTC timestamp>)")
    p.add_argument("--note", default=None, help="free text recorded in the JSON header and the summary")
    args = p.parse_args(argv)

    for name, cfg in args.add_config:
        CONFIGS[name] = cfg
    try:
        remote = dict(parse_server_url(v) for v in args.server_url)
    except argparse.ArgumentTypeError as exc:
        p.error(str(exc))
    if args.configs is None:
        if remote:
            args.config_names = [name for name in CONFIGS if name in remote]
        else:
            args.config_names = list(CONFIGS)
    else:
        args.config_names = [c.strip() for c in args.configs.split(",") if c.strip()]
        # A config added on the command line is meant to run.
        for name, _ in args.add_config:
            if name not in args.config_names:
                args.config_names.append(name)
    for name in args.config_names:
        if name not in CONFIGS:
            p.error("unknown config %r (choose from %s)" % (name, ", ".join(CONFIGS)))
    args.remote = remote
    args.prompts = resolve_path(args.prompts)
    args.slot_ids = [s.strip() for s in args.slot_prompt_ids.split(",") if s.strip()]
    if args.repeats < 1:
        p.error("--repeats must be at least 1")
    if args.single_repeats < 1:
        p.error("--single-repeats must be at least 1")
    if args.out is None:
        stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d-%H%M%S")
        args.out = os.path.join(HERE, "results", stamp)
    return args


def load_prompts(args):
    """Return (prompts, data). `data` keeps the tools and the agent system prompt."""
    with open(args.prompts, "r", encoding="utf-8") as f:
        data = json.load(f)
    sets = data["sets"]
    prompts = []
    for p in data["prompts"]:
        n_predict = sets[p["set"]]["n_predict"]
        if p["set"] in ("matrix",) + CHAT_SETS and args.n_predict is not None:
            n_predict = args.n_predict
        if p["set"] == "long" and args.n_predict_long is not None:
            n_predict = args.n_predict_long
        prompts.append(dict(p, n_predict=n_predict))
    if args.prompt_ids:
        wanted = [s.strip() for s in args.prompt_ids.split(",") if s.strip()]
        by_id = {p["id"]: p for p in prompts}
        missing = [w for w in wanted if w not in by_id]
        if missing:
            raise SystemExit("unknown prompt ids: %s" % ", ".join(missing))
        prompts = [by_id[w] for w in wanted]
    if args.categories:
        wanted = {s.strip() for s in args.categories.split(",") if s.strip()}
        prompts = [p for p in prompts if p["category"] in wanted]
    if args.limit is not None:
        prompts = prompts[: args.limit]
    if not prompts:
        raise SystemExit("no prompts selected")
    if any(p["set"] in CHAT_SETS for p in prompts):
        for key in ("tools", "agent_tools", "agent_system"):
            if key not in data:
                raise SystemExit("%s lacks %r, which the tool and agent prompts need" % (args.prompts, key))
    return prompts, data


def slot_subset(prompts, slot_ids):
    """The prompts that a multi-slot run fires: the fixed subset, or the first 8 selected."""
    subset = [p for p in prompts if p["id"] in slot_ids]
    return subset or prompts[:8]


def prompt_summary(prompts):
    parts = []
    for set_name in ("matrix", "long") + CHAT_SETS:
        subset = [p for p in prompts if p["set"] == set_name]
        if subset:
            budgets = "/".join(str(n) for n in sorted({p["n_predict"] for p in subset}))
            parts.append("%d %s prompts x %s tokens" % (len(subset), set_name, budgets))
    return ", ".join(parts)


def plan_runs(args, prompts, subset):
    """One entry per (config, slots) run with its prompt count, token cap and ETA in seconds."""
    plan = []
    for name in args.config_names:
        rate = ETA_PLAIN_TOK_S if CONFIGS[name]["drafter"] is None else ETA_DRAFT_TOK_S
        for slots in args.slots:
            selected = prompts if slots == 1 else subset
            requests = len(selected) * args.repeats
            tokens = sum(p["n_predict"] for p in selected) * args.repeats
            prefix = sum(ETA_PREFIX_TOKENS.get(p["set"], 100) for p in selected) * args.repeats
            single_requests = args.single_repeats if (slots == 1 and not args.no_single) else 0
            requests += single_requests
            tokens += single_requests * args.single_n_predict
            prefix += single_requests * ETA_PREFIX_TOKENS["single"]
            # Concurrent requests share the GPU; the aggregate rate is taken
            # as the single-stream rate, an upper bound on the time.
            seconds = tokens / rate + prefix / ETA_PREFILL_TOK_S + requests * ETA_REQUEST_OVERHEAD_S
            if name not in args.remote:
                seconds += ETA_LOAD_S
            if not args.no_power:
                seconds += args.power_idle_s
            plan.append({"config": name, "slots": slots, "prompts": len(selected), "requests": requests,
                         "single_requests": single_requests, "tokens": tokens, "seconds": seconds})
    return plan


def print_plan(args, plan, out_dir):
    total = sum(e["seconds"] for e in plan)
    print("spec_bench: %d runs (%d configs x %d slot counts), %d passes" % (
        len(plan), len(args.config_names), len(args.slots), args.repeats))
    for e in plan:
        kind = "full prompt set" if e["slots"] == 1 else "concurrency subset in waves of %d" % e["slots"]
        if e.get("single_requests"):
            kind += " + single prompt x %d passes" % e["single_requests"]
        print("  %-12s slots %d: %3d prompts (%s), %2d requests, at most %6d tokens, ETA %s" % (
            e["config"], e["slots"], e["prompts"], kind, e["requests"], e["tokens"], fmt_minutes(e["seconds"])))
    print("  total ETA about %s (assumes %.0f tok/s plain, %.0f tok/s with a drafter, %.0f tok/s prefill, "
          "%.0f s per model load, %d s idle power window; prompts that stop early finish sooner)" % (
              fmt_minutes(total), ETA_PLAIN_TOK_S, ETA_DRAFT_TOK_S, ETA_PREFILL_TOK_S, ETA_LOAD_S,
              0 if args.no_power else args.power_idle_s))
    print("  output: %s" % display_path(out_dir))
    if args.note:
        print("  note: %s" % args.note)
    sys.stdout.flush()
    return total


def model_files(args):
    """Size and hash of every local model file a launched configuration needs."""
    files = {}
    for name in args.config_names:
        if name in args.remote:
            continue
        cfg = CONFIGS[name]
        wanted = {"model": resolve_path(args.model)}
        if cfg["drafter"] is not None:
            key = "drafter_" + cfg["drafter"] if cfg["drafter"] in ("v1", "v2") else "drafter_" + name
            wanted[key] = drafter_path(args, cfg)
        for key, path in wanted.items():
            if key not in files and os.path.isfile(path):
                files[key] = file_record(path)
    return files


def build_results(header, configs, rows, outputs, prompts, subset_ids):
    """The results.json object: header, config records, rows, every summary and the placeholder map.

    The placeholder map comes from fill_placeholders.build on this same
    object, so the tool's placeholders.json and the post-processed one have
    one schema.
    """
    summary = summarize(prompts, rows, header["config_names"])
    exact = exactness(rows, outputs, header["config_names"], header["repeats"])
    single = single_summary(rows, header["config_names"])
    extras = {
        "long_form": long_form_table(prompts, rows, header["config_names"]),
        "tool_calls": tool_call_summary(rows, header["config_names"]),
        "slots": slot_summary(rows, configs, subset_ids),
        "subset_ids": subset_ids,
        "single": single,
    }
    results = dict(header, configs=configs, results=rows, summary=summary, exactness=exact,
                   long_form=extras["long_form"], tool_calls=extras["tool_calls"], multi_slot=extras["slots"],
                   single=single,
                   power=[{"config": c["name"], "slots": c["slots"], "power": c["power"]} for c in configs])
    results["placeholders"] = fill_placeholders.build(results)
    return results, extras


def write_outputs(out_dir, header, configs, rows, outputs, prompts, subset_ids):
    results, extras = build_results(header, configs, rows, outputs, prompts, subset_ids)
    with open(os.path.join(out_dir, "results.json"), "w", encoding="utf-8") as f:
        json.dump(results, f, indent=1)
        f.write("\n")
    with open(os.path.join(out_dir, "placeholders.json"), "w", encoding="utf-8") as f:
        json.dump(results["placeholders"], f, indent=1, sort_keys=True)
        f.write("\n")
    with open(os.path.join(out_dir, "summary.md"), "w", encoding="utf-8") as f:
        f.write(render_markdown(header, results["summary"], results["exactness"], configs, rows, extras))
    dump = [
        {"config": k[0], "slots": k[1], "prompt_id": k[2], "pass": k[3], "content": v["content"], "tokens": v["tokens"]}
        for k, v in sorted(outputs.items())
    ]
    with open(os.path.join(out_dir, "outputs.json"), "w", encoding="utf-8") as f:
        json.dump(dump, f)
        f.write("\n")


def run_config(args, name, slots, prompts, subset, data, out_dir, rows, outputs, base_outputs):
    """Run one configuration at one slot count. Return the config record."""
    cfg = CONFIGS[name]
    record = {
        "name": name,
        "slots": slots,
        "column": cfg["column"],
        "mode": "remote" if name in args.remote else "launched",
        "url": args.remote.get(name),
        "drafter": None,
        "spec_draft_n_max": cfg["n_max"],
        "server_args": None,
        "props": None,
        "drafter_metadata": None,
        "load_seconds": None,
        "spec_engaged": None,
        "requests": 0,
        "waves": 0,
        "wave_seconds": None,
        "power": None,
        "started_utc": utc_now(),
        "error": None,
    }
    print("\n=== %s, slots %d (%s) ===" % (name, slots, record["mode"]))
    server = None
    sampler = None
    generation_seconds = 0.0
    tokens_generated = 0
    try:
        if record["mode"] == "launched":
            url = "http://%s:%d" % (args.host, args.port)
            bin_dir = resolve_path(args.bin_dir)
            required = [os.path.join(bin_dir, "llama-server"), resolve_path(args.model)]
            if cfg["drafter"] is not None:
                required.append(drafter_path(args, cfg))
            for path in required:
                if not os.path.isfile(path):
                    raise BenchError("missing file: %s" % path)
            if cfg["drafter"] is not None:
                # A remote server does not expose its drafter, so the metadata
                # is recorded only for servers the tool launches itself.
                record["drafter"] = display_path(required[2])
                record["drafter_metadata"] = read_drafter_metadata(required[2])
                block = drafter_block_size(record["drafter_metadata"])
                if block is not None and cfg["n_max"] > block:
                    print("  WARNING: --spec-draft-n-max %d exceeds the drafter block size %d"
                          % (cfg["n_max"], block))
            if port_in_use(args.host, args.port):
                raise BenchError("something already listens on %s:%d; the tool never stops "
                                 "a server it did not start" % (args.host, args.port))
            command = server_command(args, cfg, slots)
            env = dict(os.environ)
            env["LD_LIBRARY_PATH"] = bin_dir + (":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else "")
            record["server_args"] = [display_path(c) for c in command]
            print("  command: %s" % " ".join(record["server_args"]))
            server = LaunchedServer(command, env, os.path.join(out_dir, "server-%s-np%d.log" % (name, slots)))
            started = time.monotonic()
            server.start()
            wait_for_health(url, args.load_timeout, server)
            record["load_seconds"] = round(time.monotonic() - started, 1)
            print("  healthy after %.1f s" % record["load_seconds"])
        else:
            url = args.remote[name]
            wait_for_health(url, args.load_timeout)
        record["url"] = url
        record["props"] = fetch_props(url)
        print("  server build %s, model %s, slots %s" % (
            record["props"]["build_info"], record["props"]["model_path"], record["props"]["total_slots"]))
        total_slots = record["props"]["total_slots"]
        if isinstance(total_slots, int) and total_slots < slots:
            print("  WARNING: the server has %d slots; %d concurrent requests will queue" % (total_slots, slots))

        if not args.no_power:
            sampler = PowerSampler(args.gpu_index)
            sampler.start()
            if args.power_idle_s > 0:
                print("  sampling idle power for %d s" % args.power_idle_s)
                sys.stdout.flush()
                time.sleep(args.power_idle_s)
        if args.warmup_tokens > 0:
            if sampler is not None:
                sampler.phase = "warmup"
            warm_up(url, args.warmup_tokens, args.request_timeout)
        if sampler is not None:
            sampler.phase = "generation"

        def record_row(row, output):
            rows.append(row)
            outputs[(name, slots, row["prompt_id"], row["pass"])] = output
            record["requests"] += 1
            present = draft_counters_present(row)
            if present is None:
                return
            if cfg["drafter"] is not None and record["spec_engaged"] is None:
                record["spec_engaged"] = present
                if not present:
                    print("  WARNING: the response carries no draft counters; speculation is not engaged")
            if cfg["drafter"] is None and present:
                print("  WARNING: the baseline response carries draft counters; this server has a drafter")

        for pass_no in range(1, args.repeats + 1):
            if slots == 1:
                for prompt in prompts:
                    if server is not None and not server.alive():
                        raise BenchError("llama-server exited during the run; log: %s" % log_excerpt(server.log_path))
                    row, output = run_prompt(args, url, prompt, data, name, slots, pass_no, None)
                    record_row(row, output)
                    if row["error"] is None:
                        generation_seconds += (row["wall_ms"] or 0.0) / 1000.0
                        tokens_generated += row["predicted_n"] or 0
                    print_row(row, output, base_outputs.get((prompt["id"], pass_no)))
                if pass_no == 1 and not args.no_single:
                    single_prompt = {"id": SINGLE_ID, "category": "single", "set": "single",
                                     "n_predict": args.single_n_predict, "prompt": args.single_prompt}
                    for single_pass in range(1, args.single_repeats + 1):
                        if server is not None and not server.alive():
                            raise BenchError("llama-server exited during the run; log: %s" % log_excerpt(server.log_path))
                        row, output = run_prompt(args, url, single_prompt, data, name, slots, single_pass, None)
                        record_row(row, output)
                        if row["error"] is None:
                            generation_seconds += (row["wall_ms"] or 0.0) / 1000.0
                            tokens_generated += row["predicted_n"] or 0
                        print_row(row, output, base_outputs.get((SINGLE_ID, single_pass)))
            else:
                waves = [subset[i:i + slots] for i in range(0, len(subset), slots)]
                for wave_no, batch in enumerate(waves, 1):
                    if server is not None and not server.alive():
                        raise BenchError("llama-server exited during the run; log: %s" % log_excerpt(server.log_path))
                    wave_rows, wave_outputs, wall = run_wave(args, url, batch, data, name, slots, pass_no, wave_no)
                    record["waves"] += 1
                    record["wave_seconds"] = (record["wave_seconds"] or 0.0) + wall
                    generation_seconds += wall
                    for row, output in zip(wave_rows, wave_outputs):
                        record_row(row, output)
                        if row["error"] is None:
                            tokens_generated += row["predicted_n"] or 0
                        print_row(row, output, None)
                    ok = [r for r in wave_rows if r["error"] is None]
                    print("  wave %d: %d requests, %d tokens in %.1f s -> %.2f tok/s aggregate" % (
                        wave_no, len(batch), sum(r["predicted_n"] or 0 for r in ok), wall,
                        sum(r["predicted_n"] or 0 for r in ok) / wall if wall else 0.0))
                    sys.stdout.flush()
    except CONFIG_ERRORS as exc:
        record["error"] = config_error_text(exc)
        print("  ERROR: %s" % record["error"])
    finally:
        if sampler is not None:
            samples = sampler.stop()
            if sampler.available is False and not samples:
                record["power"] = {"unavailable": "nvidia-smi not found or failed"}
            else:
                record["power"] = power_summary(samples, tokens_generated, generation_seconds)
                record["power"]["host"] = socket.gethostname()
                record["power"]["interval_s"] = POWER_INTERVAL_S
                p = record["power"]
                print("  power: idle %s W, generation mean %s W, max %s W, %s mJ/token" % (
                    fmt_watts(p["idle_w"]), fmt_watts(p["mean_w"]), fmt_watts(p["max_w"]),
                    fmt_watts(p["energy_mj_per_token"])))
        if server is not None:
            server.stop()
    record["finished_utc"] = utc_now()
    return record


def print_row(row, output, base_output):
    if row["error"] is not None:
        print("  %-16s ERROR %s" % (row["prompt_id"], row["error"]))
        sys.stdout.flush()
        return
    line = "  %-16s pass %d  %4d tok  %7.2f tok/s" % (
        row["prompt_id"], row["pass"], row["predicted_n"] or 0, row["tok_s"] or 0.0)
    if row["draft_n"]:
        accepted = row["draft_n_accepted"] or 0
        line += "  accept %.3f (%d/%d)  %.2f tok/step" % (
            accepted / row["draft_n"], accepted, row["draft_n"], row.get("tokens_per_step") or 0.0)
    if row.get("endpoint") == "chat":
        line += "  %s" % (row.get("finish_reason") or "?")
        if row["set"] == "tool":
            line += "  tool call %s" % ("valid" if row.get("tool_call_valid") else "INVALID")
        if row.get("timings_source") == "wall":
            line += "  (wall timed)"
    if base_output is not None and output is not None:
        index, unit, _, _ = compare_outputs(base_output, output)
        line += "  identical" if index is None else "  differs at %s %d" % (unit, index)
    print(line)
    sys.stdout.flush()


def main(argv=None):
    args = parse_args(argv)
    prompts, data = load_prompts(args)
    subset = slot_subset(prompts, args.slot_ids)
    out_dir = resolve_path(args.out)
    launched = [name for name in args.config_names if name not in args.remote]
    if args.plan_only:
        plan = plan_runs(args, prompts, subset)
        print("spec_bench: configs %s; %s" % (", ".join(args.config_names), prompt_summary(prompts)))
        print_plan(args, plan, out_dir)
        for name in launched:
            for slots in args.slots:
                print("  %-12s slots %d: %s" % (name, slots, " ".join(
                    display_path(c) for c in server_command(args, CONFIGS[name], slots))))
        return 0
    os.makedirs(out_dir, exist_ok=True)
    environment = probe_environment(args)
    if launched and environment["gpu_compute_apps"] and not args.allow_busy_gpu:
        names = ", ".join(a["name"] for a in environment["gpu_compute_apps"])
        raise SystemExit("the GPU is in use by: %s. Numbers from a shared GPU are not "
                         "publishable. Wait for an idle GPU or pass --allow-busy-gpu." % names)

    plan = plan_runs(args, prompts, subset)
    print("spec_bench: configs %s; %s" % (", ".join(args.config_names), prompt_summary(prompts)))
    eta = print_plan(args, plan, out_dir)

    header = {
        "tool": "spec_bench",
        "schema_version": 2,
        "created_utc": utc_now(),
        "note": args.note,
        "environment": environment,
        "args": {k: v for k, v in vars(args).items() if k not in ("remote", "config_names", "server_url", "slot_ids", "add_config")},
        "server_urls": args.remote,
        "config_names": args.config_names,
        "configs_defined": {name: {k: v for k, v in cfg.items()} for name, cfg in CONFIGS.items() if name in args.config_names},
        "mode": "server-url" if args.remote else "launch",
        "slots": args.slots,
        "slot_prompt_ids": [p["id"] for p in subset],
        "files": model_files(args),
        "prompts_file": display_path(args.prompts),
        "prompts_sha256": sha256_file(args.prompts),
        "prompt_summary": prompt_summary(prompts),
        "prompt_ids": [p["id"] for p in prompts],
        "repeats": args.repeats,
        "seed": args.seed,
        "reasoning_effort": args.reasoning_effort,
        "single": None if args.no_single else {"id": SINGLE_ID, "prompt": args.single_prompt,
                                                "n_predict": args.single_n_predict, "repeats": args.single_repeats,
                                                "endpoint": "/completion", "template": "chatml, client side"},
        "power_idle_s": 0 if args.no_power else args.power_idle_s,
        "eta_seconds": round(eta),
        "plan": plan,
        "build_info": None,
        "request": {
            "completion": {"endpoint": "/completion", "sets": ["matrix", "long"], "temperature": 0.0,
                           "seed": args.seed, "cache_prompt": False,
                           "template": "chatml, applied by the client, no system message"},
            "chat": {"endpoint": "/v1/chat/completions", "sets": list(CHAT_SETS), "temperature": 0.0,
                     "seed": args.seed, "cache_prompt": False, "tool_choice": "auto",
                     "template": "server (--jinja)", "reasoning_effort": args.reasoning_effort,
                     "speed_source": "timings when the response carries it, else usage.completion_tokens over wall time"},
        },
    }
    subset_ids = [p["id"] for p in subset]
    configs = []
    rows = []
    outputs = {}
    started = time.monotonic()
    try:
        for name in args.config_names:
            for slots in args.slots:
                base_outputs = {
                    (k[2], k[3]): v for k, v in outputs.items() if k[0] == "baseline" and k[1] == 1
                } if slots == 1 else {}
                record = run_config(args, name, slots, prompts, subset, data, out_dir, rows, outputs, base_outputs)
                if header["build_info"] is None and record["props"]:
                    header["build_info"] = record["props"].get("build_info")
                configs.append(record)
                write_outputs(out_dir, header, configs, rows, outputs, prompts, subset_ids)
    except KeyboardInterrupt:
        print("\ninterrupted; partial results written to %s" % display_path(out_dir))
        write_outputs(out_dir, header, configs, rows, outputs, prompts, subset_ids)
        return 130
    header["elapsed_seconds"] = round(time.monotonic() - started, 1)
    write_outputs(out_dir, header, configs, rows, outputs, prompts, subset_ids)
    print("\ndone in %.1f min; results in %s" % (header["elapsed_seconds"] / 60, display_path(out_dir)))
    failed = ["%s slots %d" % (c["name"], c["slots"]) for c in configs if c["error"]]
    if failed:
        print("runs with errors: %s" % ", ".join(failed))
        return 1
    if any(r["error"] is not None for r in rows):
        print("%d requests failed; see the Errors section" % sum(1 for r in rows if r["error"] is not None))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
