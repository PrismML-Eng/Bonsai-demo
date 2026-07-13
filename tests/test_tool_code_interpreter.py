import importlib.util
import asyncio
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TOOL_PATH = ROOT / "scripts" / "openwebui" / "tool_code_interpreter.py"
SPEC = importlib.util.spec_from_file_location("tool_code_interpreter", TOOL_PATH)
code_tool = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(code_tool)


class CodeInterpreterResultTests(unittest.TestCase):
    def test_progress_only_stderr_is_clean_success(self):
        result = code_tool._normalize_execution(
            "value=42",
            "[*********************100%***********************]  1 of 1 completed",
            "",
        )

        self.assertEqual(result, {"status": "success", "stdout": "value=42"})

    def test_traceback_without_result_is_compact_error(self):
        stderr = (
            "\x1b[31mTraceback (most recent call last):\x1b[39m\n"
            "  File \"cell.py\", line 2\n"
            "TypeError: unsupported format string passed to Series.__format__"
        )
        result = code_tool._normalize_execution("heading", stderr, "")

        self.assertEqual(result["status"], "error")
        self.assertEqual(
            result["error"],
            "TypeError: unsupported format string passed to Series.__format__",
        )
        self.assertNotIn("instruction", result)
        self.assertIn("multi_level_index=False", result["suggested_fix"])
        self.assertIn("pandas Series", result["suggested_fix"])
        self.assertNotIn("Traceback", result["error"])

    def test_traceback_with_image_is_partial_success(self):
        result = code_tool._normalize_execution(
            "statistics printed",
            "Traceback (most recent call last):\nTypeError: optional tick formatting failed",
            "![Output Image](/api/v1/files/example/content)",
        )

        self.assertEqual(result["status"], "partial_success")
        self.assertNotIn("instruction", result)
        self.assertIn("![Output Image]", result["result"])

    def test_tool_description_is_generic_and_allows_api_discovery(self):
        description = code_tool.Tools.execute_code.__doc__

        self.assertIn("inspect.signature()", description)
        self.assertIn("discovery call", description)
        self.assertIn("only the latest plot attachment", description)
        self.assertIn("one final figure", description)
        self.assertIn("attached automatically", description)
        self.assertNotIn("yfinance", description)

    def test_generated_image_is_attached_with_native_compatible_file_event(self):
        events = []

        async def emitter(event):
            events.append(event)

        response = code_tool._normalize_execution(
            "done",
            "",
            "![Output Image](/api/v1/files/example/content)",
        )
        asyncio.run(code_tool._attach_artifacts(response, emitter))

        self.assertNotIn("result", response)
        self.assertEqual(response, {"status": "success", "stdout": "done"})
        self.assertEqual(events[0]["type"], "files")
        self.assertEqual(events[0]["data"]["files"][0]["id"], "example")
        self.assertEqual(
            events[0]["data"]["files"][0]["url"],
            "/api/v1/files/example/content",
        )

    def test_generated_image_has_model_fallback_without_event_emitter(self):
        response = code_tool._normalize_execution(
            "done",
            "",
            "![Output Image](/api/v1/files/example/content)",
        )
        asyncio.run(code_tool._attach_artifacts(response, None))

        self.assertEqual(
            response["result"],
            "![Output Image](/api/v1/files/example/content)",
        )
        self.assertNotIn("instruction", response)

    def test_non_image_result_is_preserved(self):
        response = code_tool._normalize_execution("", "", "42")
        asyncio.run(code_tool._attach_artifacts(response, None))

        self.assertEqual(response, {"status": "success", "result": "42"})

    def test_unrelated_error_does_not_receive_yfinance_advice(self):
        result = code_tool._normalize_execution(
            "",
            "Traceback (most recent call last):\nKeyError: missing column",
            "",
        )

        self.assertEqual(result["status"], "error")
        self.assertNotIn("suggested_fix", result)

    def test_nonfatal_warning_is_preserved_without_marking_failure(self):
        result = code_tool._normalize_execution(
            "done",
            "FutureWarning: a default will change in a future version",
            "",
        )

        self.assertEqual(result["status"], "success")
        self.assertIn("FutureWarning", result["warnings"])


if __name__ == "__main__":
    unittest.main()
