import importlib.util
import io
import json
import pathlib
import stat
import subprocess
import tempfile
import time
import unittest
from contextlib import redirect_stdout, redirect_stderr


ROOT = pathlib.Path(__file__).resolve().parents[1]


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / "spec_bench" / (name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


fill_placeholders = load("fill_placeholders")
fill_doc = load("fill_doc")
single_prompt_bench = load("single_prompt_bench")
spec = importlib.util.spec_from_file_location("test_spec_bench", ROOT / "tests" / "test_spec_bench.py")
test_spec_bench = importlib.util.module_from_spec(spec)
spec.loader.exec_module(test_spec_bench)

WORKLOAD_ROWS = [
    ("code-01", "matrix", "code"), ("math-01", "matrix", "math"), ("reasoning-01", "matrix", "reasoning"),
    ("chat-01", "matrix", "chat"), ("long-form-01", "matrix", "long-form"), ("long-01", "long", "long-form"),
    ("tool-01", "tool", "tool"), ("agent-01", "agent", "agent"),
]


def quiet(func, *args):
    out = io.StringIO()
    with redirect_stdout(out), redirect_stderr(out):
        code = func(*args)
    return code, out.getvalue()


def synthetic_results(with_single=True):
    """A results.json object that covers every placeholder key."""
    names = ["baseline", "dspark-v1", "dspark-v2"]
    rates = {"baseline": 30.0, "dspark-v1": 45.0, "dspark-v2": 60.0}
    rows = []
    for name in names:
        for pid, set_name, category in WORKLOAD_ROWS:
            row = {"config": name, "slots": 1, "prompt_id": pid, "category": category, "set": set_name,
                   "pass": 1, "error": None, "tok_s": rates[name], "predicted_n": 100, "wall_ms": 4000.0,
                   "draft_n": None, "draft_n_accepted": None}
            if name != "baseline":
                row["draft_n"] = 120
                row["draft_n_accepted"] = 60
            rows.append(row)
    multi_slot = []
    for slots in (1, 2, 4):
        for name in names:
            multi_slot.append({"config": name, "slots": slots, "prompts": 8, "ok": 8, "errors": 0,
                               "per_stream_tok_s": rates[name] / slots, "aggregate_tok_s": rates[name] * 0.8,
                               "accept_rate": None if name == "baseline" else 0.5, "error": None})
    configs = []
    for name in names:
        configs.append({"name": name, "slots": 1, "power": {"idle_w": 20.5, "mean_w": 50.0 + len(name),
                                                             "energy_mj_per_token": 1234.5}})
    exact = {"configs": {"dspark-v1": {"compared": 62, "identical": 62},
                         "dspark-v2": {"compared": 62, "identical": 61}}}
    single = None
    if with_single:
        single = {}
        for name in names:
            passes = [rates[name] + i for i in range(3)]
            single[name] = {"passes": passes, "predicted_n": 768,
                            "drafted": 0 if name == "baseline" else 900,
                            "accepted": 0 if name == "baseline" else 400}
    return {
        "schema_version": 2, "config_names": names, "environment": {"hostname": "gb10"},
        "results": rows, "multi_slot": multi_slot, "configs": configs, "exactness": exact, "single": single,
    }


class FillPlaceholdersTests(unittest.TestCase):
    def test_synthetic_run_covers_every_key(self):
        ph = fill_placeholders.build(synthetic_results())
        missing = [k for k in fill_placeholders.expected_keys() if k not in ph]
        self.assertEqual(missing, [])
        self.assertEqual(ph["labels.v1"], "DSpark v1 (Ternary-Bonsai-27B drafter, K=4)")
        self.assertEqual(ph["labels.v2"], "DSpark v2 (K=5)")
        self.assertEqual((ph["code.baseline"], ph["code.baseline.tps"]), ("30.0", "30.0"))
        self.assertEqual((ph["code.v2.tps"], ph["code.v2.accept"], ph["code.v2.speedup"]), ("60.0", "50.0%", "2.00x"))
        self.assertEqual(ph["code.v1.speedup"], "1.50x")
        # 100 tokens with 60 accepted: 100 / 40 = 2.5 tokens per step.
        self.assertEqual(ph["code.v2.tps_step"], "2.50")
        self.assertEqual(ph["blended.v2.tps_step"], "2.50")
        self.assertEqual((ph["longform.baseline"], ph["long2000.v1.tps"], ph["tool.v2.accept"]), ("30.0", "45.0", "50.0%"))
        self.assertEqual((ph["single.baseline.p1"], ph["single.baseline.p3"], ph["single.baseline.mean"]), ("30.0", "32.0", "31.0"))
        self.assertEqual((ph["single.v2.mean"], ph["single.v2.speedup"], ph["single.v2.accept"]), ("61.0", "1.97x", "44.4%"))
        # 768 tokens with 400 accepted: 768 / 368.
        self.assertEqual(ph["single.v2.tps_step"], "2.09")
        self.assertEqual((ph["slots.4.baseline.stream"], ph["slots.4.v2.stream"], ph["slots.4.v2.speedup"]), ("7.5", "15.0", "2.00x"))
        self.assertEqual((ph["slots.2.v2.aggregate"], ph["slots.2.v2.aggregate_speedup"], ph["slots.2.v2.accept"]), ("48.0", "2.00x", "50.0%"))
        self.assertEqual((ph["power.idle.w"], ph["power.baseline.w"], ph["power.v2.mj"]), ("20.5", "58.0", "1234"))
        self.assertIn("nvidia-smi", ph["power.source"])
        self.assertEqual((ph["exact.v2.identical"], ph["exact.v2.total"], ph["exact.v1.identical"]), ("61", "62", "62"))
        self.assertTrue(all(isinstance(v, str) for v in ph.values()))

    def test_speedup_uses_prompts_present_in_both_configs(self):
        results = synthetic_results()
        results["results"] = [r for r in results["results"]
                              if not (r["config"] == "baseline" and r["prompt_id"] == "math-01")]
        ph = fill_placeholders.build(results)
        self.assertNotIn("math.baseline", ph)
        self.assertNotIn("math.v2.tps", ph)
        self.assertEqual(ph["blended.v2.speedup"], "2.00x")

    def test_single_json_overrides_results(self):
        results = synthetic_results()
        single = {"schema_version": 1, "configs": {
            "baseline": {"passes": [10.0, 10.0, 10.0], "predicted_n": 30, "drafted": 0, "accepted": 0, "error": None},
            "dspark-v2": {"passes": [20.0, 20.0, 20.0], "predicted_n": 30, "drafted": 40, "accepted": 20, "error": None},
            "dspark-v1": {"passes": [], "error": "missing file", "predicted_n": 0, "drafted": 0, "accepted": 0},
        }}
        ph = fill_placeholders.build(results, single)
        self.assertEqual((ph["single.baseline.mean"], ph["single.v2.speedup"], ph["single.v2.accept"]), ("10.0", "2.00x", "50.0%"))
        self.assertEqual(ph["single.v2.tps_step"], "3.00")
        self.assertNotIn("single.v1.mean", ph)

    def test_failed_slot_run_records_the_error(self):
        results = synthetic_results()
        for e in results["multi_slot"]:
            if e["config"] == "dspark-v2" and e["slots"] == 4:
                e.update({"ok": 0, "errors": 0, "error": "llama-server exited with code 1 before it was ready"})
        ph = fill_placeholders.build(results)
        self.assertNotIn("slots.4.v2.stream", ph)
        self.assertIn("exited with code 1", ph["slots.4.v2.error"])

    def test_partial_run_reports_missing_keys(self):
        # A run without the math prompts, the 2-slot runs and the v1 exactness
        # report leaves keys out: the script lists them and --strict fails.
        results = synthetic_results()
        results["results"] = [r for r in results["results"] if r["category"] != "math"]
        results["multi_slot"] = [e for e in results["multi_slot"] if e["slots"] != 2]
        del results["exactness"]["configs"]["dspark-v1"]
        with tempfile.TemporaryDirectory() as tmp:
            run_dir = pathlib.Path(tmp) / "run"
            run_dir.mkdir()
            with open(run_dir / "results.json", "w", encoding="utf-8") as f:
                json.dump(results, f)
            out = run_dir / "placeholders.json"
            code, text = quiet(fill_placeholders.main, [str(run_dir), "--out", str(out)])
            self.assertEqual(code, 0)
            self.assertIn("expected keys missing", text)
            self.assertIn("math.baseline", text)
            self.assertIn("slots.2.baseline.stream", text)
            with open(out, encoding="utf-8") as f:
                ph = json.load(f)
            self.assertEqual(ph["labels.v2"], "DSpark v2 (K=5)")
            self.assertEqual(ph["exact.v2.total"], "62")
            self.assertRegex(ph["code.v2.speedup"], r"^\d+\.\d\dx$")
            self.assertRegex(ph["code.v2.accept"], r"^\d+\.\d%$")
            self.assertRegex(ph["single.baseline.p2"], r"^\d+\.\d$")
            self.assertNotIn("math.baseline", ph)
            self.assertNotIn("exact.v1.total", ph)
            code, text = quiet(fill_placeholders.main, [str(run_dir), "--out", str(out), "--strict"])
            self.assertEqual(code, 1)

    def test_missing_results_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            code, _ = quiet(fill_placeholders.main, [tmp])
        self.assertEqual(code, 2)


DOC = """# Report

Baseline runs at {{BENCH:code.baseline}} tok/s; with DSpark v2 it runs at
{{BENCH:code.v2.tps}} tok/s ({{BENCH:code.v2.speedup}}, acceptance {{BENCH:code.v2.accept}}).
Again: {{BENCH:code.baseline}}.
"""


class FillDocTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = pathlib.Path(self.tmp.name)
        self.doc = root / "doc.md"
        self.doc.write_text(DOC)
        self.values = root / "placeholders.json"

    def tearDown(self):
        self.tmp.cleanup()

    def write_values(self, values):
        self.values.write_text(json.dumps(values))

    def test_find_keys_and_fill(self):
        self.assertEqual(fill_doc.find_keys(DOC), ["code.baseline", "code.v2.tps", "code.v2.speedup", "code.v2.accept"])
        filled, missing = fill_doc.fill(DOC, {"code.baseline": "30.0", "code.v2.tps": "60.0"})
        self.assertEqual(missing, ["code.v2.speedup", "code.v2.accept"])
        self.assertIn("runs at 30.0 tok/s", filled)
        self.assertIn("{{BENCH:code.v2.speedup}}", filled)

    def test_check_reports_and_writes_nothing(self):
        self.write_values({"code.baseline": "30.0", "code.v2.tps": "60.0", "unused.key": "1"})
        code, text = quiet(fill_doc.main, [str(self.doc), str(self.values), "--check"])
        self.assertEqual(code, 1)
        self.assertIn("2 markers have no value: code.v2.speedup, code.v2.accept", text)
        self.assertIn("1 values have no marker: unused.key", text)
        self.assertIn("5 markers, 4 distinct keys, 3 values", text)
        self.assertEqual(self.doc.read_text(), DOC)

    def test_refuses_to_write_with_a_missing_key(self):
        self.write_values({"code.baseline": "30.0", "code.v2.tps": "60.0", "code.v2.speedup": "2.00x"})
        code, text = quiet(fill_doc.main, [str(self.doc), str(self.values)])
        self.assertEqual(code, 1)
        self.assertIn("refused to write", text)
        self.assertEqual(self.doc.read_text(), DOC)

    def test_fills_in_place_and_to_out(self):
        values = {"code.baseline": "30.0", "code.v2.tps": "60.0", "code.v2.speedup": "2.00x", "code.v2.accept": "52.1%"}
        self.write_values(values)
        out = self.doc.with_name("filled.md")
        code, text = quiet(fill_doc.main, [str(self.doc), str(self.values), "--out", str(out)])
        self.assertEqual(code, 0)
        self.assertEqual(self.doc.read_text(), DOC)
        filled = out.read_text()
        self.assertNotIn("{{BENCH:", filled)
        self.assertIn("60.0 tok/s (2.00x, acceptance 52.1%)", filled)
        self.assertIn("Again: 30.0.", filled)
        code, _ = quiet(fill_doc.main, [str(self.doc), str(self.values)])
        self.assertEqual(code, 0)
        self.assertEqual(self.doc.read_text(), filled)
        code, text = quiet(fill_doc.main, [str(self.doc), str(self.values), "--check"])
        self.assertEqual(code, 0)
        self.assertIn("0 markers, 0 distinct keys", text)

    def test_na_values_warn_or_fail_with_strict(self):
        self.write_values({"code.baseline": "30.0", "code.v2.tps": "n/a", "code.v2.speedup": "n/a", "code.v2.accept": "52.1%"})
        code, text = quiet(fill_doc.main, [str(self.doc), str(self.values), "--check"])
        self.assertEqual(code, 0)
        self.assertIn("2 markers would print n/a", text)
        code, text = quiet(fill_doc.main, [str(self.doc), str(self.values), "--strict"])
        self.assertEqual(code, 1)
        self.assertEqual(self.doc.read_text(), DOC)

    def test_malformed_marker_is_a_problem(self):
        self.doc.write_text("value {{BENCH:code baseline}} here")
        self.write_values({})
        code, text = quiet(fill_doc.main, [str(self.doc), str(self.values), "--check"])
        self.assertEqual(code, 1)
        self.assertIn("malformed markers", text)

    def test_bad_inputs(self):
        code, _ = quiet(fill_doc.main, [str(self.doc), str(self.doc.with_name("absent.json"))])
        self.assertEqual(code, 2)
        self.values.write_text("[1, 2]")
        code, _ = quiet(fill_doc.main, [str(self.doc), str(self.values)])
        self.assertEqual(code, 2)


class SinglePromptBenchTests(unittest.TestCase):
    """Run the runner end to end against the fake llama-server of test_spec_bench."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = pathlib.Path(self.tmp.name)
        self.bin_dir = root / "bin"
        self.bin_dir.mkdir()
        self.server = self.bin_dir / "llama-server"
        self.server.write_text(test_spec_bench.FAKE_SERVER)
        self.server.chmod(self.server.stat().st_mode | stat.S_IXUSR)
        self.model = root / "target.gguf"
        self.model.write_bytes(b"GGUF")
        self.drafter = root / "drafter.gguf"
        test_spec_bench.write_gguf(self.drafter, 4)
        self.out = root / "out"

    def tearDown(self):
        self.tmp.cleanup()

    def single(self):
        with open(self.out / "single.json", encoding="utf-8") as f:
            return json.load(f)

    def test_launch_three_passes_per_config(self):
        code, text = quiet(single_prompt_bench.main, [
            "--bin-dir", str(self.bin_dir), "--model", str(self.model), "--drafter-v1", str(self.drafter),
            "--drafter-v2", str(self.drafter), "--configs", "baseline,dspark-v1",
            "--add-config", "k7=%s:7" % self.drafter, "--port", str(test_spec_bench.free_port()),
            "--repeats", "3", "--n-predict", "6", "--warmup-tokens", "0", "--load-timeout", "30",
            "--allow-busy-gpu", "--out", str(self.out),
        ])
        del single_prompt_bench.sb.CONFIGS["k7"]
        self.assertEqual(code, 0, text)
        data = self.single()
        self.assertEqual(data["config_names"], ["baseline", "dspark-v1", "k7"])
        self.assertEqual((data["repeats"], data["n_predict"], data["seed"]), (3, 6, 42))
        self.assertIn("quicksort", data["prompt"])
        for name in data["config_names"]:
            entry = data["configs"][name]
            self.assertIsNone(entry["error"])
            self.assertEqual(entry["mode"], "launched")
            self.assertEqual(entry["passes"], [60.0, 60.0, 60.0])
            self.assertEqual(entry["server_args"][entry["server_args"].index("-np") + 1], "1")
            self.assertEqual(entry["props"]["build_info"], "b0-test")
        self.assertEqual(data["configs"]["baseline"]["tokens_per_step"], 1.0)
        v1 = data["configs"]["dspark-v1"]
        self.assertEqual(v1["server_args"][v1["server_args"].index("--spec-draft-n-max") + 1], "4")
        self.assertEqual((v1["drafted"], v1["accepted"]), (36, 9))
        self.assertAlmostEqual(v1["tokens_per_step"], 2.0)
        self.assertAlmostEqual(v1["speedup"], 1.0)
        self.assertEqual(v1["identical_to_baseline"], "3/3")
        self.assertEqual(data["configs"]["k7"]["drafter_metadata"]["dflash.block_size"], 4)
        self.assertIn("pass 3:", text)
        self.assertIn("identical", text)
        self.assertTrue((self.out / "single-server-baseline.log").exists())
        self.assertTrue((self.out / "single-outputs.json").exists())
        # fill_placeholders picks single.json up from the results directory.
        results = synthetic_results(with_single=False)
        with open(self.out / "results.json", "w", encoding="utf-8") as f:
            json.dump(results, f)
        code, text = quiet(fill_placeholders.main, [str(self.out)])
        self.assertEqual(code, 0)
        self.assertIn("single prompt data from", text)
        with open(self.out / "placeholders.json", encoding="utf-8") as f:
            ph = json.load(f)
        self.assertEqual((ph["single.baseline.p1"], ph["single.v1.mean"], ph["single.v1.speedup"]), ("60.0", "60.0", "1.00x"))
        self.assertEqual(ph["single.v1.accept"], "25.0%")
        self.assertEqual(ph["single.k7.mean"], "60.0")

    def test_missing_drafter_is_recorded_and_the_run_continues(self):
        code, text = quiet(single_prompt_bench.main, [
            "--bin-dir", str(self.bin_dir), "--model", str(self.model),
            "--drafter-v2", str(self.drafter.with_name("absent.gguf")), "--configs", "dspark-v2,baseline",
            "--port", str(test_spec_bench.free_port()), "--repeats", "1", "--n-predict", "4",
            "--warmup-tokens", "0", "--allow-busy-gpu", "--out", str(self.out),
        ])
        self.assertEqual(code, 1)
        data = self.single()
        self.assertIn("missing file", data["configs"]["dspark-v2"]["error"])
        self.assertEqual(data["configs"]["dspark-v2"]["passes"], [])
        self.assertEqual(data["configs"]["baseline"]["passes"], [40.0])

    def test_remote_server_is_not_launched(self):
        port = test_spec_bench.free_port()
        proc = subprocess.Popen([str(self.server), "--port", str(port), "-md", "x", "--spec-draft-n-max", "5"],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            for _ in range(50):
                if single_prompt_bench.sb.port_in_use("127.0.0.1", port):
                    break
                time.sleep(0.2)
            code, text = quiet(single_prompt_bench.main, [
                "--bin-dir", str(self.bin_dir), "--server-url", "dspark-v2=http://127.0.0.1:%d" % port,
                "--repeats", "2", "--n-predict", "4", "--warmup-tokens", "0", "--out", str(self.out),
            ])
        finally:
            proc.terminate()
            proc.wait()
        self.assertEqual(code, 0, text)
        data = self.single()
        self.assertEqual(data["mode"], "server-url")
        self.assertEqual(data["config_names"], ["dspark-v2"])
        entry = data["configs"]["dspark-v2"]
        self.assertEqual(entry["mode"], "remote")
        self.assertEqual(len(entry["passes"]), 2)
        self.assertIsNone(entry["speedup"])
        self.assertFalse((self.out / "single-server-dspark-v2.log").exists())


if __name__ == "__main__":
    unittest.main()
