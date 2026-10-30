"""Exercise the launcher preset without models, Open WebUI, or live services."""

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PRESET = ROOT / "scripts" / "openwebui" / "mcp_servers.sh"


def load_connections(env=None, key_file=None, bridge=False):
    with tempfile.TemporaryDirectory() as directory:
        demo = Path(directory)
        if key_file is not None:
            (demo / ".brave_key").write_text(key_file)
        if bridge:
            executable = demo / "brave-search-mcp-server"
            executable.write_text("#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$DEMO_DIR/bridge-args\"\n")
            executable.chmod(0o755)
        clean_env = {
            k: v for k, v in os.environ.items()
            if k not in ("BRAVE_API_KEY", "BONSAI_WEB_SEARCH", "BONSAI_BRAVE_TOOLS")
        }
        clean_env.update({
            "DEMO_DIR": directory, "_BRAVE_LOG": str(demo / "brave.log"),
            "BG_PIDS": "", "PATH": directory + os.pathsep + os.environ["PATH"],
        })
        clean_env.update(env or {})
        result = subprocess.run(
            ["sh", "-c", """
                step() { :; }
                warn() { echo "$*" >&2; }
                err() { echo "$*" >&2; }
                . "$1"
                printf '%s\n' "$TOOL_SERVER_CONNECTIONS"
                wait
            """, "preset-test", str(PRESET)],
            env=clean_env, capture_output=True, text=True, check=False,
        )
        args = (demo / "bridge-args").read_text() if (demo / "bridge-args").exists() else None
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

    def test_invalid_provider_is_actionable_and_fails_before_connecting(self):
        result, args = load_connections({"BONSAI_WEB_SEARCH": "typo"})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Valid values: auto, parallel, brave, none", result.stderr)
        self.assertIsNone(args)


if __name__ == "__main__":
    unittest.main()
