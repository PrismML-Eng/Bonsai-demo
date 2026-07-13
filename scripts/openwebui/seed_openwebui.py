"""Seed Open WebUI with the Bonsai demo tools and model settings.

Run by start_openwebui.sh once the UI is up. Idempotent: re-running updates
the tools/models in place, so every start re-seeds safely. Never fails the
launcher — problems are printed as [seed] warnings and the script exits 0.

Usage:
  python seed_openwebui.py --url http://localhost:9090 \
      [--llama-url http://localhost:8080/v1] [--llama-vision] \
      [--mlx-url http://localhost:8081/v1] [--mlx-vision]
"""

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

TOOLS_DIR = os.path.dirname(os.path.abspath(__file__))

# Code interpreter is on when start_openwebui.sh started the Jupyter kernel.
CODE_INTERPRETER_ON = os.environ.get("BONSAI_CODE_INTERPRETER_ON") == "1"

# (id, name, file, description)
TOOLS = [
    ("weather", "Weather", "tool_weather.py",
     "Current weather and forecast for any location"),
    ("web_fetch", "Web Fetch", "tool_web_fetch.py",
     "Fetch and read the text content of any URL"),
    ("demo_db", "Demo Sales Database", "tool_sql.py",
     "Read-only SQLite access to a demo sales database"),
]
if CODE_INTERPRETER_ON:
    # This repo-owned tool shadows Open WebUI's builtin function of the same name.
    # It uses the same Jupyter backend but returns compact, truthful statuses.
    TOOLS.append((
        "python_code", "Python Code Interpreter", "tool_code_interpreter.py",
        "Run Python for calculations, data analysis, and plots",
    ))
TOOL_IDS = [t[0] for t in TOOLS]

# MCP servers (TOOL_SERVER_CONNECTIONS in start_openwebui.sh): Brave web search is
# attached to the model (on by default) when it's configured; Hugging Face / DeepWiki
# stay per-chat opt-in because their schemas add thousands of prompt tokens. Attach
# any server to every chat by adding "server:mcp:<id>" to the model's toolIds.
_MCP_IDS = [s for s in os.environ.get("BONSAI_MCP_IDS", "").split(",") if s]
DEFAULT_MCP_TOOL_IDS = [f"server:mcp:{s}" for s in _MCP_IDS if s == "brave"]

# Open WebUI substitutes these at request time, so the model always knows "now".
SYSTEM_PROMPT = (
    "You are a helpful assistant running locally inside Open WebUI as part of "
    "the Bonsai demo. "
    "Today is {{CURRENT_WEEKDAY}}, {{CURRENT_DATE}}. Use tools for current, "
    "specific, or verifiable information and for exact calculations. Plan enough "
    "to verify the answer, parallelize independent work when useful, and avoid "
    "repeating successful work. For web research, use focused searches and fetch "
    "a promising source when a claim needs more context or verification. Treat "
    "snippets as leads, distinguish facts from inference or opinion, and do not "
    "claim causation without evidence. When explaining why an event happened, "
    "inspect evidence from before it; later events cannot be its cause. Check tool "
    "outputs and never invent missing facts or numbers. Respect requested date "
    "ranges and account for exclusive end dates when a tool uses them. Answer "
    "plainly without a references section. Inspect an unfamiliar database's schema "
    "before substantive queries."
)
if CODE_INTERPRETER_ON:
    SYSTEM_PROMPT += (
        " Use execute_code only when the user explicitly requests Python or a chart, "
        "or when another tool cannot perform a necessary exact calculation. Never "
        "create a plot unless explicitly requested. Every call uses a fresh kernel, "
        "so each call must include its own imports and setup. Keep output compact. "
        "When an API is unclear, it is okay to inspect its help or signature first. "
        "Read errors and suggested fixes before retrying, never repeat unchanged "
        "failing code, and preserve successful outputs. Open WebUI attaches plots "
        "displayed by execute_code; refer to them as attachments and never copy, "
        "invent, or modify internal /api/v1/files URLs."
    )

# Builtin tools: keep the master gate ON and narrow it to time + code_interpreter.
# When Jupyter is up, the attached `python_code` toolkit registers execute_code
# first, so Open WebUI skips its same-named builtin and our compact result wrapper
# is used. The remaining builtin categories stay off to avoid prompt bloat.
_BUILTIN_TOOL_CATEGORIES = (
    "automations", "calendar", "channels", "chats", "code_interpreter",
    "image_generation", "knowledge", "memory", "notes", "tasks", "time",
    "web_search",
)
BUILTIN_TOOLS_META = {c: False for c in _BUILTIN_TOOL_CATEGORIES}
BUILTIN_TOOLS_META["time"] = True
BUILTIN_TOOLS_META["code_interpreter"] = CODE_INTERPRETER_ON

# Everyone can use the seeded tools/models (matters only if auth is enabled).
ACCESS_GRANTS = [{"principal_type": "user", "principal_id": "*", "permission": "read"}]


def log(msg):
    print(f"[seed] {msg}", flush=True)


class Api:
    def __init__(self, base):
        self.base = base.rstrip("/")
        self.token = None

    def request(self, method, path, payload=None, timeout=15):
        req = urllib.request.Request(
            self.base + path,
            data=json.dumps(payload).encode() if payload is not None else None,
            headers={"Content-Type": "application/json"},
            method=method,
        )
        if self.token:
            req.add_header("Authorization", f"Bearer {self.token}")
        with urllib.request.urlopen(req, timeout=timeout) as r:
            body = r.read()
        return json.loads(body) if body else {}

    def signin(self):
        """With WEBUI_AUTH=false the frontend signs in with empty credentials
        and receives the auto-admin's session token; do the same."""
        try:
            data = self.request("POST", "/api/v1/auths/signin",
                                {"email": "", "password": ""})
            self.token = data.get("token") or None
            return self.token is not None
        except Exception:
            return False


def wait_for_webui(api, tries=60):
    for _ in range(tries):
        try:
            api.request("GET", "/api/config")
            return True
        except Exception:
            time.sleep(2)
    return False


def fetch_backend_model_ids(base_url):
    """Ask an OpenAI-compatible backend which model ids it serves.
    Returns (bonsai_ids, other_ids) - some backends (mlx-vlm) also list
    helper models (e.g. an embedding model) that should be hidden."""
    try:
        req = urllib.request.Request(base_url.rstrip("/") + "/models")
        with urllib.request.urlopen(req, timeout=10) as r:
            data = json.loads(r.read())
        ids = [m["id"] for m in data.get("data", []) if m.get("id")]
        bonsai = [i for i in ids if "bonsai" in i.lower()]
        return bonsai, [i for i in ids if i not in bonsai]
    except Exception as e:
        log(f"WARN: could not list models from {base_url}: {e}")
        return [], []


def seed_tool(api, tool_id, name, filename, description):
    path = os.path.join(TOOLS_DIR, filename)
    try:
        with open(path) as f:
            content = f.read()
    except OSError as e:
        log(f"WARN: cannot read {path}: {e}")
        return
    payload = {
        "id": tool_id,
        "name": name,
        "content": content,
        "meta": {"description": description},
        "access_grants": ACCESS_GRANTS,
    }
    try:
        api.request("GET", f"/api/v1/tools/id/{tool_id}")
        api.request("POST", f"/api/v1/tools/id/{tool_id}/update", payload)
        log(f"tool updated: {tool_id}")
    except urllib.error.HTTPError as e:
        if e.code == 401:
            log(f"WARN: not authorized to manage tools ({e}); skipping {tool_id}")
            return
        try:
            api.request("POST", "/api/v1/tools/create", payload)
            log(f"tool created: {tool_id}")
        except Exception as e2:
            log(f"WARN: could not create tool {tool_id}: {e2}")
    except Exception as e:
        log(f"WARN: tool {tool_id}: {e}")


def display_name(model_id, backend):
    """Friendly UI name: strip paths and .gguf, tag the backend."""
    base = model_id.rstrip("/").split("/")[-1]
    if base.endswith(".gguf"):
        base = base[: -len(".gguf")]
    return f"{base} ({backend})"


def _model_params(model_id):
    """Params for the seeded model record. We ship the demo system prompt and
    leave each model on its own tested sampling defaults."""
    return {"system": SYSTEM_PROMPT}


def seed_model(api, model_id, vision, native_tools, backend):
    payload = {
        "id": model_id,
        "base_model_id": None,
        "name": display_name(model_id, backend),
        "meta": {
            "capabilities": {
                "vision": vision,
                "file_upload": True,
                "usage": True,
                # Open WebUI otherwise rewrites the original user message with its
                # RAG citation template after fetch_url calls. That conflicts with
                # the demo prompt and invalidates llama.cpp's long prefix cache.
                "citations": False,
                # Server-side Python (Jupyter) for plots / data / yfinance,
                # when start_openwebui.sh started the kernel.
                "code_interpreter": CODE_INTERPRETER_ON,
                # Master gate for builtin tools. Kept ON so the `time` tool is
                # always available; builtinTools below narrows the set to just
                # time + code_interpreter, leaving the ~24 others (notes/
                # write_note, calendar, memory, ...) OFF.
                "builtin_tools": True,
            },
            # Per-category switch (see BUILTIN_TOOLS_META): time on, code
            # interpreter when the kernel is up, everything else off.
            "builtinTools": BUILTIN_TOOLS_META,
            # Local tools (weather / web_fetch / demo_db) + Brave web search
            # (server:mcp:brave) when configured, all on by default.
            "toolIds": TOOL_IDS + DEFAULT_MCP_TOOL_IDS,
            # Turn the code interpreter on by default for new chats.
            "defaultFeatureIds": (["code_interpreter"] if CODE_INTERPRETER_ON else []),
            "bonsai_seeded": True,
        },
        "access_grants": ACCESS_GRANTS,
        "params": _model_params(model_id),
    }
    if native_tools:
        # llama-server is started with --jinja and emits OpenAI tool_calls.
        payload["params"]["function_calling"] = "native"
    try:
        api.request("GET", f"/api/v1/models/model?id={model_id}")
        api.request("POST", f"/api/v1/models/model/update?id={model_id}", payload)
        log(f"model updated: {model_id} (vision={vision}, native_tools={native_tools})")
    except urllib.error.HTTPError:
        try:
            api.request("POST", "/api/v1/models/create", payload)
            log(f"model created: {model_id} (vision={vision}, native_tools={native_tools})")
        except Exception as e2:
            log(f"WARN: could not create model record {model_id}: {e2}")
    except Exception as e:
        log(f"WARN: model {model_id}: {e}")


def seed_stream_filter(api):
    """Install the global stream filter that works around an Open WebUI bug:
    mlx_vlm.server sends "timings": null in every SSE chunk and Open WebUI's
    stream handler crashes on it per-chunk (silently dropping all content).
    Harmless for other backends."""
    fid = "mlx_stream_normalizer"
    path = os.path.join(TOOLS_DIR, "filter_mlx_stream.py")
    try:
        with open(path) as f:
            content = f.read()
    except OSError as e:
        log(f"WARN: cannot read {path}: {e}")
        return
    payload = {
        "id": fid,
        "name": "MLX Stream Chunk Normalizer",
        "meta": {"description": "Strips explicit null timings/usage from streaming chunks (mlx_vlm workaround)"},
        "content": content,
    }
    try:
        rec = api.request("GET", f"/api/v1/functions/id/{fid}")
    except Exception:
        rec = None
    try:
        if rec:
            api.request("POST", f"/api/v1/functions/id/{fid}/update", payload)
        else:
            api.request("POST", "/api/v1/functions/create", payload)
            rec = api.request("GET", f"/api/v1/functions/id/{fid}")
        # The toggle endpoints FLIP state - only fire when needed.
        if not (rec or {}).get("is_active"):
            api.request("POST", f"/api/v1/functions/id/{fid}/toggle")
        if not (rec or {}).get("is_global"):
            api.request("POST", f"/api/v1/functions/id/{fid}/toggle/global")
        log("stream filter seeded: mlx_stream_normalizer (active, global)")
    except Exception as e:
        log(f"WARN: could not seed stream filter: {e}")


def hide_model(api, model_id):
    """Soft-disable a helper model so it doesn't clutter the picker."""
    try:
        rec = api.request("GET", f"/api/v1/models/model?id={urllib.parse.quote(model_id)}")
    except Exception:
        rec = None
    try:
        if not rec:
            api.request("POST", "/api/v1/models/create", {
                "id": model_id, "base_model_id": None, "name": model_id,
                "meta": {"bonsai_seeded": True, "description": "backend helper model (hidden)"},
                "params": {}, "access_grants": ACCESS_GRANTS,
            })
            rec = {"is_active": True}
        if rec.get("is_active", True):
            api.request("POST", f"/api/v1/models/model/toggle?id={urllib.parse.quote(model_id)}")
            log(f"hidden helper model: {model_id}")
    except Exception as e:
        log(f"WARN: could not hide {model_id}: {e}")


def cleanup_stale(api, live_ids):
    """Delete records this script created in past runs for models that no
    backend currently serves. Never touches records made by hand."""
    try:
        data = api.request("GET", "/api/v1/models/list")
        records = data.get("items", data if isinstance(data, list) else [])
    except Exception as e:
        log(f"WARN: could not list model records: {e}")
        return
    for rec in records:
        rid = rec.get("id")
        if not rid or rid in live_ids:
            continue
        if not (rec.get("meta") or {}).get("bonsai_seeded"):
            continue
        try:
            api.request("POST", f"/api/v1/models/model/delete?id={urllib.parse.quote(rid)}")
            log(f"removed stale record: {rid}")
        except Exception as e:
            log(f"WARN: could not remove stale record {rid}: {e}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True, help="Open WebUI base URL")
    ap.add_argument("--llama-url", help="llama-server OpenAI base URL, e.g. http://localhost:8080/v1")
    ap.add_argument("--llama-vision", action="store_true")
    ap.add_argument("--mlx-url", help="MLX server OpenAI base URL, e.g. http://localhost:8081/v1")
    ap.add_argument("--mlx-vision", action="store_true")
    args = ap.parse_args()

    api = Api(args.url)
    if not wait_for_webui(api):
        log("WARN: Open WebUI did not become ready - skipping seeding")
        return

    # With WEBUI_AUTH=false the frontend signs in with empty credentials and
    # gets the auto-admin's token; do the same. (On the very first boot the
    # API also accepts unauthenticated writes, but after that a token is
    # required, so always prefer signing in.)
    if not api.signin():
        log("no session token (first boot?) - trying unauthenticated seeding")
    try:
        api.request("GET", "/api/v1/tools/")
    except Exception as e:
        log(f"WARN: Open WebUI API unreachable ({e}) - skipping seeding")
        return

    for tool in TOOLS:
        seed_tool(api, *tool)

    seed_stream_filter(api)

    # Both backends emit native OpenAI tool_calls (llama-server via --jinja;
    # mlx_lm / mlx-vlm natively).
    seeded_ids, hidden_ids = [], []
    if args.llama_url:
        bonsai, other = fetch_backend_model_ids(args.llama_url)
        for mid in bonsai:
            seed_model(api, mid, vision=args.llama_vision, native_tools=True,
                       backend="llama.cpp")
        seeded_ids += bonsai
        hidden_ids += other
    if args.mlx_url:
        bonsai, other = fetch_backend_model_ids(args.mlx_url)
        for mid in bonsai:
            seed_model(api, mid, vision=args.mlx_vision, native_tools=True,
                       backend="MLX")
        seeded_ids += bonsai
        hidden_ids += other

    # Hide backend helper models (e.g. mlx-vlm's embedding model) from the picker.
    for mid in hidden_ids:
        hide_model(api, mid)

    # Remove seeded records from earlier runs whose backend model is gone
    # (e.g. yesterday's binary-family records after switching to ternary).
    cleanup_stale(api, set(seeded_ids) | set(hidden_ids))

    log("done.")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # never fail the launcher
        log(f"WARN: seeding aborted: {e}")
    sys.exit(0)
