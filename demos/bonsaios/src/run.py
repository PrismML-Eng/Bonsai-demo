#!/usr/bin/env python3
"""Capture native Hermes requests and Bonsai streams; bound auxiliary summaries."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import time
from urllib.error import HTTPError
from urllib.request import Request, urlopen
from trace import StreamTrace

MODEL = "bonsai-2-27b"
SAMPLING = dict(temperature=1.0, top_p=0.95, top_k=20, min_p=0.0,
                presence_penalty=0.0, repeat_penalty=1.0, frequency_penalty=0.0)


def dump(path, value):
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(value, indent=2) + "\n")
    temporary.replace(path)


def fetch(url):
    with urlopen(url, timeout=15) as response:
        return json.load(response)


def config(base_url, cwd, effort, seed, context, turns):
    extra = {**SAMPLING, "seed": seed, "stream": True, "stream_options": {"include_usage": True},
             "reasoning_effort": effort, "reasoning_budget_tokens": -1,
             "chat_template_kwargs": {"enable_thinking": True}}
    return {
        "model": {"provider": "bonsai", "default": MODEL, "base_url": base_url,
                  "api_key": "local-bonsai", "context_length": context, "streaming": True},
        "providers": {"bonsai": {"base_url": base_url, "api_key": "local-bonsai",
                                 "extra_body": extra}},
        "agent": {"max_turns": turns, "reasoning_effort": effort},
        "terminal": {"backend": "local", "cwd": str(cwd), "timeout": 90},
        "memory": {"memory_enabled": False, "user_profile_enabled": False},
        "compression": {"enabled": True, "threshold": 0.5, "target_ratio": 0.2,
                        "protect_last_n": 20, "protect_first_n": 3},
        "auxiliary": {"title_generation": {"enabled": False}},
    }


class Capture(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        self.forward()

    def do_POST(self):
        self.forward()

    def forward(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        record = None
        if self.path.endswith("/chat/completions") and body:
            raw_request = json.loads(body)
            request = raw_request
            pin = getattr(self.server, 'environment_pins', None)
            index = None
            if pin is not None:
                request,index = pin.normalize(raw_request,self.server.phase)
                body = json.dumps(request).encode()
            # Summarization is an auxiliary call, not a main agent decoding turn.
            auxiliary = not request.get('tools') and any(
                str(m.get('content','')).startswith('You are a summarization agent creating a context checkpoint.')
                for m in request.get('messages',[]))
            record = {"hermes_request_before_environment_pinning":raw_request,"phase_request_index":index,"started": time.time(), "phase": getattr(self.server, 'phase', 0),
                      "request": request, "purpose": "compression" if auxiliary else "agent"}
            if auxiliary:
                record['original_request'] = dict(request)
                request = dict(request)
                # All conditions use the same bounded local auxiliary policy. Preserve original input.
                request.update(**SAMPLING, seed=0,
                               reasoning_effort='medium', reasoning_budget_tokens=1024,
                               chat_template_kwargs={"enable_thinking":True})
                record['request'] = request
                record['auxiliary_policy'] = 'fixed model-card sampling, medium effort, 1024 reasoning tokens'
                if getattr(self.server,'compression_mode','current')=='nonthinking-summary':
                    request.update(reasoning_budget_tokens=0,chat_template_kwargs={'enable_thinking':False},max_tokens=4096)
                    record['auxiliary_policy']='nonthinking local summary, 4096 total output tokens'
                    record['request']=request
                body=json.dumps(request).encode()
            with self.server.lock:
                self.server.counter += 1
                record["turn"] = self.server.counter
                filename = self.server.run / f"request-{record['turn']:03d}.json"
                dump(filename, record)
        started = time.monotonic()
        trace = None
        try:
            req = Request(self.server.upstream + self.path, data=body or None,
                          method=self.command, headers={"Content-Type": "application/json"})
            try:
                response = urlopen(req, timeout=self.server.request_timeout)
            except HTTPError as exc:
                response = exc
            with response:
                status = response.status
                content_type = response.headers.get("Content-Type", "application/json")
                if record is not None and 'text/event-stream' in content_type:
                    trace = StreamTrace(filename.with_suffix(''))
                    self.send_response(status)
                    self.send_header('Content-Type', content_type)
                    self.send_header('Cache-Control', 'no-cache')
                    self.send_header('Connection', 'close')
                    self.end_headers()
                    self.close_connection = True
                    last_snapshot = time.monotonic()
                    while True:
                        line = response.readline()
                        if not line:
                            break
                        trace.feed(line)
                        if pin is not None and trace.calls:
                            pin.remember_calls([trace.calls[k] for k in sorted(trace.calls)],record['phase'],index)
                        if time.monotonic() - last_snapshot >= 2:
                            record.update(status=status, response=trace.snapshot(), trace=trace.metrics(),
                                          wall_seconds=time.monotonic()-started)
                            dump(filename, record)
                            last_snapshot = time.monotonic()
                        self.wfile.write(line)
                        self.wfile.flush()
                    record.update(status=status, response=trace.snapshot(), trace=trace.metrics(),
                                  wall_seconds=time.monotonic()-started)
                    dump(filename, record)
                    return
                data = response.read()
            if record is not None:
                record.update(status=status, wall_seconds=time.monotonic() - started,
                              response=json.loads(data))
                if pin is not None:
                    calls=((record['response'].get('choices') or [{}])[0].get('message') or {}).get('tool_calls') or []
                    pin.remember_calls(calls,record['phase'],index)
                dump(filename, record)
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        except Exception as exc:
            if record is not None:
                record["error"] = str(exc)
                dump(filename, record)
            self.close_connection = True
        finally:
            if trace is not None:
                record.update(response=trace.snapshot(), trace=trace.metrics(), wall_seconds=time.monotonic()-started)
                dump(filename, record)
                trace.close()
                if pin is not None:
                    dump(self.server.run/'transport-id-map.json',pin.ids)
