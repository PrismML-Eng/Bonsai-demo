import importlib.util
import os
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
SEED_PATH = ROOT / "scripts" / "openwebui" / "seed_openwebui.py"


def _load_seed_module():
    spec = importlib.util.spec_from_file_location("seed_openwebui_test", SEED_PATH)
    module = importlib.util.module_from_spec(spec)
    with mock.patch.dict(os.environ, {"BONSAI_CODE_INTERPRETER_ON": "1"}):
        spec.loader.exec_module(module)
    return module


class _ApiRecorder:
    def __init__(self):
        self.calls = []

    def request(self, method, path, payload=None, timeout=15):
        self.calls.append((method, path, payload))
        return {}


class SeedOpenWebUITests(unittest.TestCase):
    def test_model_disables_openwebui_citation_rewrite(self):
        seed = _load_seed_module()
        api = _ApiRecorder()

        seed.seed_model(
            api,
            "Ternary-Bonsai-27B-Q2_0.gguf",
            vision=True,
            native_tools=True,
            backend="llama.cpp",
        )

        payload = next(
            payload
            for method, path, payload in api.calls
            if method == "POST" and path.startswith("/api/v1/models/model/update")
        )
        self.assertIs(payload["meta"]["capabilities"]["citations"], False)

    def test_prompt_is_generic_bounded_and_date_aware(self):
        seed = _load_seed_module()
        prompt = seed.SYSTEM_PROMPT

        self.assertIn("{{CURRENT_DATE}}", prompt)
        self.assertIn("inside Open WebUI", prompt)
        self.assertIn("Respect requested date ranges", prompt)
        self.assertIn("exclusive end dates", prompt)
        self.assertIn("Plan enough to verify the answer", prompt)
        self.assertIn("later events cannot be its cause", prompt)
        self.assertIn("only when the user explicitly requests Python or a chart", prompt)
        self.assertIn("Never create a plot unless explicitly requested", prompt)
        self.assertIn("okay to inspect its help or signature", prompt)
        self.assertIn("never repeat unchanged failing code", prompt)
        self.assertIn("attaches plots displayed by execute_code", prompt)
        self.assertIn("never copy, invent, or modify internal", prompt)
        self.assertIn("without a references section", prompt)
        self.assertNotIn("yfinance", prompt)
        self.assertNotIn("![Output Image]", prompt)
        self.assertNotIn("January 1, 2026", prompt)
        self.assertNotIn("Cite each source", prompt)
        self.assertNotIn("[Title](URL)", prompt)

    def test_repo_owned_code_tool_is_attached_when_jupyter_is_on(self):
        seed = _load_seed_module()

        self.assertIn("python_code", seed.TOOL_IDS)
        tool = next(item for item in seed.TOOLS if item[0] == "python_code")
        self.assertEqual(tool[2], "tool_code_interpreter.py")

    def test_27b_uses_precise_thinking_sampling(self):
        seed = _load_seed_module()

        params = seed._model_params("Ternary-Bonsai-27B-Q2_0.gguf")

        self.assertEqual(params["temperature"], 0.6)
        self.assertEqual(params["top_p"], 0.95)
        self.assertEqual(params["top_k"], 20)


if __name__ == "__main__":
    unittest.main()
