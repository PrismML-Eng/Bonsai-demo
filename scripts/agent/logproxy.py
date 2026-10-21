#!/usr/bin/env python3
"""Wire-level transcript capture for any OpenAI-compatible harness -> server (llama-server here).

Records every /chat/completions exchange to JSONL: full message prefix (incl. tool schemas and
tool results), sampling params, usage, finish_reason, and the assistant reply. Handles BOTH
non-streamed JSON and SSE streams, relays chunks as they arrive (never buffers a long
generation), and logs in a finally block so a client disconnect still produces a record.

Usage: logproxy.py <listen_port> <upstream_host> <upstream_port> <out.jsonl>
"""
import http.client, os, json, os,sys,time,urllib.request,urllib.error
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
LISTEN=int(sys.argv[1]); UHOST=sys.argv[2]; UPORT=int(sys.argv[3]); OUT=sys.argv[4]
TURN=[0]

def parse_response(raw:bytes):
    """-> (usage, finish_reason, assistant_message, streamed?)"""
    txt=raw.decode("utf-8","replace")
    try:
        js=json.loads(txt); ch=(js.get("choices") or [{}])[0]
        u=js.get("usage"); t=js.get("timings")
        if t and isinstance(u,dict): u=dict(u, timings={k:t.get(k) for k in ("prompt_n","prompt_ms","predicted_n","predicted_ms","predicted_per_second","prompt_per_second","cache_n")})
        return u, ch.get("finish_reason"), ch.get("message"), False
    except Exception:
        pass
    content=""; reasoning=""; tools={}; usage=None; finish=None; timings=None
    for line in txt.splitlines():
        if not line.startswith("data:"): continue
        p=line[5:].strip()
        if not p or p=="[DONE]": continue
        try: ev=json.loads(p)
        except Exception: continue
        if ev.get("usage"): usage=ev["usage"]
        if ev.get("timings"): timings=ev["timings"]   # llama-server final chunk: prompt_n/prompt_ms/predicted_n/predicted_ms/predicted_per_second
        if ev.get("provider"): globals()["_LAST_PROVIDER"]=ev["provider"]
        c0=(ev.get("choices") or [{}])[0]
        if c0.get("finish_reason"): finish=c0["finish_reason"]
        d=c0.get("delta") or {}
        if d.get("content"): content+=d["content"]
        if d.get("reasoning_content"): reasoning+=d["reasoning_content"]   # llama.cpp --reasoning-format deepseek / vLLM reasoning parser stream thoughts here
        elif d.get("reasoning"): reasoning+=d["reasoning"]
        for tc in (d.get("tool_calls") or []):
            i=tc.get("index",0); e=tools.setdefault(i,{"function":{"name":"","arguments":""}})
            fn=tc.get("function") or {}
            if fn.get("name"): e["function"]["name"]=fn["name"]
            if fn.get("arguments"): e["function"]["arguments"]+=fn["arguments"]
        if not txt.startswith("data:") and not content: pass
    msg={"role":"assistant","content":content}
    if reasoning: msg["reasoning_content"]=reasoning
    if tools: msg["tool_calls"]=[tools[k] for k in sorted(tools)]
    if timings and isinstance(usage,dict): usage=dict(usage, timings={k:timings.get(k) for k in ("prompt_n","prompt_ms","predicted_n","predicted_ms","predicted_per_second","prompt_per_second","cache_n")})
    return usage, finish, msg, True

INJECT_KW = {}
# Optional remote upstream instead of host:port, e.g. UPSTREAM_URL=https://openrouter.ai/api  (+ UPSTREAM_KEY bearer).
UPSTREAM_URL = os.environ.get("UPSTREAM_URL")
UPSTREAM_KEY = os.environ.get("UPSTREAM_KEY")
# Optional JSON object merged into every /chat/completions body, e.g. {"reasoning":{"max_tokens":12288},"provider":{"order":["Venice"],"allow_fallbacks":false}}
INJECT_BODY = {}
_ib = os.environ.get("INJECT_BODY")
if _ib:
    try: INJECT_BODY = json.loads(_ib); sys.stderr.write("logproxy: injecting body %s\n" % (INJECT_BODY,))
    except Exception as e: sys.stderr.write("logproxy: bad INJECT_BODY (%r)\n" % (e,))
# Optional: route the PLANNING turn (a request whose messages are only system+user) to a
# different upstream, e.g. a llama-server started with a larger --reasoning-budget.
# FIRST_TURN_UPSTREAM="host:port" (as reachable from this machine).
FIRST_UP = None
_ftu = os.environ.get("FIRST_TURN_UPSTREAM")
if _ftu and ":" in _ftu:
    FIRST_UP = (_ftu.rsplit(":",1)[0], int(_ftu.rsplit(":",1)[1]))
    sys.stderr.write("logproxy: planning turn -> %s:%d\n" % FIRST_UP)
_ikw = os.environ.get("INJECT_TEMPLATE_KWARGS", "").strip()
if _ikw:
    try:
        INJECT_KW = json.loads(_ikw)
        sys.stderr.write("logproxy: injecting chat_template_kwargs=%s\n" % (INJECT_KW,))
    except Exception as e:
        sys.stderr.write("logproxy: bad INJECT_TEMPLATE_KWARGS (%r)\n" % (e,))

class H(BaseHTTPRequestHandler):
    protocol_version="HTTP/1.1"
    def log_message(self,*a): pass
    def _proxy(self,method):
        ln=int(self.headers.get("Content-Length") or 0)
        body=self.rfile.read(ln) if ln else b""
        # Hermes has no chat_template_kwargs knob. When INJECT_TEMPLATE_KWARGS is set
        # (JSON object), merge it into every /chat/completions request so the served
        # template can be driven explicitly, e.g. {"enable_thinking": true}.
        if INJECT_KW and body and self.path.endswith("/chat/completions"):
            try:
                _rq=json.loads(body)
                _kw=dict(_rq.get("chat_template_kwargs") or {})
                _kw.update(INJECT_KW)
                _rq["chat_template_kwargs"]=_kw
                body=json.dumps(_rq).encode()
            except Exception as _e:
                sys.stderr.write("inject failed: %r\n"%(_e,))
        _up=(UHOST,UPORT)
        if FIRST_UP and body and self.path.endswith("/chat/completions"):
            try:
                _m=json.loads(body).get("messages") or []
                if sum(1 for x in _m if x.get("role")!="system")<=1: _up=FIRST_UP
            except Exception: pass
        self._upstream="%s:%d"%_up
        if INJECT_BODY and body and self.path.endswith("/chat/completions"):
            try:
                _rq=json.loads(body); _rq.update(INJECT_BODY); body=json.dumps(_rq).encode()
            except Exception as _e: sys.stderr.write("inject body failed: %r\n"%(_e,))
        if UPSTREAM_URL:
            url=UPSTREAM_URL.rstrip("/")+self.path; self._upstream=UPSTREAM_URL
        else:
            url="http://%s:%d%s"%(_up[0],_up[1],self.path)
        _hdrs={k:v for k,v in self.headers.items() if k.lower() not in ("host","content-length","accept-encoding")}
        if UPSTREAM_KEY: _hdrs["Authorization"]="Bearer "+UPSTREAM_KEY
        req=urllib.request.Request(url,data=body or None,method=method,headers=_hdrs)
        chunks=[]; self._sent=False
        try:
            try:
                try:
                    r=urllib.request.urlopen(req,timeout=3600)
                except (urllib.error.URLError, ConnectionResetError, OSError) as _ce:
                    if isinstance(_ce, urllib.error.HTTPError): raise
                    sys.stderr.write("logproxy: upstream connect failed (%r), retrying once in 3s\n"%(_ce,)); time.sleep(3)
                    req=urllib.request.Request(url,data=body or None,method=method,headers=_hdrs)
                    r=urllib.request.urlopen(req,timeout=3600)
                code=r.status; ctype=r.headers.get("Content-Type","application/json")
            except urllib.error.HTTPError as e:
                data=e.read(); chunks=[data]
                self.send_response(e.code); self._sent=True; self.send_header("Content-Type",e.headers.get("Content-Type","application/json"))
                self.send_header("Content-Length",str(len(data))); self.end_headers(); self.wfile.write(data)
                return
            if "text/event-stream" in (ctype or ""):
                self.send_response(code); self._sent=True; self.send_header("Content-Type",ctype)
                self.send_header("Transfer-Encoding","chunked"); self.send_header("Cache-Control","no-cache"); self.end_headers()
                # If the upstream connection is cut mid-stream (seen 3x today: forwarded connections to a
                # node dropped at one instant), do NOT propagate the reset -- Hermes dies on it.  Close the
                # SSE stream cleanly with finish_reason=length so Hermes treats it as a truncated turn
                # and continues with its normal "response was truncated" nudge.
                try:
                    while True:
                        buf=r.read(4096)
                        if not buf: break
                        chunks.append(buf)
                        self.wfile.write(("%X\r\n"%len(buf)).encode()+buf+b"\r\n"); self.wfile.flush()
                except (ConnectionResetError, ConnectionAbortedError, BrokenPipeError, TimeoutError, OSError, http.client.HTTPException) as _ue:
                    sys.stderr.write("logproxy: upstream stream cut (%r) -> closing SSE as finish_reason=length\n"%(_ue,))
                    tail=(b'data: {"id":"proxy-cut","object":"chat.completion.chunk","choices":[{"index":0,"delta":{},"finish_reason":"length"}],"proxy_upstream_error":"%s"}\n\ndata: [DONE]\n\n' % type(_ue).__name__.encode())
                    chunks.append(tail)
                    try: self.wfile.write(("%X\r\n"%len(tail)).encode()+tail+b"\r\n"); self.wfile.flush()
                    except Exception: pass
                self.wfile.write(b"0\r\n\r\n"); self.wfile.flush()
            else:
                data=r.read(); chunks=[data]
                self.send_response(code); self._sent=True; self.send_header("Content-Type",ctype)
                self.send_header("Content-Length",str(len(data))); self.end_headers(); self.wfile.write(data)
            r.close()
        except Exception as _e:
            # an upstream that never answered (connection refused twice, DNS, bad URL): answer the client
            # with a 502 instead of closing silently, which some clients wait on
            sys.stderr.write("logproxy: upstream error %r\n"%(_e,))
            if not self._sent:
                try:
                    data=json.dumps({"error":{"message":"logproxy: upstream error: %s"%(_e,),"type":"upstream_error","code":502}}).encode()
                    chunks=[data]
                    self.send_response(502); self._sent=True; self.send_header("Content-Type","application/json")
                    self.send_header("Content-Length",str(len(data))); self.end_headers(); self.wfile.write(data)
                except Exception: pass
        finally:
            if self.path.endswith("/chat/completions") and body:
                try:
                    rq=json.loads(body)
                    usage,finish,msg,streamed=parse_response(b"".join(chunks))
                    TURN[0]+=1
                    rec={"ts":time.time(),"turn":TURN[0],"model":rq.get("model"),
                         "n_messages":len(rq.get("messages") or []),"has_tools":bool(rq.get("tools")),
                         "sampling":{k:rq.get(k) for k in ("temperature","top_p","top_k","min_p","max_tokens","stream","presence_penalty","frequency_penalty","repeat_penalty","repeat_last_n","reasoning_effort","reasoning","seed") if k in rq},
                         "chat_template_kwargs":rq.get("chat_template_kwargs"),
                         "usage":usage,"finish_reason":finish,"streamed":streamed,
                         "messages":rq.get("messages"),"tools":rq.get("tools"),"response_message":msg,"upstream":getattr(self,"_upstream",None),"provider":globals().get("_LAST_PROVIDER")}
                    with open(OUT,"a",encoding="utf-8") as f: f.write(json.dumps(rec,ensure_ascii=False)+"\n")
                except Exception: pass
    def do_POST(self): self._proxy("POST")
    def do_GET(self): self._proxy("GET")

if __name__=="__main__":
    print("logproxy :%d -> %s:%d  transcript -> %s"%(LISTEN,UHOST,UPORT,OUT),flush=True)
    ThreadingHTTPServer(("127.0.0.1",LISTEN),H).serve_forever()
