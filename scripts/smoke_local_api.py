#!/usr/bin/env python3
"""Opt-in smoke checks against an already running local inference server."""
import argparse
import json
import os
from pathlib import Path
import time
from urllib.request import Request, urlopen


class Client:
    def __init__(self, base_url, model, effort, timeout, key=None):
        self.base_url = base_url.rstrip('/')
        self.model = model
        self.effort = effort
        self.timeout = timeout
        self.key = key
        self.calls = []

    def post(self, path, body):
        headers = {'Content-Type': 'application/json'}
        if self.key:
            headers['Authorization'] = 'Bearer ' + self.key
        request = Request(self.base_url + path, json.dumps(body).encode(), headers)
        with urlopen(request, timeout=self.timeout) as response:
            return json.load(response)

    def chat(self, messages, tools=None):
        body = dict(model=self.model, messages=messages, stream=False,
                    reasoning_effort=self.effort, max_tokens=16384, seed=42,
                    temperature=1.0, top_p=0.95, top_k=20, min_p=0.05,
                    presence_penalty=0.0, repeat_penalty=1.0)
        if tools:
            body['tools'] = tools
        start = time.monotonic()
        response = self.post('/v1/chat/completions', body)
        choice = response['choices'][0]
        self.calls.append({'seconds': time.monotonic() - start,
                           'usage': response.get('usage'),
                           'timings': response.get('timings'),
                           'finish_reason': choice.get('finish_reason')})
        if choice.get('finish_reason') not in ('stop', 'tool_calls'):
            raise ValueError('Response did not finish: ' + str(choice.get('finish_reason')))
        return choice['message']


def messages(prompt):
    return [{'role': 'system', 'content': 'You are a helpful assistant.'},
            {'role': 'user', 'content': prompt}]


def text_check(client):
    message = client.chat(messages('Reply with a short greeting.'))
    if not (message.get('content') or '').strip():
        raise ValueError('No final answer (a reasoning-only response is not success)')
    return {'answer': message['content']}


def tools_check(client):
    schema = [{'type': 'function', 'function': {
        'name': 'lookup_inventory', 'description': 'Read current inventory; retry transient errors.',
        'parameters': {'type': 'object', 'properties': {'sku': {'type': 'string'}},
                       'required': ['sku'], 'additionalProperties': False}}}]
    history = messages('Use lookup_inventory for SKU RTX5090. Retry temporary errors. '
                       'Subtract reserved from stock. Return only JSON {"available": number}.')
    attempts = 0
    for _ in range(6):
        message = client.chat(history, schema)
        calls = message.get('tool_calls') or []
        if not calls:
            if attempts < 2:
                raise ValueError('Model stopped before completing the tool retry')
            answer = json.loads(message.get('content') or '')
            if answer != {'available': 11}:
                raise ValueError('Incorrect answer after tool result: ' + str(answer))
            return {'answer': answer, 'tool_attempts': attempts}
        if len(calls) != 1:
            raise ValueError('Expected one inventory call per turn')
        call = calls[0]
        if (call['function']['name'] != 'lookup_inventory' or
                json.loads(call['function']['arguments']) != {'sku': 'RTX5090'}):
            raise ValueError('Unexpected tool name or arguments')
        attempts += 1
        result = ({'error': 'temporary_unavailable', 'retryable': True}
                  if attempts == 1 else {'stock': 17, 'reserved': 6})
        # Do not replay reasoning_content as conversation history.
        history.append({'role': 'assistant', 'content': message.get('content'), 'tool_calls': calls})
        history.append({'role': 'tool', 'tool_call_id': call['id'], 'content': json.dumps(result)})
    raise ValueError('Tool loop exceeded six model turns')


def context_check(client, target):
    if not 512 <= target <= 48000:
        raise ValueError('context-tokens must be between 512 and 48000')
    def document(n):
        lines = [f'Record {i}: status archived, count {i % 97}.\n' for i in range(n)]
        lines[n // 2] = 'Record TARGET: code Q7M4-Z9K2.\n'
        return ''.join(lines)
    lo, hi = 1, target
    while lo + 1 < hi:
        mid = (lo + hi) // 2
        count = len(client.post('/tokenize', {'content': document(mid)})['tokens'])
        if count <= target:
            lo = mid
        else:
            hi = mid
    doc = document(lo)
    count = len(client.post('/tokenize', {'content': doc})['tokens'])
    answer = client.chat(messages(doc + '\nReturn only the code from Record TARGET.'))
    if (answer.get('content') or '').strip() != 'Q7M4-Z9K2':
        raise ValueError('Target code was not retrieved exactly')
    return {'document_tokens': count, 'answer': answer['content']}


def run(client, cases, context_tokens):
    results = []
    for case in cases:
        start = time.monotonic()
        try:
            detail = (context_check(client, context_tokens) if case == 'context'
                      else {'text': text_check, 'tools': tools_check}[case](client))
            result = {'case': case, 'passed': True, **detail}
        except Exception as error:
            result = {'case': case, 'passed': False, 'error': str(error)}
        result['seconds'] = time.monotonic() - start
        results.append(result)
    return {'model': client.model, 'reasoning_effort': client.effort,
            'results': results, 'requests': client.calls,
            'passed': all(item['passed'] for item in results)}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base-url', default='http://127.0.0.1:8080', help='Server root, without /v1')
    parser.add_argument('--model', required=True)
    parser.add_argument('--reasoning-effort', choices=['medium', 'xhigh'], default='medium')
    parser.add_argument('--timeout', type=float, default=300)
    parser.add_argument('--api-key-env', default='BONSAI_API_KEY')
    parser.add_argument('--cases', nargs='+', choices=['text', 'tools', 'context'], default=['text', 'tools'])
    parser.add_argument('--context-tokens', type=int, default=8000)
    parser.add_argument('--output', type=Path, required=True, help='New JSON report; existing files are refused')
    args = parser.parse_args(argv)
    if args.timeout <= 0 or not 512 <= args.context_tokens <= 48000:
        parser.error('Use a positive timeout and 512 <= context-tokens <= 48000')
    client = Client(args.base_url, args.model, args.reasoning_effort, args.timeout,
                    os.environ.get(args.api_key_env))
    # Open before inference so an accidental rerun never overwrites evidence.
    with args.output.open('x', encoding='utf-8') as output:
        report = run(client, args.cases, args.context_tokens)
        json.dump(report, output, ensure_ascii=False, indent=2)
        output.write('\n')
    print(json.dumps({'passed': report['passed'], 'output': str(args.output)}))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
