"""Lightweight runner regressions; no Hermes, network, or model required.

Run: python3 scripts/agent/test_runner_safety.py
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parent


class RunnerSafetyTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="bonsai-runner-test-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.demo = self.root / "demo"
        self.agent = self.demo / "scripts" / "agent"
        self.agent.mkdir(parents=True)
        for name in ("run_agent_demo.sh", "hermes-config-round0.yaml", "hermes-config-feedback.yaml"):
            shutil.copy2(SOURCE / name, self.agent / name)
        venv = self.demo / ".venv-hermes" / "bin"
        venv.mkdir(parents=True)
        (venv / "python").symlink_to(sys.executable)
        self.task = self.root / "task.md"
        self.task.write_text("Test task")
        self.workspace = self.root / "workspaces"
        self.fake = self.root / "bin"
        self.fake.mkdir()
        curl = self.fake / "curl"
        curl.write_text("#!" + sys.executable + "\n" + '''
import json, os, pathlib, sys
if os.environ.get("TEST_RACE"):
    target = pathlib.Path(os.environ["AGENT_WORKSPACE_ROOT"]) / "test-run"
    target.mkdir(parents=True, exist_ok=True)
    (target / "sentinel").write_text("keep")
print(json.dumps({"data": [{"id": "test-model"}]} if sys.argv[-1].endswith("/v1/models") else
    {"default_generation_settings": {"n_ctx": 131072, "params": {"seed": 42}}, "total_slots": 1}))
''')
        curl.chmod(0o755)
        self.env = {k: v for k, v in os.environ.items() if not k.startswith("AGENT_")}
        self.env.update(PATH=str(self.fake) + os.pathsep + os.environ["PATH"],
                        AGENT_WORKSPACE_ROOT=str(self.workspace), AGENT_TRACE="0", AGENT_SEED="42")

    def run_task(self, task=None, mode_args=None):
        return subprocess.run(
            ["bash", str(self.agent / "run_agent_demo.sh"),
             *(mode_args or ["task", str(task or self.task), "test-run"])],
            env=self.env, capture_output=True, text=True, timeout=10)

    def test_existing_workspace_is_preserved(self):
        old = self.workspace / "test-run"
        old.mkdir(parents=True)
        (old / "sentinel").write_text("keep")
        result = self.run_task()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((old / "sentinel").read_text(), "keep")
        self.assertFalse((self.demo / "agent-runs").exists())

    def test_dangling_workspace_symlink_is_preserved(self):
        self.workspace.mkdir()
        old = self.workspace / "test-run"
        old.symlink_to(self.root / "absent", target_is_directory=True)
        result = self.run_task()
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(old.is_symlink())

    def test_missing_task_leaves_no_run_state(self):
        result = self.run_task(self.root / "missing.md")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("task is not a readable file", result.stdout)
        self.assertFalse((self.demo / "agent-runs").exists())
        self.assertFalse(self.workspace.exists())

    def test_missing_feedback_workspace_leaves_no_run_state(self):
        result = self.run_task(mode_args=["feedback", str(self.root / "missing-run"),
                                          str(self.task), "test-run"])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("previous workspace is missing", result.stdout)
        self.assertFalse((self.demo / "agent-runs").exists())

    def test_relative_workspace_root_is_rejected_before_creation(self):
        self.env["AGENT_WORKSPACE_ROOT"] = "relative-workspace"
        result = self.run_task()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("must be an absolute path", result.stdout)
        self.assertFalse((self.demo / "agent-runs").exists())

    def test_workspace_created_after_precheck_is_preserved(self):
        self.env["TEST_RACE"] = "1"
        result = self.run_task()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.workspace / "test-run" / "sentinel").read_text(), "keep")
        self.assertFalse((self.demo / "agent-runs" / "test-run").exists())

    def test_existing_custom_home_is_preserved(self):
        home_root = self.root / "homes"
        home = home_root / "test-run" / "home"
        home.mkdir(parents=True)
        (home / "config.yaml").write_text("keep")
        self.env["AGENT_HOME_ROOT"] = str(home_root)
        result = self.run_task()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((home / "config.yaml").read_text(), "keep")
        self.assertFalse(self.workspace.exists())

    def test_fresh_workspace_with_spaces_reaches_mock_launch(self):
        self.env["AGENT_WORKSPACE_ROOT"] = str(self.root / "workspace with spaces")
        # Stand in for the detach helper; do not execute Hermes or create a daemon.
        (self.agent / "daemonize.py").write_text(
            "import os, pathlib, sys\npathlib.Path(sys.argv[1]).write_text(str(os.getppid()))\n")
        sleep = self.fake / "sleep"
        sleep.write_text("#!/bin/sh\nexit 0\n")
        sleep.chmod(0o755)
        result = self.run_task()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        workspace = self.demo / "agent-runs" / "test-run" / "workspace"
        self.assertTrue(workspace.is_symlink())
        self.assertEqual((workspace / "TASK.md").read_text(), "Test task")

    def test_failed_launch_removes_everything_it_created(self):
        # daemonize stub records a pid that is not running: the startup check must fail and clean up
        home_root = self.root / "homes"
        self.env["AGENT_HOME_ROOT"] = str(home_root)
        (self.agent / "daemonize.py").write_text(
            "import pathlib, sys\npathlib.Path(sys.argv[1]).write_text('999999')\n")
        sleep = self.fake / "sleep"
        sleep.write_text("#!/bin/sh\nexit 0\n")
        sleep.chmod(0o755)
        result = self.run_task()
        self.assertEqual(result.returncode, 4, result.stdout + result.stderr)
        self.assertIn("did not start", result.stderr)
        self.assertFalse((self.demo / "agent-runs" / "test-run").exists())
        self.assertFalse((self.workspace / "test-run").exists())
        self.assertFalse((home_root / "test-run").exists())

    def test_trace_injection_uses_runner_values(self):
        # Execute the actual JSON-building assignment without starting the proxy.
        source = (self.agent / "run_agent_demo.sh").read_text()
        assignment = source[source.index("  INJECT=$("):source.index('\n  SEED="$SEED" EFFORT=')]
        env = dict(self.env)
        env.pop("SEED", None)
        env.pop("EFFORT", None)
        for values, expected in [
            ("SEED=42; EFFORT=medium", {"seed": 42, "chat_template_kwargs": {"reasoning_effort": "medium"}}),
            ("SEED=; EFFORT=", {}),
        ]:
            with self.subTest(values=values):
                result = subprocess.run(["bash", "-c", values + "\n" + assignment + '\nprintf "%s\\n" "$INJECT"'],
                                        env=env, capture_output=True, text=True, check=True)
                self.assertEqual(json.loads(result.stdout), expected)


if __name__ == "__main__":
    unittest.main()
