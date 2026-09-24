"""Reproduce one IMO 2026 attempt with the exact settings used for the published solutions.

Starts a local llama-server from the Prism llama.cpp release, checks that the thinking
budget is enforced, sends the problem, and streams the thinking and final answer to disk.

    python3 run_problem.py --model bonsai --problem 1 \
        --server ./llama-prism-b10709-9a9394a/llama-server \
        --model-file ./Ternary-Bonsai-2-27B-PQ2_0.gguf
"""
import argparse
import json
import pathlib
import subprocess
import time
import urllib.error
import urllib.request

HERE = pathlib.Path(__file__).resolve().parent

THINKING_BUDGET = 131072
MAX_TOKENS = 147456  # thinking budget + 16,384 for the final answer
CONTEXT = 196608

# Bonsai and Qwen use their native "xhigh" reasoning effort; Gemma has no effort levels,
# so only native thinking is enabled.
TEMPLATE_KWARGS = {
    'bonsai': {'reasoning_effort': 'xhigh', 'enable_thinking': True},
    'qwen': {'reasoning_effort': 'xhigh', 'enable_thinking': True},
    'gemma': {'enable_thinking': True},
}


def save(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--model', required=True, choices=sorted(TEMPLATE_KWARGS))
    parser.add_argument('--problem', type=int, required=True, choices=range(1, 7))
    parser.add_argument('--server', required=True, help='path to llama-server')
    parser.add_argument('--model-file', required=True, help='path to the .gguf weights')
    parser.add_argument('--port', type=int, default=8080)
    parser.add_argument('--out', default='results')
    args = parser.parse_args()

    problem = json.loads((HERE / 'problems.json').read_text())['problems'][args.problem - 1]
    out = pathlib.Path(args.out) / args.model / f'p{args.problem}'
    out.mkdir(parents=True, exist_ok=False)
    base = f'http://127.0.0.1:{args.port}'
    kwargs = TEMPLATE_KWARGS[args.model]

    def post(endpoint, payload):
        request = urllib.request.Request(base + endpoint, json.dumps(payload).encode(),
                                         {'Content-Type': 'application/json'})
        return urllib.request.urlopen(request, timeout=7200)

    command = [args.server, '-m', args.model_file, '-ngl', '99', '-fa', 'on',
               '-c', str(CONTEXT), '-np', '1', '-t', '6', '-tb', '6',
               '--host', '127.0.0.1', '--port', str(args.port),
               '--jinja', '--reasoning-format', 'deepseek', '--no-context-shift',
               '-ctk', 'f16', '-ctv', 'f16', '--chat-template-kwargs', json.dumps(kwargs)]

    with (out / 'server.log').open('w') as log:
        server = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
        try:
            for _ in range(300):
                if server.poll() is not None:
                    raise RuntimeError('Server exited while loading; see server.log')
                try:
                    with urllib.request.urlopen(base + '/health', timeout=2) as response:
                        if response.status == 200:
                            break
                except (OSError, urllib.error.URLError):
                    pass
                time.sleep(2)
            else:
                raise TimeoutError('Server not healthy within 10 minutes')

            settings = {'model': args.model, 'temperature': 1.0, 'top_p': 0.95, 'top_k': 20, 'min_p': 0.0,
                        'presence_penalty': 0.0, 'repeat_penalty': 1.0, 'seed': 42,
                        'chat_template_kwargs': kwargs, 'reasoning_budget_message': '',
                        'cache_prompt': False}
            if 'reasoning_effort' in kwargs:
                settings['reasoning_effort'] = kwargs['reasoning_effort']

            # Check that the thinking budget is enforced before spending hours on the real run.
            smoke = dict(settings, messages=[{'role': 'user', 'content':
                         'Find the number of primes less than 100. Explain the calculation carefully.'}],
                         reasoning_budget_tokens=32, max_tokens=1024, stream=False)
            with post('/v1/chat/completions', smoke) as response:
                msg = json.load(response)['choices'][0]['message']
            reasoning = msg.get('reasoning_content') or msg.get('reasoning') or ''
            assert reasoning and msg.get('content'), 'Budget check did not produce both thinking and an answer'
            with post('/tokenize', {'content': reasoning, 'add_special': False}) as response:
                smoke_tokens = len(json.load(response)['tokens'])
            assert smoke_tokens <= 40, f'Thinking budget not enforced: {smoke_tokens} tokens'
            print(f'P{args.problem}: budget check passed; starting the problem', flush=True)

            messages = [{'role': 'system', 'content': 'You are a helpful assistant.'},
                        {'role': 'user', 'content': 'Solve the following IMO 2026 problem. Give a complete, rigorous proof.\n\n'
                         + f'Problem {args.problem}. ' + problem['text']}]
            request = dict(settings, messages=messages, reasoning_budget_tokens=THINKING_BUDGET,
                           max_tokens=MAX_TOKENS, stream=True, stream_options={'include_usage': True})
            save(out / 'request.json', request)

            started = time.monotonic()
            usage, finish_reason, done = None, None, False
            with post('/v1/chat/completions', request) as response, \
                    (out / 'thinking.txt').open('w') as think, (out / 'answer.md').open('w') as answer:
                for raw in response:
                    line = raw.decode().strip()
                    if not line.startswith('data: '):
                        continue
                    if line == 'data: [DONE]':
                        done = True
                        break
                    chunk = json.loads(line[6:])
                    if chunk.get('error'):
                        raise RuntimeError(chunk['error'])
                    if chunk.get('usage'):
                        usage = chunk['usage']
                    for choice in chunk.get('choices', []):
                        delta = choice.get('delta', {})
                        think.write(delta.get('reasoning_content') or delta.get('reasoning') or '')
                        answer.write(delta.get('content') or '')
                        finish_reason = choice.get('finish_reason') or finish_reason
            assert done and finish_reason, 'Incomplete event stream'
            result = {'finish_reason': finish_reason, 'usage': usage,
                      'generation_seconds': round(time.monotonic() - started, 1)}
            save(out / 'result.json', result)
            print(json.dumps(result), flush=True)
        finally:
            server.terminate()
            try:
                server.wait(timeout=20)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait()


if __name__ == '__main__':
    main()
