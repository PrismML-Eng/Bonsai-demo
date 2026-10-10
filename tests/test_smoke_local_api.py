"""Deterministic tests; no model, GPU, or network is required."""
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from urllib.error import HTTPError
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
    def test_http_error_body_status_and_timing_are_reported(self):
        client = smoke.Client('http://localhost', 'missing', 'medium', 1, key='secret')
        error = HTTPError('http://localhost/v1/chat/completions', 400,
                          'Bad Request', {}, io.BytesIO(b'{"error":"model ID not found"}'))
        with patch.object(smoke, 'urlopen', side_effect=error):
            report = smoke.run(client, ['text'], 8000)
        self.assertFalse(report['passed'])
        self.assertIn('model ID not found', report['results'][0]['error'])
        call, = report['requests']
        self.assertEqual(call['status'], 400)
        self.assertEqual(call['path'], '/v1/chat/completions')
        self.assertEqual(call['error_body'], '{"error":"model ID not found"}')
        self.assertFalse(call['success'])
        self.assertGreaterEqual(call['seconds'], 0)
        self.assertNotIn('secret', json.dumps(report))

    def test_non_json_http_error_and_tokenize_request_are_recorded(self):
        client = smoke.Client('http://localhost', 'test', 'medium', 1)
        error = HTTPError('http://localhost/tokenize', 503, 'Unavailable', {},
                          io.BytesIO(b'server unavailable: \xff'))
        with patch.object(smoke, 'urlopen', side_effect=error):
            report = smoke.run(client, ['context'], 512)
        self.assertFalse(report['passed'])
        self.assertEqual(report['requests'][0]['path'], '/tokenize')
        self.assertEqual(report['requests'][0]['status'], 503)
        self.assertIn('server unavailable', report['requests'][0]['error_body'])

    def test_successful_http_request_retains_usage_and_timing(self):
        client = smoke.Client('http://localhost', 'test', 'medium', 1)
        data = {'choices': [{'finish_reason': 'stop', 'message': {'content': 'hello'}}],
                'usage': {'completion_tokens': 1}, 'timings': {'predicted_ms': 12}}
        response = io.BytesIO(json.dumps(data).encode())
        response.status = 200
        with patch.object(smoke, 'urlopen', return_value=response):
            report = smoke.run(client, ['text'], 8000)
        self.assertTrue(report['passed'])
        call, = report['requests']
        self.assertEqual(call['status'], 200)
        self.assertTrue(call['success'])
        self.assertEqual(call['usage'], data['usage'])
        self.assertEqual(call['timings'], data['timings'])
        self.assertEqual(call['finish_reason'], 'stop')
        self.assertGreaterEqual(call['seconds'], 0)

    def test_transport_failure_records_timing_without_http_status(self):
        client = smoke.Client('http://localhost', 'test', 'medium', 1)
        with patch.object(smoke, 'urlopen', side_effect=TimeoutError('request timed out')):
            report = smoke.run(client, ['text'], 8000)
        call, = report['requests']
        self.assertFalse(call['success'])
        self.assertIsNone(call['status'])
        self.assertGreaterEqual(call['seconds'], 0)
        self.assertIn('timed out', call['error'])

    def test_failed_context_check_preserves_actual_answer(self):
        for answer in ('WRONG-CODE', '', None):
            with self.subTest(answer=answer):
                client = FakeClient([{'content': answer}])
                with patch.object(client, 'post', return_value={'tokens': [1] * 10}, create=True):
                    report = smoke.run(client, ['context'], 512)
                result, = report['results']
                self.assertFalse(result['passed'])
                self.assertEqual(result['answer'], answer)
                self.assertEqual(result['document_tokens'], 10)

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
