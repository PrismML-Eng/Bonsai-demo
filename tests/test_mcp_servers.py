"""Exercise the launcher preset without models, Open WebUI, or live services."""

import json
import os
import shutil
import signal
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
PRESET = ROOT / "scripts" / "openwebui" / "mcp_servers.sh"
# External commands the preset calls, symlinked into the sandbox below.
PRESET_COMMANDS = ("tr",)
TIMEOUT = 30


def isolated_path(demo):
    """PATH holding only the fixtures and the commands the preset needs.

    The host PATH is deliberately excluded: a bridge installed on the machine
    running the tests would otherwise be found, started, and waited on.
    """
    commands = demo / "commands"
    commands.mkdir()
    for name in PRESET_COMMANDS:
        found = shutil.which(name)
        if found is None:
            raise AssertionError(f"the preset needs {name!r}, which is not installed")
        (commands / name).symlink_to(found)
    return os.pathsep.join([str(demo), str(commands)])


def run_preset(env):
    """Run the preset in its own process group so nothing can outlive the test."""
    process = subprocess.Popen(
        [shutil.which("sh") or "/bin/sh", "-c", """
            step() { :; }
            warn() { echo "$*" >&2; }
            err() { echo "$*" >&2; }
            . "$1"
            printf '%s\n' "$BONSAI_WEB_SEARCH_NOTE" > "$DEMO_DIR/search-note"
            printf '%s\n' "$TOOL_SERVER_CONNECTIONS"
            wait
        """, "preset-test", str(PRESET)],
        env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        start_new_session=True,
    )
    try:
        stdout, stderr = process.communicate(timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.communicate()
        raise AssertionError(f"the preset did not finish within {TIMEOUT}s")
    return subprocess.CompletedProcess(process.args, process.returncode, stdout, stderr)


def load_connections(env=None, key_file=None, bridge=False):
    with tempfile.TemporaryDirectory() as directory:
        demo = Path(directory)
        if key_file is not None:
            (demo / ".brave_key").write_text(key_file)
        if bridge:
            executable = demo / "brave-search-mcp-server"
            executable.write_text("#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$DEMO_DIR/bridge-args\"\n")
            executable.chmod(0o755)
        result = run_preset({
            "DEMO_DIR": directory, "_BRAVE_LOG": str(demo / "brave.log"),
            "BG_PIDS": "", "PATH": isolated_path(demo),
            **(env or {}),
        })
        args = (demo / "bridge-args").read_text() if (demo / "bridge-args").exists() else None
        note = demo / "search-note"
        result.search_note = note.read_text().strip() if note.exists() else ""
        return result, args


class MCPServersTests(unittest.TestCase):
    def test_unconfigured_search_is_keyless_parallel(self):
        result, args = load_connections()
        self.assertEqual(result.returncode, 0, result.stderr)
        servers = json.loads(result.stdout)
        self.assertEqual([s["id"] for s in servers], ["huggingface", "deepwiki", "parallel"])
        search = servers[-1]
        self.assertEqual(search["url"], "https://search.parallel.ai/mcp")
        self.assertEqual(search["headers"], {"User-Agent": "BonsaiDemo/0.1.0"})
        self.assertEqual(search["auth_type"], "none")
        self.assertEqual(search["key"], "")
        self.assertNotIn("session_id", result.stdout)
        self.assertIsNone(args)
        # The banner has to name the destination and the way out.
        self.assertIn("parallel.ai", result.search_note)
        self.assertIn("BONSAI_WEB_SEARCH=none", result.search_note)

    def test_configured_brave_and_custom_tools_keep_the_bridge(self):
        result, args = load_connections(
            {"BRAVE_API_KEY": "fixture-key", "BONSAI_BRAVE_TOOLS": "brave_news_search"},
            bridge=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([s["id"] for s in json.loads(result.stdout)], ["huggingface", "deepwiki", "brave"])
        self.assertIn("--enabled-tools\nbrave_news_search\n", args)
        self.assertNotIn("fixture-key", result.stdout)

    def test_key_file_keeps_brave_without_falling_back_if_bridge_is_missing(self):
        result, args = load_connections(key_file="fixture-key\r\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([s["id"] for s in json.loads(result.stdout)], ["huggingface", "deepwiki"])
        self.assertIn("skipping Brave MCP", result.stderr)
        self.assertIsNone(args)

    def test_a_bridge_on_the_host_path_is_neither_found_nor_started(self):
        # The "bridge missing" cases must stay missing on a machine that has a
        # real bridge installed: finding one starts it, and the preset waits.
        with tempfile.TemporaryDirectory() as installed:
            decoy = Path(installed) / "brave-search-mcp-server"
            decoy.write_text("#!/bin/sh\nprintf 'started\\n' > \"$DEMO_DIR/bridge-args\"\nsleep 600\n")
            decoy.chmod(0o755)
            with mock.patch.dict(os.environ, {"PATH": installed + os.pathsep + os.environ["PATH"]}):
                result, args = load_connections(key_file="fixture-key\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([s["id"] for s in json.loads(result.stdout)], ["huggingface", "deepwiki"])
        self.assertIn("skipping Brave MCP", result.stderr)
        self.assertIsNone(args)

    def test_explicit_parallel_overrides_a_brave_key(self):
        result, args = load_connections(
            {"BRAVE_API_KEY": "fixture-key", "BONSAI_WEB_SEARCH": "parallel"}, bridge=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)[-1]["id"], "parallel")
        self.assertIsNone(args)

    def test_explicit_brave_without_key_does_not_fall_back(self):
        result, args = load_connections({"BONSAI_WEB_SEARCH": "brave"}, bridge=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([s["id"] for s in json.loads(result.stdout)], ["huggingface", "deepwiki"])
        self.assertIn("web search is unavailable", result.stderr)
        self.assertIsNone(args)

    def test_none_disables_search_even_with_brave_credentials(self):
        result, args = load_connections(
            {"BONSAI_WEB_SEARCH": "none", "BRAVE_API_KEY": "fixture-key"}, bridge=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([s["id"] for s in json.loads(result.stdout)], ["huggingface", "deepwiki"])
        self.assertIsNone(args)
        self.assertEqual(result.search_note, "off (BONSAI_WEB_SEARCH=none).")

    def test_invalid_provider_is_actionable_and_fails_before_connecting(self):
        result, args = load_connections({"BONSAI_WEB_SEARCH": "typo"})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Valid values: auto, parallel, brave, none", result.stderr)
        self.assertIsNone(args)


if __name__ == "__main__":
    unittest.main()
