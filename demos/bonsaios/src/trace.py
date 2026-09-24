"""Lossless SSE capture plus readable Bonsai reasoning, content, and tool fragments."""
import json
from pathlib import Path
import time


class StreamTrace:
    def __init__(self, prefix):
        self.prefix = Path(prefix)
        self.raw = self.prefix.with_suffix('.sse').open('wb')
        self.events = self.prefix.with_suffix('.events.jsonl').open('w')
        self.reasoning = self.prefix.with_suffix('.reasoning.txt').open('w')
        self.content = self.prefix.with_suffix('.content.txt').open('w')
        self.buffer = b''
        self.started = time.monotonic()
        self.message = {'role': 'assistant', 'content': '', 'reasoning_content': ''}
        self.calls = {}
        self.usage = {}
        self.finish_reason = None
        self.done = False
        self.completion_id = None
        self.count = 0
        self.first_reasoning_seconds = None
        self.first_content_seconds = None
        self.first_tool_seconds = None
        self.timings = None

    def feed(self, data):
        self.raw.write(data)
        self.raw.flush()
        self.buffer += data
        while b'\n' in self.buffer:
            line, self.buffer = self.buffer.split(b'\n', 1)
            if not line.startswith(b'data:'):
                continue
            payload = line[5:].strip()
            if payload == b'[DONE]':
                self.done = True
                continue
            if not payload:
                continue
            event = json.loads(payload)
            elapsed = time.monotonic() - self.started
            self.count += 1
            self.events.write(json.dumps({'elapsed_seconds': elapsed, 'event': event}) + '\n')
            self.events.flush()
            self.completion_id = event.get('id', self.completion_id)
            if event.get('usage'):
                self.usage = event['usage']
            if event.get('timings'):
                self.timings = event['timings']
            for choice in event.get('choices', []):
                if choice.get('index', 0) != 0:
                    continue
                delta = choice.get('delta') or {}
                for key, output, stamp in [('reasoning_content', self.reasoning, 'first_reasoning_seconds'),
                                           ('content', self.content, 'first_content_seconds')]:
                    value = delta.get(key) or ''
                    if value:
                        self.message[key] += value
                        output.write(value)
                        output.flush()
                        if getattr(self, stamp) is None:
                            setattr(self, stamp, elapsed)
                for fragment in delta.get('tool_calls') or []:
                    if self.first_tool_seconds is None:
                        self.first_tool_seconds = elapsed
                    index = fragment.get('index', 0)
                    call = self.calls.setdefault(index, {'type': 'function', 'function': {'name': '', 'arguments': ''}})
                    if fragment.get('id'):
                        call['id'] = fragment['id']
                    for key in ['name', 'arguments']:
                        call['function'][key] += (fragment.get('function') or {}).get(key, '')
                if choice.get('finish_reason'):
                    self.finish_reason = choice['finish_reason']

    def snapshot(self):
        message = dict(self.message)
        if self.calls:
            message['tool_calls'] = [self.calls[k] for k in sorted(self.calls)]
        return {'id': self.completion_id, 'object': 'chat.completion',
                'choices': [{'index': 0, 'message': message, 'finish_reason': self.finish_reason}],
                'usage': self.usage, 'timings': self.timings}

    def metrics(self):
        return {'sse_events': self.count, 'stream_complete': self.done,
                'reasoning_characters': len(self.message['reasoning_content']),
                'content_characters': len(self.message['content']),
                'tool_argument_characters': sum(len(c['function']['arguments']) for c in self.calls.values()),
                'first_reasoning_seconds': self.first_reasoning_seconds,
                'first_content_seconds': self.first_content_seconds,
                'first_tool_seconds': self.first_tool_seconds}

    def close(self):
        for file in [self.raw, self.events, self.reasoning, self.content]:
            file.close()
