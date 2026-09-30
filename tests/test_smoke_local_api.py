"""Deterministic tests; no model, GPU, or network is required."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('smoke', Path(__file__).resolve().parents[1] / 'scripts/smoke_local_api.py')
smoke = importlib.util.module_from_spec(spec)
spec.loader.exec_module(smoke)


class FakeClient:
    model = 'test'
    effort = 'medium'

    def __init__(self, replies):
        self.replies = iter(replies)
        self.calls = []

    def chat(self, *args):
        value = next(self.replies)
        if isinstance(value, Exception):
            raise value
        return value


def tool(arguments='{"sku":"RTX5090"}'):
    return {'content': None, 'tool_calls': [{'id': 'call1', 'type': 'function',
            'function': {'name': 'lookup_inventory', 'arguments': arguments}}]}


class SmokeChecks(unittest.TestCase):
    def test_retry_and_final_result(self):
        client = FakeClient([tool(), tool(), {'content': '{"available":11}'}])
        self.assertEqual(smoke.tools_check(client)['tool_attempts'], 2)

    def test_no_tool_is_not_success(self):
        with self.assertRaisesRegex(ValueError, 'before completing'):
            smoke.tools_check(FakeClient([{'content': '{"available":11}'}]))

    def test_malformed_arguments(self):
        with self.assertRaises(json.JSONDecodeError):
            smoke.tools_check(FakeClient([tool('{bad')]))

    def test_wrong_sku(self):
        with self.assertRaisesRegex(ValueError, 'Unexpected tool'):
            smoke.tools_check(FakeClient([tool('{"sku":"other"}')]))

    def test_unbounded_loop_is_stopped(self):
        with self.assertRaisesRegex(ValueError, 'six model turns'):
            smoke.tools_check(FakeClient([tool()] * 6))

    def test_reasoning_only_is_failure(self):
        with self.assertRaisesRegex(ValueError, 'No final answer'):
            smoke.text_check(FakeClient([{'content': '', 'reasoning_content': 'thinking'}]))

    def test_timeout_is_recorded(self):
        report = smoke.run(FakeClient([TimeoutError('timeout')]), ['text'], 8000)
        self.assertFalse(report['passed'])
        self.assertIn('timeout', report['results'][0]['error'])

    def test_truncated_response_is_failure(self):
        client = smoke.Client('http://localhost', 'test', 'medium', 1)
        with patch.object(client, 'post', return_value={'choices': [{'finish_reason': 'length', 'message': {'content': 'hello'}}]}):
            with self.assertRaisesRegex(ValueError, 'did not finish'):
                client.chat([])

    def test_cli_exit_and_no_overwrite(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'report.json'
            with patch.object(smoke, 'Client', return_value=FakeClient([TimeoutError('timeout')])):
                self.assertEqual(smoke.main(['--model', 'test', '--cases', 'text', '--output', str(output)]), 1)
                saved = output.read_bytes()
                with self.assertRaises(FileExistsError):
                    smoke.main(['--model', 'test', '--output', str(output)])
                self.assertEqual(output.read_bytes(), saved)


if __name__ == '__main__':
    unittest.main()
