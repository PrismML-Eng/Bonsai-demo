"""Game-mode harness tests against a scripted OpenAI-compatible fake server; no model or GPU needed.

  python3 scripts/agent/test_game_harness.py            # proxy tests only (stdlib)
  HERMES_VENV=.venv-hermes python3 scripts/agent/test_game_harness.py   # + end-to-end runs of run_agent_demo.sh game
                                                                       #   with the patched Hermes (install_hermes.sh)

Proxy (logproxy.py):
  * a request marked as an empty-reply resample (header X-Agent-Resample, sent by the patched Hermes) gets a
    different seed, so a seeded server can return a different reply; the header is not forwarded; unmarked requests
    keep their seed even when they repeat an earlier request; RESEED_REPEATS=0 leaves marked requests alone too;
  * the cut turn of the cut tool-call recovery keeps its own reasoning (PRESERVE_REASONING=1) or drops it, and the
    "prism_cut_reasoning" key never reaches the server.
End to end (run_agent_demo.sh game, patched Hermes, proxy, fake server):
  * empty reply -> one resample with a new seed -> the run finishes (and with AGENT_RESEED=0 the resamples repeat the
    empty reply until the recovery gives up);
  * a write_file cut by the output limit is not executed; the model gets the split-the-work note; the next call writes;
  * the run's config and every request carry max_tokens 49152 (game16), threshold 0.93907518, max_turns 150.
"""
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import urllib.request
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

AGENT = Path(__file__).resolve().parent
DEMO = AGENT.parent.parent
MODEL = "test-model"
EMPTY_SEED = 42                       # the fake model answers empty whenever it samples with this seed
PARTIAL = json.dumps({"path": "racer.html", "content": "<!doctype html>" + "x" * 3000})[:-5]  # unterminated JSON


def free_port():
    s = socket.socket(); s.bind(("127.0.0.1", 0)); p = s.getsockname()[1]; s.close(); return p


class FakeServer:
    """Scripted chat server. Agent requests (those with tools) are answered by `script(n, body)`, n = 1, 2, ...; every
    request body is recorded. /props reports n_predict like llama-server started with AGENT_PROFILE=game16."""

    def __init__(self, script, n_predict=49152, delay_first=0):
        self.script, self.requests, self.headers, self.n = script, [], [], 0
        fake = self

        class H(BaseHTTPRequestHandler):
            def log_message(self, *a):
                pass

            def _json(self, obj):
                b = json.dumps(obj).encode()
                self.send_response(200); self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)

            def do_GET(self):
                if self.path.startswith("/v1/models"):
                    return self._json({"object": "list", "data": [{"id": MODEL, "object": "model"}]})
                if self.path.startswith("/props"):
                    return self._json({"total_slots": 1, "default_generation_settings": {
                        "n_ctx": 262144, "params": {"n_predict": n_predict, "seed": 42}}})
                self.send_response(404); self.end_headers()

            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers.get("Content-Length") or 0)) or b"{}")
                fake.requests.append(body); fake.headers.append({k.lower(): v for k, v in self.headers.items()})
                if body.get("tools"):
                    fake.n += 1
                    if fake.n == 1 and delay_first:
                        time.sleep(delay_first)  # the runner requires Hermes to be alive 4 s after launch
                    reply = fake.script(fake.n, body)
                else:
                    reply = {"content": "ok"}
                reply = dict(reply); finish = reply.pop("finish", "tool_calls" if reply.get("tool_calls") else "stop")
                usage = {"prompt_tokens": 100, "completion_tokens": reply.pop("tokens", 50), "total_tokens": 150}
                cid = "chatcmpl-" + uuid.uuid4().hex[:8]
                if not body.get("stream"):
                    msg = {"role": "assistant", "content": reply.get("content", "")}
                    if reply.get("reasoning"): msg["reasoning_content"] = reply["reasoning"]
                    if reply.get("tool_calls"): msg["tool_calls"] = [dict(tc, type="function") for tc in reply["tool_calls"]]
                    return self._json({"id": cid, "object": "chat.completion", "model": MODEL, "usage": usage,
                                       "choices": [{"index": 0, "message": msg, "finish_reason": finish}]})
                self.send_response(200); self.send_header("Content-Type", "text/event-stream"); self.end_headers()

                def ev(delta, fr=None):
                    self.wfile.write(("data: " + json.dumps({"id": cid, "object": "chat.completion.chunk", "model": MODEL,
                                     "choices": [{"index": 0, "delta": delta, "finish_reason": fr}]}) + "\n\n").encode())
                ev({"role": "assistant"})
                if reply.get("reasoning"): ev({"reasoning_content": reply["reasoning"]})
                if reply.get("content"): ev({"content": reply["content"]})
                for i, tc in enumerate(reply.get("tool_calls") or []):
                    args = tc["function"]["arguments"]
                    ev({"tool_calls": [{"index": i, "id": tc["id"], "type": "function",
                                        "function": {"name": tc["function"]["name"], "arguments": ""}}]})
                    for j in range(0, len(args), 500):
                        ev({"tool_calls": [{"index": i, "function": {"arguments": args[j:j + 500]}}]})
                ev({}, finish)
                self.wfile.write(("data: " + json.dumps({"id": cid, "object": "chat.completion.chunk", "choices": [],
                                                         "usage": usage}) + "\n\ndata: [DONE]\n\n").encode())
                self.wfile.flush()

        self.port = free_port()
        self.httpd = ThreadingHTTPServer(("127.0.0.1", self.port), H)
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()

    def agent_requests(self):
        return [r for r in self.requests if r.get("tools")]

    def close(self):
        self.httpd.shutdown(); self.httpd.server_close()


def tool_call(name, args):
    return {"id": "call_" + uuid.uuid4().hex[:10], "function": {"name": name, "arguments": args if isinstance(args, str) else json.dumps(args)}}


def seeded_script(n, body):
    """Call 1 writes the page; every later call answers empty with seed 42 and finishes with any other seed."""
    if n == 1:
        return {"reasoning": "write it.", "tool_calls": [tool_call("write_file", {"path": "racer.html", "content": "<html>ok</html>\n"})]}
    if body.get("seed") == EMPTY_SEED:
        return {"reasoning": "thought until the budget ran out", "content": ""}
    return {"reasoning": "final.", "content": "done."}


def cut_script(n, body):
    """Call 1: write_file cut by the output limit. Call 2: the page in a small write. Call 3: done."""
    if n == 1:
        return {"reasoning": "CUTREASON plan the whole file in one call", "tool_calls": [tool_call("write_file", PARTIAL)],
                "finish": "length", "tokens": 49152}
    if n == 2:
        return {"reasoning": "smaller part.", "tool_calls": [tool_call("write_file", {"path": "racer.html", "content": "PART1\n"})]}
    return {"reasoning": "final.", "content": "done."}


class Proxy:
    def __init__(self, upstream_port, out, **env):
        self.port = free_port()
        e = dict(os.environ, **{k: str(v) for k, v in env.items()})
        self.p = subprocess.Popen([sys.executable, str(AGENT / "logproxy.py"), str(self.port), "127.0.0.1", str(upstream_port), str(out)],
                                  env=e, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(50):
            try:
                urllib.request.urlopen(f"http://127.0.0.1:{self.port}/v1/models", timeout=1).read(); break
            except Exception:
                time.sleep(0.1)

    def chat(self, body, resample=None):
        h = {"Content-Type": "application/json"}
        if resample:
            h["X-Agent-Resample"] = str(resample)
        req = urllib.request.Request(f"http://127.0.0.1:{self.port}/v1/chat/completions", data=json.dumps(body).encode(),
                                     headers=h, method="POST")
        return json.loads(urllib.request.urlopen(req, timeout=30).read())

    def close(self):
        self.p.terminate(); self.p.wait(5)


TOOLS = [{"type": "function", "function": {"name": "write_file", "parameters": {"type": "object"}}}]


class ProxyTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="bonsai-proxy-test-")); self.addCleanup(shutil.rmtree, self.tmp, True)

    def _proxy(self, fake, **env):
        p = Proxy(fake.port, self.tmp / "wire.jsonl", **env); self.addCleanup(p.close); return p

    def _wire(self):
        return [json.loads(l) for l in (self.tmp / "wire.jsonl").read_text().splitlines()]

    REQ = {"model": MODEL, "messages": [{"role": "user", "content": "go"}], "tools": TOOLS}

    def _content(self, reply):
        return reply["choices"][0]["message"]["content"]

    def test_marked_resample_gets_a_new_seed(self):
        fake = FakeServer(lambda n, b: seeded_script(2, b)); self.addCleanup(fake.close)
        proxy = self._proxy(fake, INJECT_BODY=json.dumps({"seed": 42, "max_tokens": 49152}))
        replies = [self._content(proxy.chat(self.REQ, resample=n)) for n in (None, 1, 2)]
        self.assertEqual([r.get("seed") for r in fake.requests], [42, 43, 44])
        self.assertEqual(replies, ["", "done.", "done."])
        self.assertEqual([w["resample"] for w in self._wire()], [None, 1, 2])
        proxy.chat(self.REQ)
        self.assertEqual(fake.requests[-1]["seed"], 42)  # unmarked: the injected seed, although the body repeats

    def test_identical_successful_requests_keep_an_explicit_seed(self):
        """Control: two identical unmarked requests with an explicit seed 42 that both succeed go out with seed 42."""
        fake = FakeServer(lambda n, b: {"content": "done."}); self.addCleanup(fake.close)
        proxy = self._proxy(fake)
        req = dict(self.REQ, seed=42)
        replies = [self._content(proxy.chat(req)) for _ in range(2)]
        self.assertEqual(replies, ["done.", "done."])
        self.assertEqual([r.get("seed") for r in fake.requests], [42, 42])
        self.assertEqual(fake.requests[0], fake.requests[1])

    def test_resample_marker_is_not_forwarded(self):
        fake = FakeServer(lambda n, b: {"content": "done."}); self.addCleanup(fake.close)
        proxy = self._proxy(fake)
        proxy.chat(dict(self.REQ, seed=7), resample=1)
        self.assertNotIn("x-agent-resample", fake.headers[-1])
        self.assertNotIn("X-Agent-Resample", json.dumps(fake.requests[-1]))
        self.assertEqual(fake.requests[-1]["seed"], 8)

    def test_marked_resample_without_seed_gets_a_random_one(self):
        fake = FakeServer(lambda n, b: seeded_script(2, b)); self.addCleanup(fake.close)
        proxy = self._proxy(fake)
        proxy.chat(self.REQ); proxy.chat(self.REQ, resample=1)
        self.assertNotIn("seed", fake.requests[0])
        self.assertIsInstance(fake.requests[1].get("seed"), int)

    def test_reseed_off_keeps_the_seed_on_marked_requests(self):
        fake = FakeServer(lambda n, b: seeded_script(2, b)); self.addCleanup(fake.close)
        proxy = self._proxy(fake, INJECT_BODY=json.dumps({"seed": 42}), RESEED_REPEATS=0)
        replies = [self._content(proxy.chat(self.REQ, resample=n)) for n in (None, 1, 2)]
        self.assertEqual([r.get("seed") for r in fake.requests], [42, 42, 42])
        self.assertEqual(replies, ["", "", ""])
        self.assertTrue(all("x-agent-resample" not in h for h in fake.headers))

    def _cut_history(self):
        return [{"role": "user", "content": "go"},
                {"role": "assistant", "content": "", "prism_cut_reasoning": "CUTREASON own thinking"},
                {"role": "user", "content": "[System: Your previous tool call (write_file) was cut off ...]"}]

    def test_cut_turn_keeps_its_reasoning_when_preserved(self):
        fake = FakeServer(lambda n, b: {"content": ""}); self.addCleanup(fake.close)
        proxy = self._proxy(fake, PRESERVE_REASONING=1)
        # an earlier text-only reply with the same (empty) text must not lend its reasoning to the cut turn
        proxy.chat({"model": MODEL, "messages": [{"role": "user", "content": "x"}], "tools": TOOLS})
        proxy.chat({"model": MODEL, "messages": self._cut_history(), "tools": TOOLS})
        sent = fake.requests[-1]["messages"][1]
        self.assertEqual(sent.get("reasoning_content"), "CUTREASON own thinking")
        self.assertNotIn("prism_cut_reasoning", json.dumps(fake.requests))
        self.assertEqual(self._wire()[-1]["preserve_reasoning"], {"reinserted": 0, "missing": 0, "cut_turns": 1, "cut_reinserted": 1})

    def test_cut_turn_reasoning_dropped_when_not_preserved(self):
        fake = FakeServer(lambda n, b: {"content": ""}); self.addCleanup(fake.close)
        proxy = self._proxy(fake)
        proxy.chat({"model": MODEL, "messages": self._cut_history(), "tools": TOOLS})
        self.assertNotIn("prism_cut_reasoning", json.dumps(fake.requests))
        self.assertNotIn("reasoning_content", fake.requests[-1]["messages"][1])


HERMES_VENV = os.environ.get("HERMES_VENV") or str(DEMO / ".venv-hermes")


@unittest.skipUnless(Path(HERMES_VENV, "bin", "python").exists(), "needs the patched Hermes venv (install_hermes.sh or HERMES_VENV)")
class GameRunTests(unittest.TestCase):
    """run_agent_demo.sh game neon-racer against the fake server, in a throwaway copy of the demo layout."""

    def setUp(self):
        # not under /private/var/ (the macOS temp dir), where Hermes's file tools refuse to write
        tmp = "/tmp" if os.path.realpath(tempfile.gettempdir()).startswith("/private/var/") else None
        self.root = Path(tempfile.mkdtemp(prefix="bonsai-game-test-", dir=tmp)); self.addCleanup(shutil.rmtree, self.root, True)
        self.demo = self.root / "demo"
        shutil.copytree(AGENT, self.demo / "scripts" / "agent", ignore=shutil.ignore_patterns("__pycache__"))
        (self.demo / "demos" / "games" / "neon-racer").mkdir(parents=True)
        shutil.copy2(DEMO / "demos" / "games" / "neon-racer" / "prompt.md", self.demo / "demos" / "games" / "neon-racer")
        (self.demo / ".venv-hermes").symlink_to(Path(HERMES_VENV).resolve())

    def run_game(self, script, **env):
        fake = FakeServer(script, delay_first=6); self.addCleanup(fake.close)
        e = {k: v for k, v in os.environ.items() if not k.startswith(("AGENT_", "HERMES_"))}
        e.update(AGENT_UPSTREAM=f"127.0.0.1:{fake.port}", AGENT_WORKSPACE_ROOT=str(self.root / "ws"), **env)
        out = subprocess.run(["bash", str(self.demo / "scripts/agent/run_agent_demo.sh"), "game", "neon-racer", "t1"],
                             env=e, capture_output=True, text=True, timeout=120)
        self.assertEqual(out.returncode, 0, out.stdout + out.stderr)
        run = self.demo / "agent-runs" / "t1"
        pid = int((run / "hermes.pid").read_text())
        for _ in range(600):
            try:
                os.kill(pid, 0); time.sleep(0.2)
            except ProcessLookupError:
                break
        else:
            os.kill(pid, 15); self.fail("Hermes did not finish")
        time.sleep(0.5)
        return fake, run

    @staticmethod
    def _jsonl(p):
        return [json.loads(l) for l in p.read_text().splitlines()] if p.exists() else []

    def check_game_settings(self, fake, run):
        cfg = (run / "home" / "config.yaml").read_text()
        self.assertIn("  max_tokens: 49152\n", cfg); self.assertIn("  threshold: 0.93907518\n", cfg)
        self.assertRegex(cfg, r"\n  max_turns: 150\b")
        self.assertTrue(all(r.get("max_tokens") == 49152 for r in fake.agent_requests()))

    def test_empty_reply_resample_differs(self):
        fake, run = self.run_game(seeded_script)
        self.check_game_settings(fake, run)
        rec = self._jsonl(run / "empty_recovery.jsonl")
        self.assertEqual([r["kind"] for r in rec], ["resample"], rec)
        self.assertEqual([r.get("seed") for r in fake.agent_requests()], [42, 42, 43])
        wire = [w for w in self._jsonl(run / "wire.jsonl") if w["has_tools"]]
        self.assertEqual([w["resample"] for w in wire], [None, None, 1])  # only Hermes's resample is marked
        self.assertTrue(all("x-agent-resample" not in h for h in fake.headers))  # and the marker is not forwarded
        self.assertIn("done.", (run / "stdout.log").read_text())
        self.assertEqual((run / "workspace" / "racer.html").read_text(), "<html>ok</html>\n")

    def test_empty_reply_resample_with_reseed_off_repeats(self):
        fake, run = self.run_game(seeded_script, AGENT_RESEED="0")
        rec = self._jsonl(run / "empty_recovery.jsonl")
        self.assertEqual([r["kind"] for r in rec], ["resample", "resample", "nudge", "exhausted"], rec)
        self.assertEqual({r.get("seed") for r in fake.agent_requests()}, {42})

    def test_cut_tool_call_gets_the_note(self):
        fake, run = self.run_game(cut_script)
        self.check_game_settings(fake, run)
        reqs = fake.agent_requests()
        self.assertGreaterEqual(len(reqs), 3)
        msgs = reqs[1]["messages"]
        self.assertEqual(len(msgs), len(reqs[0]["messages"]) + 2)  # not an identical resend
        self.assertEqual(msgs[-1]["role"], "user")
        self.assertTrue(msgs[-1]["content"].startswith("[System: Your previous tool call (write_file, target racer.html) was cut off"))
        self.assertEqual(msgs[-2]["role"], "assistant"); self.assertFalse(msgs[-2].get("tool_calls"))
        self.assertTrue(msgs[-2].get("reasoning_content", "").startswith("CUTREASON"))  # kept: reasoning preserved in game mode
        wire = json.dumps(reqs)
        self.assertNotIn("prism_cut_reasoning", wire); self.assertNotIn(PARTIAL[:60], wire)
        self.assertEqual([r["event"] for r in self._jsonl(run / "cut_recovery.jsonl")], ["fired"])
        self.assertEqual((run / "workspace" / "racer.html").read_text(), "PART1\n")


if __name__ == "__main__":
    unittest.main(verbosity=2)
