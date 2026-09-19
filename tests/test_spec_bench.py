import collections
import importlib.util
import io
import json
import pathlib
import socket
import stat
import struct
import subprocess
import tempfile
import time
import unittest
from contextlib import redirect_stdout


ROOT = pathlib.Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("spec_bench", ROOT / "scripts" / "spec_bench" / "spec_bench.py")
spec_bench = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(spec_bench)

PROMPTS_PATH = ROOT / "scripts" / "spec_bench" / "prompts.json"

# A stand-in for llama-server. It answers the endpoints the tool uses and
# returns fixed tokens, so the launch, poll and stop path can run without a
# GPU. With a drafter it adds draft counters, and at K=5 it changes the last
# token (and the chat text) so the exactness report has something to list.
# With a drafter and more than one slot it exits at once with an error line,
# like a build that refuses that combination. `--draft-zero` reports draft
# counters of zero, `--no-tokens` omits the token ids from /completion, and
# `--fail-single-pass N` answers the Nth quicksort request with HTTP 500.
FAKE_SERVER = r'''#!/usr/bin/env python3
import json, sys, http.server
args = sys.argv[1:]
port = int(args[args.index("--port") + 1])
drafter = "-md" in args
n_max = int(args[args.index("--spec-draft-n-max") + 1]) if drafter else 0
slots = int(args[args.index("-np") + 1]) if "-np" in args else 1
fail_pass = int(args[args.index("--fail-single-pass") + 1]) if "--fail-single-pass" in args else 0
if drafter and slots > 1:
    print("common_init_from_params: error: speculative decoding requires n_parallel == 1", flush=True)
    sys.exit(1)
health_calls = {"n": 0}
single_calls = {"n": 0}

def timings(n):
    t = {"prompt_n": 10, "prompt_ms": 5.0, "predicted_n": n, "predicted_ms": 100.0,
         "predicted_per_second": n * 10.0}
    if drafter:
        t["draft_n"] = 0 if "--draft-zero" in args else n * 2
        t["draft_n_accepted"] = 0 if "--draft-zero" in args else n // 2
    return t

class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass
    def send(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def do_GET(self):
        if self.path == "/health":
            health_calls["n"] += 1
            if health_calls["n"] == 1:
                self.send(503, {"error": {"message": "Loading model"}})
            else:
                self.send(200, {"status": "ok"})
        elif self.path == "/props":
            self.send(200, {"build_info": "b0-test", "model_path": "target.gguf",
                            "model_alias": "test", "total_slots": slots,
                            "chat_template_caps": {"supports_tools": True},
                            "default_generation_settings": {"n_ctx": 16384 // slots}})
        else:
            self.send(404, {})
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        if self.path == "/apply-template":
            self.send(200, {"prompt": json.dumps(body, sort_keys=True)})
            return
        if self.path == "/v1/chat/completions":
            n = min(body["max_tokens"], 8)
            has_tool_result = any(m["role"] == "tool" for m in body["messages"])
            message = {"role": "assistant", "reasoning_content": "think " * 3}
            if has_tool_result:
                message["content"] = "## Result\nDone" + (" (k5)" if drafter and n_max == 5 else "")
                finish = "stop"
            else:
                name = body["tools"][0]["function"]["name"]
                message["content"] = ""
                message["tool_calls"] = [{"id": "c1", "type": "function", "function": {
                    "name": name, "arguments": json.dumps({"city": "Lisbon" if n_max != 5 else "Porto"})}}]
                finish = "tool_calls"
            out = {"choices": [{"index": 0, "finish_reason": finish, "message": message}],
                   "usage": {"completion_tokens": n, "prompt_tokens": 10, "total_tokens": n + 10}}
            if "--no-timings" not in args:
                out["timings"] = timings(n)
            self.send(200, out)
            return
        n = min(body["n_predict"], 8)
        if "quicksort" in body["prompt"]:
            single_calls["n"] += 1
            if single_calls["n"] == fail_pass:
                self.send(500, {"error": {"message": "fake failure of pass %d" % fail_pass}})
                return
        tokens = [sum(map(ord, body["prompt"])) % 1000 + i for i in range(n)]
        if drafter and n_max == 5 and n > 1:
            tokens[-1] += 1
        out = {"content": "".join(chr(97 + t % 26) for t in tokens), "tokens": tokens,
               "stop_type": "limit", "truncated": False, "timings": timings(n)}
        if "--no-tokens" in args:
            del out["tokens"]
        self.send(200, out)

http.server.ThreadingHTTPServer(("127.0.0.1", port), H).serve_forever()
'''


def write_gguf(path, block_size):
    """Write a GGUF file with a header only: three keys, no tensors."""
    def string(s):
        b = s.encode()
        return struct.pack("<Q", len(b)) + b

    data = b"GGUF" + struct.pack("<IQQ", 3, 0, 3)
    data += string("general.architecture") + struct.pack("<I", 8) + string("dflash")
    data += string("dflash.block_size") + struct.pack("<I", 4) + struct.pack("<I", block_size)
    data += string("tokenizer.ggml.tokens") + struct.pack("<IIQ", 9, 8, 2) + string("a") + string("b")
    path.write_bytes(data)


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class PromptSetTests(unittest.TestCase):
    def setUp(self):
        with open(PROMPTS_PATH, encoding="utf-8") as f:
            self.data = json.load(f)

    def test_shape(self):
        prompts = self.data["prompts"]
        self.assertEqual(len(prompts), 62)
        self.assertEqual(len({p["id"] for p in prompts}), 62)
        counts = collections.Counter((p["set"], p["category"]) for p in prompts)
        for category in spec_bench.CATEGORY_ORDER:
            self.assertEqual(counts[("matrix", category)], 8, category)
        self.assertEqual(counts[("long", "long-form")], 6)
        self.assertEqual(counts[("tool", "tool")], 8)
        self.assertEqual(counts[("agent", "agent")], 8)
        self.assertEqual(self.data["sets"]["matrix"]["n_predict"], 512)
        self.assertEqual(self.data["sets"]["long"]["n_predict"], 2000)
        self.assertEqual(self.data["sets"]["tool"]["n_predict"], 512)
        self.assertEqual(self.data["sets"]["agent"]["n_predict"], 512)

    def test_tools_and_tool_prompts(self):
        names = [t["function"]["name"] for t in self.data["tools"]]
        self.assertEqual(names, ["get_weather", "search_docs", "run_sql", "create_ticket"])
        for tool in self.data["tools"] + self.data["agent_tools"]:
            self.assertEqual(tool["type"], "function")
            params = tool["function"]["parameters"]
            self.assertEqual(params["type"], "object")
            self.assertTrue(params["properties"])
            self.assertTrue(set(params["required"]) <= set(params["properties"]))
        tool_prompts = [p for p in self.data["prompts"] if p["set"] == "tool"]
        self.assertEqual(collections.Counter(p["expect_tool"] for p in tool_prompts),
                         {name: 2 for name in names})

    def test_agent_prompts_carry_a_long_prefix(self):
        system = "\n".join(self.data["agent_system"])
        words = len(system.split())
        # About 1,700 tokens with the Bonsai 2 tokenizer (1.35 tokens per word).
        self.assertTrue(1100 <= words <= 1500, words)
        for heading in ("# Role", "# Rules", "# Tools", "# House style", "# Report format"):
            self.assertIn(heading, system)
        agent_names = {t["function"]["name"] for t in self.data["agent_tools"]}
        for p in self.data["prompts"]:
            if p["set"] != "agent":
                continue
            self.assertIn(p["tool_call"]["name"], agent_names, p["id"])
            self.assertIsInstance(p["tool_call"]["arguments"], dict)
            blob = "\n".join(p["tool_result"])
            # About 500 to 750 tokens of terminal output; paths and log lines
            # tokenize at roughly 3 characters per token.
            self.assertTrue(1000 <= len(blob) <= 2400, (p["id"], len(blob)))
            self.assertTrue(15 <= len(p["tool_result"]) <= 70, (p["id"], len(p["tool_result"])))

    def test_ascii_only_and_short(self):
        raw = PROMPTS_PATH.read_bytes()
        self.assertTrue(all(b < 128 for b in raw))
        for p in self.data["prompts"]:
            self.assertLess(len(p["prompt"].split()), 80, p["id"])

    def test_concurrency_subset_exists(self):
        ids = {p["id"] for p in self.data["prompts"]}
        self.assertTrue(set(spec_bench.CONCURRENCY_IDS) <= ids)
        by_id = {p["id"]: p for p in self.data["prompts"]}
        self.assertEqual(collections.Counter(by_id[i]["category"] for i in spec_bench.CONCURRENCY_IDS),
                         {"code": 2, "chat": 2, "reasoning": 2, "tool": 2})


class HelperTests(unittest.TestCase):
    def test_chat_prompt_wraps_in_chatml(self):
        self.assertEqual(
            spec_bench.chat_prompt("hi"),
            "<|im_start|>user\nhi<|im_end|>\n<|im_start|>assistant\n",
        )

    def test_first_diff(self):
        self.assertIsNone(spec_bench.first_diff([1, 2, 3], [1, 2, 3]))
        self.assertEqual(spec_bench.first_diff([1, 2, 3], [1, 9, 3]), 1)
        self.assertEqual(spec_bench.first_diff([1, 2], [1, 2, 3]), 2)
        self.assertEqual(spec_bench.first_diff([], [7]), 0)
        self.assertEqual(spec_bench.first_diff("abc", "abd"), 2)

    def test_gguf_metadata_reads_header_only(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp) / "d.gguf"
            write_gguf(path, 7)
            meta = spec_bench.gguf_metadata(path, ("general.architecture", "dflash.", "tokenizer."))
        self.assertEqual(meta["general.architecture"], "dflash")
        self.assertEqual(meta["dflash.block_size"], 7)
        self.assertEqual(meta["tokenizer.ggml.tokens"], "array[2]")

    def test_truncated_gguf_is_a_bench_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp) / "d.gguf"
            write_gguf(path, 7)
            path.write_bytes(path.read_bytes()[:40])
            with self.assertRaises(spec_bench.BenchError) as raised:
                spec_bench.read_drafter_metadata(str(path))
        self.assertIn("cannot read the GGUF header", str(raised.exception))
        self.assertIn("d.gguf", str(raised.exception))

    def test_drafter_block_size_falls_back_to_the_dspark_key(self):
        self.assertEqual(spec_bench.drafter_block_size({"dflash.block_size": 7}), 7)
        self.assertEqual(spec_bench.drafter_block_size({"dspark.dspark.block_size": 4}), 4)
        self.assertEqual(spec_bench.drafter_block_size({"dflash.block_size": 7, "dspark.dspark.block_size": 4}), 7)
        self.assertIsNone(spec_bench.drafter_block_size({"dflash.block_size": "array[2]"}))
        self.assertIsNone(spec_bench.drafter_block_size({}))
        self.assertIsNone(spec_bench.drafter_block_size(None))

    def test_draft_counters_present_tests_presence_not_value(self):
        self.assertTrue(spec_bench.draft_counters_present({"error": None, "timings_source": "timings", "draft_n": 0}))
        self.assertTrue(spec_bench.draft_counters_present({"error": None, "timings_source": "timings", "draft_n": 9}))
        self.assertFalse(spec_bench.draft_counters_present({"error": None, "timings_source": "timings", "draft_n": None}))
        self.assertIsNone(spec_bench.draft_counters_present({"error": None, "timings_source": "wall", "draft_n": None}))
        self.assertIsNone(spec_bench.draft_counters_present({"error": "HttpError: HTTP 500", "draft_n": None}))

    def test_compare_outputs_falls_back_to_text_without_token_ids(self):
        with_ids = {"tokens": [1, 2, 3], "content": "abc"}
        self.assertEqual(spec_bench.compare_outputs(with_ids, {"tokens": [1, 2, 4], "content": "abd"}), (2, "token", 3, 3))
        self.assertEqual(spec_bench.compare_outputs(with_ids, {"tokens": None, "content": "abd"}), (2, "char", 3, 3))
        self.assertEqual(spec_bench.compare_outputs(with_ids, {"tokens": None, "content": "abc"}), (None, "char", 3, 3))
        # Two outputs without ids and different text are different, not identical.
        self.assertEqual(spec_bench.compare_outputs({"tokens": None, "content": "ab"}, {"tokens": None, "content": "ac"})[0], 1)

    def test_run_completion_keeps_missing_token_ids_as_none(self):
        original = spec_bench.http_json
        answers = iter([
            {"content": "abc", "stop_type": "limit", "timings": {"predicted_n": 3, "predicted_per_second": 30.0}},
            {"content": "abc", "tokens": [5, 6, 7], "stop_type": "limit", "timings": {"predicted_n": 3}},
        ])
        spec_bench.http_json = lambda url, body=None, timeout=30: next(answers)
        try:
            row, output = spec_bench.run_completion("http://h", {"prompt": "p"}, 3, 42, 5)
            self.assertIsNone(output["tokens"])
            self.assertEqual(output["content"], "abc")
            self.assertIsNone(row["output_tokens"])
            self.assertIsNone(row["tokens_sha256"])
            self.assertEqual(row["output_chars"], 3)
            row, output = spec_bench.run_completion("http://h", {"prompt": "p"}, 3, 42, 5)
            self.assertEqual(output["tokens"], [5, 6, 7])
            self.assertEqual(row["output_tokens"], 3)
        finally:
            spec_bench.http_json = original

    def test_configs_help_names_the_real_default(self):
        out = io.StringIO()
        with redirect_stdout(out), self.assertRaises(SystemExit):
            spec_bench.parse_args(["--help"])
        text = " ".join(out.getvalue().split())
        self.assertIn("(default: every config, baseline,dspark-v1,dspark-v2, plus every --add-config;", text)
        self.assertNotIn("default: baseline,dspark-v2", text)
        self.assertEqual(spec_bench.parse_args([]).config_names, ["baseline", "dspark-v1", "dspark-v2"])

    def test_parse_server_url(self):
        self.assertEqual(
            spec_bench.parse_server_url("baseline=http://h:1/"), ("baseline", "http://h:1"))
        with self.assertRaises(Exception):
            spec_bench.parse_server_url("nope=http://h:1")

    def test_parse_add_config_and_slots(self):
        name, cfg = spec_bench.parse_add_config("dspark-v2-k7=models/d.gguf:7")
        self.assertEqual(name, "dspark-v2-k7")
        self.assertEqual((cfg["drafter"], cfg["path"], cfg["n_max"]), ("path", "models/d.gguf", 7))
        with self.assertRaises(Exception):
            spec_bench.parse_add_config("k7=models/d.gguf")
        self.assertEqual(spec_bench.parse_slots("1,2,4"), [1, 2, 4])
        with self.assertRaises(Exception):
            spec_bench.parse_slots("0")

    def test_server_command_flags(self):
        args = spec_bench.parse_args(["--server-extra", "--threads 4", "--port", "1234"])
        command = spec_bench.server_command(args, spec_bench.CONFIGS["dspark-v2"], slots=4)
        self.assertTrue(command[0].endswith("bin/cuda/llama-server"))
        self.assertEqual(command[-2:], ["--threads", "4"])
        self.assertEqual(command[command.index("-np") + 1], "4")
        self.assertIn("--jinja", command)
        self.assertEqual(command[command.index("--spec-draft-n-max") + 1], "5")
        self.assertTrue(command[command.index("-md") + 1].endswith("Ternary-Bonsai-2-27B-dspark-dflash-v2-Q4_K_M.gguf"))
        base = spec_bench.server_command(args, spec_bench.CONFIGS["baseline"])
        self.assertNotIn("-md", base)
        self.assertEqual(base[base.index("-np") + 1], "1")
        v1 = spec_bench.server_command(args, spec_bench.CONFIGS["dspark-v1"])
        self.assertEqual(v1[v1.index("--spec-draft-n-max") + 1], "4")
        self.assertTrue(v1[v1.index("-md") + 1].endswith("Ternary-Bonsai-2-27B-dspark-dflash-Q4_0.gguf"))
        self.assertEqual(spec_bench.CONFIGS["dspark-v1"]["column"], "DSpark v1 (Ternary-Bonsai-27B drafter, K=4)")
        self.assertEqual(spec_bench.CONFIGS["dspark-v2"]["column"], "DSpark v2 (K=5)")

    def test_add_config_registers_a_drafter(self):
        args = spec_bench.parse_args(["--add-config", "k7=models/d.gguf:7"])
        self.assertEqual(args.config_names, ["baseline", "dspark-v1", "dspark-v2", "k7"])
        command = spec_bench.server_command(args, spec_bench.CONFIGS["k7"])
        self.assertEqual(command[command.index("--spec-draft-n-max") + 1], "7")
        self.assertTrue(command[command.index("-md") + 1].endswith("models/d.gguf"))
        del spec_bench.CONFIGS["k7"]

    def test_chat_messages_and_body(self):
        with open(PROMPTS_PATH, encoding="utf-8") as f:
            data = json.load(f)
        by_id = {p["id"]: p for p in data["prompts"]}
        messages, tools = spec_bench.chat_messages(by_id["tool-01"], data)
        self.assertEqual([m["role"] for m in messages], ["user"])
        self.assertEqual(tools, data["tools"])
        messages, tools = spec_bench.chat_messages(by_id["agent-01"], data)
        self.assertEqual([m["role"] for m in messages], ["system", "user", "assistant", "tool"])
        self.assertEqual(messages[2]["tool_calls"][0]["function"]["name"], "run_shell")
        self.assertEqual(messages[3]["tool_call_id"], "call_1")
        self.assertEqual(tools, data["agent_tools"])
        body = spec_bench.chat_body(messages, tools, 512, 42, "template")
        self.assertEqual((body["max_tokens"], body["temperature"], body["tool_choice"]), (512, 0.0, "auto"))
        self.assertFalse(body["cache_prompt"])
        self.assertNotIn("chat_template_kwargs", body)
        body = spec_bench.chat_body(messages, tools, 512, 42, "low")
        self.assertEqual(body["chat_template_kwargs"], {"reasoning_effort": "low"})


class ToolCallParserTests(unittest.TestCase):
    def test_structured_tool_calls(self):
        message = {"content": "", "tool_calls": [{"type": "function", "id": "x", "function": {
            "name": "get_weather", "arguments": "{\"city\": \"Lisbon\"}"}}]}
        calls = spec_bench.parse_tool_calls(message)
        self.assertEqual(calls, [{"name": "get_weather", "arguments": {"city": "Lisbon"},
                                  "well_formed": True, "source": "structured"}])
        self.assertTrue(spec_bench.tool_call_valid(calls, {"get_weather"}))
        self.assertFalse(spec_bench.tool_call_valid(calls, {"run_sql"}))

    def test_structured_call_with_bad_arguments(self):
        message = {"content": "", "tool_calls": [{"function": {"name": "get_weather", "arguments": "{oops"}}]}
        calls = spec_bench.parse_tool_calls(message)
        self.assertFalse(calls[0]["well_formed"])
        self.assertFalse(spec_bench.tool_call_valid(calls, {"get_weather"}))

    def test_text_xml_form(self):
        message = {"content": "<tool_call>\n<function=run_sql>\n<parameter=query>\nSELECT 1\n</parameter>\n"
                              "<parameter=database>\nbilling\n</parameter>\n</function>\n</tool_call>"}
        calls = spec_bench.parse_tool_calls(message)
        self.assertEqual(calls[0]["name"], "run_sql")
        self.assertEqual(calls[0]["arguments"], {"query": "SELECT 1", "database": "billing"})
        self.assertEqual(calls[0]["source"], "text-xml")
        self.assertTrue(spec_bench.tool_call_valid(calls, {"run_sql"}))

    def test_text_json_form(self):
        message = {"content": "<tool_call>{\"name\": \"search_docs\", \"arguments\": {\"query\": \"retry\"}}</tool_call>"}
        calls = spec_bench.parse_tool_calls(message)
        self.assertEqual(calls[0]["source"], "text-json")
        self.assertTrue(spec_bench.tool_call_valid(calls, {"search_docs"}))

    def test_no_call_and_garbage(self):
        self.assertEqual(spec_bench.parse_tool_calls({"content": "I cannot help."}), [])
        self.assertFalse(spec_bench.tool_call_valid([], {"x"}))
        calls = spec_bench.parse_tool_calls({"content": "<tool_call>garbage</tool_call>"})
        self.assertEqual(calls[0]["source"], "text-unparsed")
        self.assertFalse(spec_bench.tool_call_valid(calls, {"x"}))


class PowerTests(unittest.TestCase):
    def test_parse_gpu_sample_handles_not_available(self):
        self.assertEqual(spec_bench.parse_gpu_sample("45.23, 90, [N/A]"),
                         {"power_w": 45.23, "util_pct": 90, "memory_mib": None})
        self.assertEqual(spec_bench.parse_gpu_sample("12.5, 0, 1024"),
                         {"power_w": 12.5, "util_pct": 0, "memory_mib": 1024})
        self.assertIsNone(spec_bench.parse_gpu_sample("garbage"))

    def test_energy_per_token(self):
        self.assertAlmostEqual(spec_bench.energy_mj_per_token(60.0, 30.0), 2000.0)
        self.assertIsNone(spec_bench.energy_mj_per_token(None, 30.0))
        self.assertIsNone(spec_bench.energy_mj_per_token(60.0, 0))

    def test_tokens_per_step(self):
        self.assertAlmostEqual(spec_bench.tokens_per_step(100, 60), 2.5)
        self.assertAlmostEqual(spec_bench.tokens_per_step(100, None), 1.0)
        self.assertAlmostEqual(spec_bench.tokens_per_step(100, 0), 1.0)
        self.assertIsNone(spec_bench.tokens_per_step(0, 0))
        self.assertIsNone(spec_bench.tokens_per_step(10, 10))

    def test_power_summary(self):
        idle = [{"phase": "idle", "power_w": 10.0, "util_pct": 0, "memory_mib": None}] * 3
        warm = [{"phase": "warmup", "power_w": 99.0, "util_pct": 50, "memory_mib": None}]
        gen = [{"phase": "generation", "power_w": 50.0, "util_pct": 90, "memory_mib": 100},
               {"phase": "generation", "power_w": 70.0, "util_pct": 100, "memory_mib": 120}]
        summary = spec_bench.power_summary(idle + warm + gen, tokens=600, generation_seconds=20.0)
        self.assertEqual((summary["idle_samples"], summary["generation_samples"]), (3, 2))
        self.assertAlmostEqual(summary["idle_w"], 10.0)
        self.assertAlmostEqual(summary["mean_w"], 60.0)
        self.assertAlmostEqual(summary["max_w"], 70.0)
        self.assertAlmostEqual(summary["util_pct_mean"], 95.0)
        self.assertEqual(summary["memory_mib_max"], 120)
        self.assertAlmostEqual(summary["tok_s_wall"], 30.0)
        self.assertAlmostEqual(summary["energy_mj_per_token"], 2000.0)
        empty = spec_bench.power_summary([], tokens=0, generation_seconds=0.0)
        self.assertIsNone(empty["mean_w"])
        self.assertIsNone(empty["energy_mj_per_token"])

    def test_sampler_thread_tags_phases_and_stops(self):
        original = spec_bench.sample_gpu
        readings = iter([10.0, 10.0, 50.0, 60.0] + [70.0] * 50)
        spec_bench.sample_gpu = lambda index: {"power_w": next(readings), "util_pct": 90, "memory_mib": None}
        try:
            sampler = spec_bench.PowerSampler(gpu_index=0, interval=0.05)
            sampler.start()
            time.sleep(0.12)
            sampler.phase = "generation"
            time.sleep(0.12)
            samples = sampler.stop()
        finally:
            spec_bench.sample_gpu = original
        self.assertFalse(sampler.is_alive())
        self.assertTrue(sampler.available)
        phases = collections.Counter(s["phase"] for s in samples)
        self.assertGreaterEqual(phases["idle"], 1)
        self.assertGreaterEqual(phases["generation"], 1)
        self.assertEqual(samples[0]["power_w"], 10.0)

    def test_sampler_stops_when_nvidia_smi_is_missing(self):
        original = spec_bench.sample_gpu
        spec_bench.sample_gpu = lambda index: None
        try:
            sampler = spec_bench.PowerSampler(gpu_index=0, interval=0.05)
            sampler.start()
            samples = sampler.stop()
        finally:
            spec_bench.sample_gpu = original
        self.assertEqual(samples, [])
        self.assertFalse(sampler.available)


def make_row(config, prompt, tok_s, slots=1, pass_no=1, drafted=None, accepted=None, wall_ms=1000.0, **extra):
    row = {"config": config, "slots": slots, "prompt_id": prompt["id"], "category": prompt["category"],
           "set": prompt["set"], "pass": pass_no, "wave": None, "tok_s": tok_s, "error": None,
           "prompt_n": 50, "predicted_n": 20, "predicted_ms": (20000.0 / tok_s) if tok_s else None,
           "draft_n": drafted, "draft_n_accepted": accepted, "wall_ms": wall_ms,
           "tokens_per_step": spec_bench.tokens_per_step(20, accepted),
           "endpoint": "chat" if prompt["set"] in spec_bench.CHAT_SETS else "completion",
           "finish_reason": "stop", "timings_source": "timings"}
    row.update(extra)
    return row


class SummaryTests(unittest.TestCase):
    def setUp(self):
        self.prompts = [
            {"id": "code-01", "category": "code", "set": "matrix", "n_predict": 4},
            {"id": "math-01", "category": "math", "set": "matrix", "n_predict": 4},
            {"id": "long-01", "category": "long-form", "set": "long", "n_predict": 8},
            {"id": "tool-01", "category": "tool", "set": "tool", "n_predict": 4, "expect_tool": "get_weather"},
            {"id": "agent-01", "category": "agent", "set": "agent", "n_predict": 4},
        ]
        self.rows = []
        self.outputs = {}
        rates = {"baseline": 10.0, "dspark-v2": 25.0}
        for name, rate in rates.items():
            drafted = 20 if name != "baseline" else None
            accepted = 15 if name != "baseline" else None
            for p in self.prompts:
                extra = {}
                if p["set"] == "tool":
                    extra = {"tool_call_valid": name == "baseline", "tool_call_expected": name == "baseline",
                             "tool_call_sources": ["structured"], "finish_reason": "tool_calls",
                             "timings_source": "timings"}
                self.rows.append(make_row(name, p, rate, drafted=drafted, accepted=accepted, **extra))
                if p["set"] in spec_bench.CHAT_SETS:
                    text = "same text" if not (name != "baseline" and p["id"] == "tool-01") else "same tex!"
                    self.outputs[(name, 1, p["id"], 1)] = {"tokens": None, "content": text}
                else:
                    tokens = [1, 2, 3]
                    if name != "baseline" and p["id"] == "math-01":
                        tokens = [1, 2, 4]
                    self.outputs[(name, 1, p["id"], 1)] = {"tokens": tokens, "content": ""}
        # Multi-slot rows for the drafter config, slots 2, over the subset.
        for p in self.prompts[:2]:
            self.rows.append(make_row("dspark-v2", p, 20.0, slots=2, drafted=20, accepted=10, wall_ms=500.0))
        self.names = ["baseline", "dspark-v2"]
        self.configs = [
            {"name": "baseline", "slots": 1, "mode": "launched", "server_args": ["llama-server", "-np", "1"],
             "props": {"build_info": "b"}, "drafter_metadata": None, "error": None, "url": None,
             "load_seconds": 12.0, "wave_seconds": None,
             "power": {"idle_w": 20.0, "mean_w": 60.0, "max_w": 70.0, "util_pct_mean": 90.0,
                       "tokens": 12, "tok_s_wall": 10.0, "energy_mj_per_token": 6000.0}},
            {"name": "dspark-v2", "slots": 1, "mode": "remote", "server_args": None, "url": "http://x",
             "props": None, "drafter_metadata": {"dflash.block_size": 7}, "error": None,
             "load_seconds": None, "wave_seconds": None, "power": {"unavailable": "nvidia-smi not found"}},
            {"name": "dspark-v2", "slots": 2, "mode": "launched", "server_args": ["llama-server", "-np", "2"],
             "props": {"build_info": "b"}, "drafter_metadata": None, "error": None, "url": None,
             "load_seconds": 12.0, "wave_seconds": 0.5, "power": None},
            {"name": "dspark-v2", "slots": 4, "mode": "launched", "server_args": ["llama-server", "-np", "4"],
             "props": None, "drafter_metadata": None, "load_seconds": None, "wave_seconds": None, "power": None,
             "url": None, "error": "llama-server exited with code 1 before it was ready; log: error: n_parallel"},
        ]
        self.subset = ["code-01", "math-01"]

    def test_summarize_means_accept_and_speedup(self):
        summary = spec_bench.summarize(self.prompts, self.rows, self.names)
        table = {e["workload"]: e for e in summary["tables"]["dspark-v2"]}
        self.assertEqual(list(table), ["code", "math", "tool", "agent", "blended (2 prompts)",
                                       "long-form (1 prompts, 8 tokens)"])
        blended = table["blended (2 prompts)"]
        self.assertAlmostEqual(blended["no_drafter_tok_s"], 10.0)
        self.assertAlmostEqual(blended["with_drafter_tok_s"], 25.0)
        self.assertAlmostEqual(blended["with_drafter_weighted_tok_s"], 25.0)
        self.assertAlmostEqual(blended["speedup"], 2.5)
        self.assertEqual((blended["accepted"], blended["drafted"]), (30, 40))
        self.assertAlmostEqual(blended["accept_rate"], 0.75)
        self.assertAlmostEqual(blended["with_drafter_tokens_per_step"], 4.0)
        self.assertAlmostEqual(blended["no_drafter_tokens_per_step"], 1.0)
        self.assertEqual(table["agent"]["prompts"], 1)
        self.assertAlmostEqual(table["agent"]["with_drafter_prompt_n"], 50.0)

    def test_summarize_ignores_multi_slot_rows(self):
        summary = spec_bench.summarize(self.prompts, self.rows, self.names)
        table = {e["workload"]: e for e in summary["tables"]["dspark-v2"]}
        self.assertEqual(table["code"]["prompts"], 1)
        self.assertAlmostEqual(table["code"]["with_drafter_tok_s"], 25.0)

    def test_summarize_skips_prompts_missing_from_baseline(self):
        rows = [r for r in self.rows if not (r["config"] == "baseline" and r["prompt_id"] == "code-01")]
        summary = spec_bench.summarize(self.prompts, rows, self.names)
        table = {e["workload"]: e for e in summary["tables"]["dspark-v2"]}
        self.assertNotIn("code", table)
        self.assertEqual(table["blended (2 prompts)"]["prompts"], 1)

    def test_exactness_reports_token_and_char_diffs(self):
        report = spec_bench.exactness(self.rows, self.outputs, self.names, 1)
        result = report["configs"]["dspark-v2"]
        self.assertEqual((result["compared"], result["identical"]), (5, 3))
        diffs = {d["prompt_id"]: d for d in result["diffs"]}
        self.assertEqual(diffs["math-01"]["first_diff"], 2)
        self.assertEqual(diffs["math-01"]["unit"], "token")
        self.assertEqual(diffs["tool-01"]["first_diff"], 8)
        self.assertEqual(diffs["tool-01"]["unit"], "char")
        self.assertIsNone(report["baseline_passes_identical"])

    def test_long_form_and_tool_call_tables(self):
        long_form = spec_bench.long_form_table(self.prompts, self.rows, self.names)
        self.assertEqual(len(long_form), 1)
        self.assertEqual(long_form[0]["prompt_id"], "long-01")
        self.assertAlmostEqual(long_form[0]["configs"]["dspark-v2"]["speedup"], 2.5)
        self.assertAlmostEqual(long_form[0]["configs"]["dspark-v2"]["accept_rate"], 0.75)
        self.assertAlmostEqual(long_form[0]["configs"]["dspark-v2"]["tokens_per_step"], 4.0)
        tools = spec_bench.tool_call_summary(self.rows, self.names)
        self.assertEqual((tools["baseline"]["prompts"], tools["baseline"]["valid"], tools["baseline"]["expected_tool"]), (1, 1, 1))
        self.assertEqual((tools["dspark-v2"]["valid"], tools["dspark-v2"]["valid_rate"]), (0, 0.0))
        self.assertEqual(tools["baseline"]["finish_reasons"], {"tool_calls": 1})
        self.assertEqual(tools["baseline"]["sources"], {"structured": 1})

    def test_slot_summary(self):
        entries = spec_bench.slot_summary(self.rows, self.configs, self.subset)
        by_key = {(e["config"], e["slots"]): e for e in entries}
        single = by_key[("dspark-v2", 1)]
        self.assertEqual(single["ok"], 2)
        self.assertAlmostEqual(single["per_stream_tok_s"], 25.0)
        self.assertAlmostEqual(single["aggregate_tok_s"], 40 / 2.0)
        self.assertAlmostEqual(single["tokens_per_step"], 4.0)
        double = by_key[("dspark-v2", 2)]
        self.assertEqual(double["ok"], 2)
        self.assertAlmostEqual(double["per_stream_tok_s"], 20.0)
        self.assertAlmostEqual(double["aggregate_tok_s"], 40 / 0.5)
        self.assertAlmostEqual(double["accept_rate"], 0.5)
        self.assertAlmostEqual(double["tokens_per_step"], 2.0)
        failed = by_key[("dspark-v2", 4)]
        self.assertEqual(failed["ok"], 0)
        self.assertIn("n_parallel", failed["error"])
        self.assertTrue(single["draft_fields"])
        self.assertTrue(double["draft_fields"])
        self.assertFalse(by_key[("baseline", 1)]["draft_fields"])
        self.assertIsNone(failed["draft_fields"])

    def test_slot_summary_draft_fields_and_partial_failures(self):
        # A drafter that drafted nothing still carries counters (draft_n 0);
        # wall-timed rows carry none and leave the state unknown; a failed
        # request counts as attempted and its error is kept.
        rows = [make_row("dspark-v2", self.prompts[0], 20.0, slots=2, drafted=0, accepted=0),
                make_row("dspark-v2", self.prompts[1], None, slots=2, error="URLError: timed out")]
        wall = [make_row("dspark-v2", p, 20.0, slots=4, timings_source="wall") for p in self.prompts[:2]]
        configs = [dict(self.configs[2]), dict(self.configs[3], error=None, wave_seconds=0.5)]
        by_key = {(e["config"], e["slots"]): e for e in spec_bench.slot_summary(rows + wall, configs, self.subset)}
        partial = by_key[("dspark-v2", 2)]
        self.assertEqual((partial["prompts"], partial["ok"], partial["errors"]), (2, 1, 1))
        self.assertTrue(partial["draft_fields"])
        self.assertEqual(partial["error"], "URLError: timed out")
        unknown = by_key[("dspark-v2", 4)]
        self.assertEqual((unknown["prompts"], unknown["ok"]), (2, 2))
        self.assertIsNone(unknown["draft_fields"])
        self.assertIsNone(unknown["error"])
        extras = {"slots": list(by_key.values()), "subset_ids": self.subset}
        text = spec_bench.render_markdown(self.header(), {"tables": {}, "baseline": None}, None, configs, [], extras)
        self.assertIn("| dspark-v2 | 2 | 2 | 20.00 | 40.00 | n/a | 1 of 2 requests failed: URLError: timed out |", text)
        self.assertIn("| dspark-v2 | 4 | 2 | 20.00 | 80.00 | n/a | ok (wall timed, no draft counters available) |", text)

    def test_single_summary_keeps_a_failed_pass_in_its_position(self):
        single = {"id": spec_bench.SINGLE_ID, "category": "single", "set": "single", "n_predict": 20}
        rows = [make_row("baseline", single, 30.0, pass_no=1),
                make_row("baseline", single, None, pass_no=2, error="HttpError: HTTP 500: boom"),
                make_row("baseline", single, 32.0, pass_no=3),
                make_row("dspark-v2", single, 60.0, pass_no=1, drafted=20, accepted=15),
                make_row("dspark-v2", single, 64.0, pass_no=3, drafted=20, accepted=15)]
        report = spec_bench.single_summary(rows, self.names)
        self.assertEqual(report["baseline"]["passes"], [30.0, None, 32.0])
        self.assertAlmostEqual(report["baseline"]["mean_tok_s"], 31.0)
        # A pass that never ran (no row) is None too.
        self.assertEqual(report["dspark-v2"]["passes"], [60.0, None, 64.0])
        self.assertAlmostEqual(report["dspark-v2"]["speedup"], 2.0)
        self.assertEqual((report["dspark-v2"]["drafted"], report["dspark-v2"]["accepted"]), (40, 30))
        self.assertEqual(spec_bench.positional_passes([]), [])
        header = dict(self.header(), single={"n_predict": 20, "repeats": 3})
        text = spec_bench.render_markdown(header, {"tables": {}, "baseline": None}, None, [], rows,
                                          {"single": report})
        self.assertIn("| baseline | 30.00 | n/a | 32.00 | 31.00 | n/a | 1.00 | n/a |", text)
        self.assertIn("| dspark-v2 | 60.00 | n/a | 64.00 | 62.00 | 0.750 (30/40) | 4.00 | **2.00x** |", text)
        # A drafter with no successful pass has no mean and no speedup.
        report = spec_bench.single_summary(rows[:3] + [dict(rows[4], error="boom", tok_s=None)], self.names)
        self.assertEqual(report["dspark-v2"]["passes"], [None, None, None])
        self.assertIsNone(report["dspark-v2"]["mean_tok_s"])
        self.assertIsNone(report["dspark-v2"]["speedup"])

    def header(self):
        return {
            "note": "unit test", "created_utc": "now", "repeats": 1, "seed": 42, "slots": [1, 2, 4],
            "prompt_summary": "5 prompts", "config_names": self.names, "reasoning_effort": "template",
            "power_idle_s": 10, "mode": "launch", "build_info": "b0",
            "single": {"n_predict": 20, "repeats": 3},
            "environment": {"hostname": "h", "gpu_name": "G", "driver_version": "1",
                            "cuda_version": "13", "llama_server_version": "v", "gpu_smi_line": "G, 1",
                            "gpu_compute_apps": [{"name": "other", "used_memory": "1 MiB"}]},
        }

    def single_rows(self):
        single = {"id": spec_bench.SINGLE_ID, "category": "single", "set": "single", "n_predict": 20}
        rows = []
        for pass_no, rate in ((1, 30.0), (2, 31.0), (3, 32.0)):
            rows.append(make_row("baseline", single, rate, pass_no=pass_no))
            rows.append(make_row("dspark-v2", single, rate * 2, pass_no=pass_no, drafted=20, accepted=15))
        return rows

    def test_single_summary_and_placeholders(self):
        rows = self.rows + self.single_rows()
        single = spec_bench.single_summary(rows, self.names)
        self.assertEqual(single["baseline"]["passes"], [30.0, 31.0, 32.0])
        self.assertAlmostEqual(single["baseline"]["mean_tok_s"], 31.0)
        self.assertIsNone(single["baseline"]["speedup"])
        self.assertAlmostEqual(single["dspark-v2"]["speedup"], 2.0)
        self.assertAlmostEqual(single["dspark-v2"]["accept_rate"], 0.75)
        self.assertAlmostEqual(single["dspark-v2"]["tokens_per_step"], 4.0)
        # The single rows are not part of the workload tables.
        summary = spec_bench.summarize(self.prompts, rows, self.names)
        self.assertEqual({e["workload"] for e in summary["tables"]["dspark-v2"]},
                         {"code", "math", "tool", "agent", "blended (2 prompts)", "long-form (1 prompts, 8 tokens)"})
        outputs = dict(self.outputs)
        for r in self.single_rows():
            outputs[(r["config"], 1, r["prompt_id"], r["pass"])] = {"tokens": [1, 2], "content": ""}
        exact = spec_bench.exactness(rows, outputs, self.names, 1)
        self.assertEqual(exact["configs"]["dspark-v2"]["compared"], 8)
        self.assertTrue(exact["baseline_passes_identical"])
        # The tool's placeholders.json comes from fill_placeholders.build on
        # the results object, so it carries the documented key names.
        header = {"config_names": self.names, "environment": {"hostname": "h"}, "repeats": 1,
                  "configs_defined": {"dspark-v2": spec_bench.CONFIGS["dspark-v2"]}}
        results, extras = spec_bench.build_results(header, self.configs, rows, outputs, self.prompts, self.subset)
        self.assertEqual(results["single"], single)
        self.assertEqual(results["exactness"]["configs"]["dspark-v2"]["compared"], 8)
        self.assertEqual(extras["slots"], spec_bench.slot_summary(rows, self.configs, self.subset))
        ph = results["placeholders"]
        self.assertEqual(ph["labels.v2"], "DSpark v2 (K=5)")
        self.assertEqual(ph["labels.baseline"], "baseline")
        self.assertEqual((ph["single.baseline.p1"], ph["single.baseline.p3"], ph["single.baseline.mean"]),
                         ("30.0", "32.0", "31.0"))
        self.assertEqual((ph["single.v2.mean"], ph["single.v2.speedup"], ph["single.v2.accept"]),
                         ("62.0", "2.00x", "75.0%"))
        self.assertEqual(ph["single.v2.tps_step"], "4.00")
        self.assertNotIn("single.v2.tok_step", ph)
        self.assertEqual((ph["code.baseline"], ph["code.v2.tps"], ph["code.v2.accept"], ph["code.v2.speedup"]),
                         ("10.0", "25.0", "75.0%", "2.50x"))
        self.assertEqual(ph["code.baseline.tps"], "10.0")
        self.assertEqual(ph["code.v2.tps_step"], "4.00")
        self.assertNotIn("code.v2.tok_step", ph)
        self.assertEqual((ph["blended.baseline"], ph["blended.v2.speedup"]), ("10.0", "2.50x"))
        self.assertEqual((ph["long2000.baseline"], ph["long2000.v2.tps"]), ("10.0", "25.0"))
        self.assertEqual((ph["tool.v2.tps"], ph["agent.v2.speedup"]), ("25.0", "2.50x"))
        self.assertNotIn("math.v1.tps", ph)
        self.assertEqual((ph["slots.2.v2.stream"], ph["slots.2.v2.aggregate"], ph["slots.2.v2.accept"]),
                         ("20.0", "80.0", "50.0%"))
        self.assertEqual(ph["slots.2.v2.speedup"], "n/a")
        self.assertEqual((ph["slots.1.baseline.stream"], ph["slots.1.v2.speedup"]), ("10.0", "2.50x"))
        self.assertIn("n_parallel", ph["slots.4.v2.error"])
        self.assertEqual((ph["power.idle.w"], ph["power.baseline.w"], ph["power.baseline.mj"]),
                         ("20.0", "60.0", "6000"))
        self.assertNotIn("power.v2.w", ph)
        self.assertIn("nvidia-smi", ph["power.source"])
        self.assertEqual((ph["exact.v2.identical"], ph["exact.v2.total"]), ("6", "8"))
        self.assertTrue(all(isinstance(v, str) for v in ph.values()))

    def test_render_markdown_has_every_section(self):
        rows = self.rows + self.single_rows()
        summary = spec_bench.summarize(self.prompts, rows, self.names)
        exact = spec_bench.exactness(self.rows, self.outputs, self.names, 1)
        extras = {
            "long_form": spec_bench.long_form_table(self.prompts, self.rows, self.names),
            "tool_calls": spec_bench.tool_call_summary(self.rows, self.names),
            "slots": spec_bench.slot_summary(self.rows, self.configs, self.subset),
            "subset_ids": self.subset,
            "single": spec_bench.single_summary(rows, self.names),
        }
        failed = dict(self.rows[0], config="dspark-v2", error="URLError: timed out")
        text = spec_bench.render_markdown(self.header(), summary, exact, self.configs, self.rows + [failed], extras)
        self.assertIn("## Workload matrix: dspark-v2", text)
        self.assertIn("| workload | no drafter | DSpark v2 (K=5) | accept | tok/step | speedup |", text)
        self.assertIn("| --- | ---: | ---: | ---: | ---: | ---: |", text)
        self.assertIn("| blended (2 prompts) | 10.00 | 25.00 | 0.750 (30/40) | 4.00 | **2.50x** |", text)
        self.assertIn("| tool | 10.00 | 25.00 | 0.750 (15/20) | 4.00 | **2.50x** |", text)
        self.assertIn("| agent | 10.00 | 25.00 | 0.750 (15/20) | 4.00 | **2.50x** |", text)
        self.assertIn("mean prefix of 50 tokens", text)
        self.assertIn("## Long-form prompts", text)
        self.assertIn("| long-01 | 10.00 | 25.00 | 0.750 | 4.00 | **2.50x** |", text)
        self.assertIn("## Single prompt", text)
        self.assertIn("| config | pass 1 | pass 2 | pass 3 | mean | accept | tok/step | speedup |", text)
        self.assertIn("| baseline | 30.00 | 31.00 | 32.00 | 31.00 | n/a | 1.00 | n/a |", text)
        self.assertIn("| dspark-v2 | 60.00 | 62.00 | 64.00 | 62.00 | 0.750 (45/60) | 4.00 | **2.00x** |", text)
        self.assertIn("## Exactness", text)
        self.assertIn("| dspark-v2 | 3/5 | math-01: token 2; tool-01: char 8 |", text)
        self.assertIn("## Tool calls", text)
        self.assertIn("| baseline | 1/1 | 1/1 | tool_calls 1 | structured 1 |", text)
        self.assertIn("| dspark-v2 | 0/1 | 0/1 | tool_calls 1 | structured 1 |", text)
        self.assertIn("## Multi-slot", text)
        self.assertIn("| dspark-v2 | 2 | 2 | 20.00 | 80.00 | 0.500 | ok |", text)
        self.assertIn("| dspark-v2 | 4 | 0 | n/a | n/a | n/a | ERROR: llama-server exited", text)
        self.assertIn("## Power", text)
        self.assertIn("| baseline | 1 | 20.0 | 60.0 | 70.0 | 90 | 12 | 10.00 | 6000.0 |", text)
        self.assertIn("| dspark-v2 | 1 | n/a | n/a | n/a | n/a | n/a | n/a | nvidia-smi not found |", text)
        self.assertIn("- dspark-v2 slots 1 code-01 pass 1: URLError: timed out", text)
        self.assertIn("`dspark-v2` slots 2: `llama-server -np 2`", text)
        self.assertIn("GPU processes at start: other (1 MiB)", text)
        self.assertIn("Note: unit test", text)
        self.assertTrue(all(ord(c) < 128 for c in text))


class PlanTests(unittest.TestCase):
    def test_plan_covers_every_config_and_slot_count(self):
        args = spec_bench.parse_args(["--slots", "1,2,4", "--no-power", "--configs", "baseline,dspark-v2"])
        prompts, _ = spec_bench.load_prompts(args)
        subset = spec_bench.slot_subset(prompts, args.slot_ids)
        self.assertEqual(len(subset), 8)
        plan = spec_bench.plan_runs(args, prompts, subset)
        self.assertEqual([(e["config"], e["slots"]) for e in plan],
                         [("baseline", 1), ("baseline", 2), ("baseline", 4),
                          ("dspark-v2", 1), ("dspark-v2", 2), ("dspark-v2", 4)])
        self.assertEqual(plan[0]["prompts"], 62)
        self.assertEqual(plan[0]["requests"], 62 + 3)
        self.assertEqual(plan[0]["tokens"], 40 * 512 + 6 * 2000 + 16 * 512 + 3 * 256)
        self.assertEqual(plan[1]["prompts"], 8)
        self.assertEqual((plan[1]["requests"], plan[1]["tokens"]), (8, 8 * 512))
        self.assertGreater(plan[0]["seconds"], plan[3]["seconds"])
        args = spec_bench.parse_args(["--no-single", "--configs", "baseline"])
        plan = spec_bench.plan_runs(args, prompts, subset)
        self.assertEqual(plan[0]["tokens"], 40 * 512 + 6 * 2000 + 16 * 512)
        self.assertGreater(sum(e["seconds"] for e in plan), 0)

    def test_plan_only_prints_and_exits_without_a_run(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = pathlib.Path(tmp) / "out"
            code = spec_bench.main(["--plan-only", "--slots", "1,4", "--bin-dir", tmp,
                                    "--model", "absent.gguf", "--out", str(out)])
            self.assertEqual(code, 0)
            self.assertFalse((out / "results.json").exists())

    def test_n_predict_override_covers_chat_sets(self):
        args = spec_bench.parse_args(["--n-predict", "128", "--prompt-ids", "code-01,tool-01,agent-01,long-01"])
        prompts, _ = spec_bench.load_prompts(args)
        self.assertEqual([p["n_predict"] for p in prompts], [128, 128, 128, 2000])


class FakeServerRunTests(unittest.TestCase):
    """Run the tool end to end against a fake llama-server."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = pathlib.Path(self.tmp.name)
        self.bin_dir = root / "bin"
        self.bin_dir.mkdir()
        self.server = self.bin_dir / "llama-server"
        self.server.write_text(FAKE_SERVER)
        self.server.chmod(self.server.stat().st_mode | stat.S_IXUSR)
        self.model = root / "target.gguf"
        self.model.write_bytes(b"GGUF")
        self.drafter = root / "drafter.gguf"
        write_gguf(self.drafter, 7)
        self.out = root / "out"
        self.common = ["--bin-dir", str(self.bin_dir), "--model", str(self.model),
                       "--drafter-v1", str(self.drafter), "--drafter-v2", str(self.drafter),
                       "--warmup-tokens", "0", "--load-timeout", "30", "--allow-busy-gpu",
                       "--no-power", "--no-single", "--out", str(self.out)]

    def tearDown(self):
        self.tmp.cleanup()

    def results(self):
        with open(self.out / "results.json", encoding="utf-8") as f:
            return json.load(f)

    def test_launch_run_and_compare(self):
        code = spec_bench.main(self.common + [
            "--configs", "baseline,dspark-v2", "--add-config", "k7=%s:7" % self.drafter,
            "--port", str(free_port()), "--prompt-ids", "code-01,math-01,tool-01,agent-01",
            "--n-predict", "4", "--note", "fake server",
        ])
        del spec_bench.CONFIGS["k7"]
        self.assertEqual(code, 0)
        results = self.results()
        self.assertEqual([(c["name"], c["slots"]) for c in results["configs"]],
                         [("baseline", 1), ("dspark-v2", 1), ("k7", 1)])
        for cfg in results["configs"]:
            self.assertIsNone(cfg["error"])
            self.assertEqual(cfg["mode"], "launched")
            self.assertEqual(cfg["props"]["build_info"], "b0-test")
            self.assertIn("--jinja", cfg["server_args"])
            self.assertIsNone(cfg["power"])
        self.assertEqual(results["configs"][1]["drafter_metadata"]["dflash.block_size"], 7)
        self.assertTrue(results["configs"][1]["spec_engaged"])
        self.assertEqual(sorted(results["files"]), ["drafter_k7", "drafter_v2", "model"])
        self.assertTrue((self.out / "placeholders.json").exists())
        self.assertEqual(len(results["results"]), 12)
        endpoints = {r["prompt_id"]: r["endpoint"] for r in results["results"]}
        self.assertEqual(endpoints, {"code-01": "completion", "math-01": "completion",
                                     "tool-01": "chat", "agent-01": "chat"})
        tool_row = next(r for r in results["results"] if r["prompt_id"] == "tool-01" and r["config"] == "baseline")
        self.assertTrue(tool_row["tool_call_valid"])
        self.assertTrue(tool_row["tool_call_expected"])
        self.assertEqual(tool_row["tool_calls"], ["get_weather"])
        self.assertEqual(tool_row["timings_source"], "timings")
        self.assertEqual(tool_row["finish_reason"], "tool_calls")
        self.assertTrue(tool_row["templated_sha256"])
        self.assertEqual(results["tool_calls"]["baseline"]["valid"], 1)
        # K=7 leaves every output unchanged; K=5 changes one token, the tool
        # call arguments and the agent text.
        self.assertEqual(results["exactness"]["configs"]["k7"]["identical"], 4)
        self.assertEqual(results["exactness"]["configs"]["dspark-v2"]["identical"], 0)
        units = {d["prompt_id"]: d["unit"] for d in results["exactness"]["configs"]["dspark-v2"]["diffs"]}
        self.assertEqual(units, {"code-01": "token", "math-01": "token", "tool-01": "char", "agent-01": "char"})
        table = {e["workload"]: e for e in results["summary"]["tables"]["dspark-v2"]}
        self.assertAlmostEqual(table["tool"]["speedup"], 1.0)
        self.assertEqual(set(table), {"code", "math", "tool", "agent", "blended (2 prompts)"})
        self.assertEqual(results["schema_version"], 2)
        self.assertEqual(len(results["plan"]), 3)
        for name in ("summary.md", "outputs.json", "server-baseline-np1.log", "server-k7-np1.log"):
            self.assertTrue((self.out / name).exists(), name)
        text = (self.out / "summary.md").read_text()
        self.assertIn("## Tool calls", text)
        self.assertIn("## Exactness", text)
        self.assertNotIn("## Multi-slot", text)

    def test_single_prompt_passes_and_placeholders(self):
        code = spec_bench.main([a for a in self.common if a != "--no-single"] + [
            "--configs", "baseline,dspark-v1", "--port", str(free_port()),
            "--prompt-ids", "code-01", "--n-predict", "4", "--single-n-predict", "6",
        ])
        self.assertEqual(code, 0)
        results = self.results()
        single_rows = [r for r in results["results"] if r["set"] == "single"]
        self.assertEqual([(r["config"], r["pass"]) for r in single_rows],
                         [("baseline", 1), ("baseline", 2), ("baseline", 3),
                          ("dspark-v1", 1), ("dspark-v1", 2), ("dspark-v1", 3)])
        self.assertTrue(all(r["predicted_n"] == 6 and r["endpoint"] == "completion" for r in single_rows))
        self.assertEqual(results["single"]["baseline"]["passes"], [60.0, 60.0, 60.0])
        self.assertAlmostEqual(results["single"]["dspark-v1"]["speedup"], 1.0)
        self.assertAlmostEqual(results["single"]["dspark-v1"]["tokens_per_step"], 2.0)
        self.assertEqual(results["single"]["baseline"]["tokens_per_step"], 1.0)
        # K=4 leaves the output unchanged, so the 4 comparisons (1 prompt + 3 passes) are identical.
        self.assertEqual(results["exactness"]["configs"]["dspark-v1"]["compared"], 4)
        self.assertEqual(results["exactness"]["configs"]["dspark-v1"]["identical"], 4)
        self.assertTrue(results["exactness"]["baseline_passes_identical"])
        self.assertEqual(results["config_names"], ["baseline", "dspark-v1"])
        with open(self.out / "placeholders.json", encoding="utf-8") as f:
            ph = json.load(f)
        self.assertEqual(ph["single.baseline.p2"], "60.0")
        self.assertEqual(ph["single.v1.speedup"], "1.00x")
        self.assertEqual(ph["single.v1.accept"], "25.0%")
        self.assertEqual(ph["code.v1.tps"], "40.0")
        self.assertEqual(ph["labels.v1"], "DSpark v1 (Ternary-Bonsai-27B drafter, K=4)")
        self.assertEqual((ph["exact.v1.identical"], ph["exact.v1.total"]), ("4", "4"))
        # The map has the schema of fill_placeholders: tps_step, the
        # <W>.baseline.tps alias, and no power keys when power was not sampled.
        self.assertEqual((ph["single.v1.tps_step"], ph["code.v1.tps_step"]), ("2.00", "2.00"))
        self.assertEqual(ph["code.baseline.tps"], ph["code.baseline"])
        self.assertNotIn("single.v1.tok_step", ph)
        self.assertNotIn("power.idle.w", ph)
        self.assertIn("nvidia-smi", ph["power.source"])
        self.assertEqual(results["placeholders"], ph)
        text = (self.out / "summary.md").read_text()
        self.assertIn("## Single prompt", text)
        self.assertIn("| dspark-v1 | 60.00 | 60.00 | 60.00 | 60.00 | 0.250 (9/36) | 2.00 | **1.00x** |", text)

    def test_multi_slot_runs_record_the_refusal(self):
        code = spec_bench.main(self.common + [
            "--configs", "baseline,dspark-v2", "--slots", "1,2", "--port", str(free_port()),
            "--prompt-ids", "code-01,chat-01,tool-01", "--n-predict", "4",
        ])
        self.assertEqual(code, 1)
        results = self.results()
        self.assertEqual([(c["name"], c["slots"]) for c in results["configs"]],
                         [("baseline", 1), ("baseline", 2), ("dspark-v2", 1), ("dspark-v2", 2)])
        base2 = results["configs"][1]
        self.assertIsNone(base2["error"])
        self.assertEqual(base2["server_args"][base2["server_args"].index("-np") + 1], "2")
        self.assertEqual(base2["waves"], 2)
        self.assertGreater(base2["wave_seconds"], 0)
        drafter2 = results["configs"][3]
        self.assertIn("exited with code 1", drafter2["error"])
        self.assertIn("n_parallel == 1", drafter2["error"])
        slot_rows = [r for r in results["results"] if r["slots"] == 2]
        self.assertEqual(len(slot_rows), 3)
        self.assertEqual({r["wave"] for r in slot_rows}, {1, 2})
        entries = {(e["config"], e["slots"]): e for e in results["multi_slot"]}
        self.assertEqual(entries[("baseline", 2)]["ok"], 3)
        self.assertGreater(entries[("baseline", 2)]["aggregate_tok_s"], 0)
        self.assertEqual(entries[("dspark-v2", 2)]["ok"], 0)
        self.assertIn("n_parallel", entries[("dspark-v2", 2)]["error"])
        text = (self.out / "summary.md").read_text()
        self.assertIn("## Multi-slot", text)
        self.assertIn("| dspark-v2 | 2 | 0 | n/a | n/a | n/a | ERROR: llama-server exited with code 1", text)
        self.assertTrue((self.out / "server-dspark-v2-np2.log").exists())

    def test_missing_drafter_is_recorded_and_the_run_continues(self):
        code = spec_bench.main(self.common + [
            "--drafter-v2", str(self.drafter.with_name("absent.gguf")),
            "--configs", "dspark-v2,baseline", "--port", str(free_port()),
            "--limit", "1", "--n-predict", "4",
        ])
        self.assertEqual(code, 1)
        results = self.results()
        self.assertIn("missing file", results["configs"][0]["error"])
        self.assertIsNone(results["configs"][1]["error"])
        self.assertIn("Not run: missing file", (self.out / "summary.md").read_text())

    def test_remote_server_is_not_launched(self):
        port = free_port()
        proc = subprocess.Popen([str(self.server), "--port", str(port), "-md", "x",
                                 "--spec-draft-n-max", "4", "--no-timings"],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            for _ in range(50):
                if spec_bench.port_in_use("127.0.0.1", port):
                    break
                time.sleep(0.2)
            code = spec_bench.main([
                "--bin-dir", str(self.bin_dir), "--server-url", "dspark-v2=http://127.0.0.1:%d" % port,
                "--prompt-ids", "code-01,tool-01", "--n-predict", "4", "--warmup-tokens", "0",
                "--no-power", "--out", str(self.out),
            ])
        finally:
            proc.terminate()
            proc.wait()
        self.assertEqual(code, 0)
        results = self.results()
        self.assertEqual(results["config_names"], ["dspark-v2"])
        self.assertEqual(results["mode"], "server-url")
        self.assertEqual(results["configs"][0]["mode"], "remote")
        self.assertIsNone(results["configs"][0]["drafter"])
        self.assertIsNone(results["exactness"])
        self.assertEqual(results["files"], {})
        tool_row = next(r for r in results["results"] if r["prompt_id"] == "tool-01")
        self.assertEqual(tool_row["timings_source"], "wall")
        self.assertEqual(tool_row["predicted_n"], 4)
        self.assertGreater(tool_row["tok_s"], 0)
        self.assertEqual(results["tool_calls"]["dspark-v2"]["wall_timed"], 1)
        self.assertFalse((self.out / "server-dspark-v2-np1.log").exists())

    def test_zero_draft_counters_still_mean_speculation_is_engaged(self):
        port = free_port()
        proc = subprocess.Popen([str(self.server), "--port", str(port), "-md", "x",
                                 "--spec-draft-n-max", "4", "--draft-zero"],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            for _ in range(50):
                if spec_bench.port_in_use("127.0.0.1", port):
                    break
                time.sleep(0.2)
            out = io.StringIO()
            with redirect_stdout(out):
                code = spec_bench.main([
                    "--bin-dir", str(self.bin_dir), "--server-url", "dspark-v2=http://127.0.0.1:%d" % port,
                    "--prompt-ids", "code-01", "--n-predict", "4", "--warmup-tokens", "0",
                    "--no-power", "--no-single", "--out", str(self.out),
                ])
        finally:
            proc.terminate()
            proc.wait()
        self.assertEqual(code, 0)
        results = self.results()
        self.assertTrue(results["configs"][0]["spec_engaged"])
        self.assertEqual(results["results"][0]["draft_n"], 0)
        self.assertNotIn("speculation is not engaged", out.getvalue())

    def test_failed_single_pass_keeps_its_position(self):
        code = spec_bench.main([a for a in self.common if a != "--no-single"] + [
            "--configs", "baseline,dspark-v1", "--port", str(free_port()),
            "--prompt-ids", "code-01", "--n-predict", "4", "--single-n-predict", "6",
            "--server-extra", "--fail-single-pass 2",
        ])
        # A failed request makes the exit code 1; the run itself completes.
        self.assertEqual(code, 1)
        results = self.results()
        self.assertTrue(all(c["error"] is None for c in results["configs"]))
        failed = [r for r in results["results"] if r["error"] is not None]
        self.assertEqual([(r["config"], r["prompt_id"], r["pass"]) for r in failed],
                         [("baseline", spec_bench.SINGLE_ID, 2), ("dspark-v1", spec_bench.SINGLE_ID, 2)])
        self.assertIn("HTTP 500", failed[0]["error"])
        for name in ("baseline", "dspark-v1"):
            self.assertEqual(results["single"][name]["passes"], [60.0, None, 60.0])
            self.assertAlmostEqual(results["single"][name]["mean_tok_s"], 60.0)
        self.assertAlmostEqual(results["single"]["dspark-v1"]["speedup"], 1.0)
        # Pass 3 stays pass 3 in the placeholders; pass 2 prints as n/a.
        ph = results["placeholders"]
        self.assertEqual((ph["single.baseline.p1"], ph["single.baseline.p2"], ph["single.baseline.p3"]),
                         ("60.0", "n/a", "60.0"))
        self.assertEqual(ph["single.v1.mean"], "60.0")
        # Only the passes both sides completed are compared.
        self.assertEqual(results["exactness"]["configs"]["dspark-v1"]["compared"], 3)
        text = (self.out / "summary.md").read_text()
        self.assertIn("| baseline | 60.00 | n/a | 60.00 | 60.00 | n/a | 1.00 | n/a |", text)

    def test_missing_token_ids_fall_back_to_text_comparison(self):
        code = spec_bench.main(self.common + [
            "--configs", "baseline,dspark-v2", "--add-config", "k7=%s:7" % self.drafter,
            "--port", str(free_port()), "--prompt-ids", "code-01", "--n-predict", "4",
            "--server-extra=--no-tokens",
        ])
        del spec_bench.CONFIGS["k7"]
        self.assertEqual(code, 0)
        results = self.results()
        for r in results["results"]:
            self.assertIsNone(r["output_tokens"])
            self.assertIsNone(r["tokens_sha256"])
            self.assertEqual(r["output_chars"], 4)
        # K=5 changes the last token, so the text differs at character 3;
        # without ids the comparison must not call the two outputs identical.
        exact = results["exactness"]["configs"]
        self.assertEqual((exact["dspark-v2"]["compared"], exact["dspark-v2"]["identical"]), (1, 0))
        self.assertEqual((exact["dspark-v2"]["diffs"][0]["unit"], exact["dspark-v2"]["diffs"][0]["first_diff"]), ("char", 3))
        self.assertEqual((exact["k7"]["compared"], exact["k7"]["identical"]), (1, 1))
        with open(self.out / "outputs.json", encoding="utf-8") as f:
            dump = json.load(f)
        self.assertTrue(all(d["tokens"] is None for d in dump))

    def test_truncated_drafter_is_recorded_and_the_run_continues(self):
        truncated = self.drafter.with_name("short.gguf")
        truncated.write_bytes(self.drafter.read_bytes()[:40])
        code = spec_bench.main(self.common + [
            "--drafter-v2", str(truncated), "--configs", "dspark-v2,baseline", "--port", str(free_port()),
            "--prompt-ids", "code-01", "--n-predict", "4",
        ])
        self.assertEqual(code, 1)
        results = self.results()
        self.assertIn("cannot read the GGUF header", results["configs"][0]["error"])
        self.assertIn("short.gguf", results["configs"][0]["error"])
        self.assertIsNone(results["configs"][1]["error"])
        self.assertEqual([r["config"] for r in results["results"]], ["baseline"])

    def test_props_error_is_recorded_and_the_run_continues(self):
        original = spec_bench.fetch_props
        calls = {"n": 0}

        def broken_once(url):
            calls["n"] += 1
            if calls["n"] == 1:
                raise spec_bench.HttpError(500, "props broken")
            return original(url)

        spec_bench.fetch_props = broken_once
        try:
            code = spec_bench.main(self.common + [
                "--configs", "baseline,dspark-v1", "--port", str(free_port()),
                "--prompt-ids", "code-01", "--n-predict", "4",
            ])
        finally:
            spec_bench.fetch_props = original
        self.assertEqual(code, 1)
        results = self.results()
        self.assertEqual(results["configs"][0]["error"], "HttpError: HTTP 500: props broken")
        self.assertIsNone(results["configs"][1]["error"])
        self.assertEqual(results["configs"][1]["props"]["build_info"], "b0-test")
        self.assertEqual([r["config"] for r in results["results"]], ["dspark-v1"])
        # The failed server was stopped before the next one took the port.
        self.assertTrue((self.out / "server-baseline-np1.log").exists())
        self.assertIn("error: HttpError: HTTP 500: props broken", (self.out / "summary.md").read_text())


if __name__ == "__main__":
    unittest.main()
