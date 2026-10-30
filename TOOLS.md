# Tool calling & MCP

For opt-in checks against a running server, see [Local API smoke checks](API-SMOKE.md).

The 27B models are trained for agentic tool use. This page covers the three ways to
use that: the raw API, MCP servers in the llama-server chat UI, and the Open WebUI
demo. (Running the servers is covered in the [README](README.md); model-tuning knobs
in [AGENTS.md](AGENTS.md).)

## Native tool calling (OpenAI-compatible API)

`start_llama_server.sh` runs the 27B with `--jinja`, so `/v1/chat/completions`
accepts the standard OpenAI `tools` array and returns structured `tool_calls`
(no prompt hacks needed). The MLX server (`start_mlx_server.sh`) emits native
`tool_calls` too.

```bash
curl -s http://localhost:8080/v1/chat/completions -H "Content-Type: application/json" -d '{
  "messages": [{"role": "user", "content": "What is the weather in Lisbon?"}],
  "tools": [{
    "type": "function",
    "function": {
      "name": "get_weather",
      "description": "Get current weather for a city",
      "parameters": {
        "type": "object",
        "properties": {"city": {"type": "string"}},
        "required": ["city"]
      }
    }
  }]
}'
```

The response's `choices[0].message.tool_calls` carries the call; append your tool
result as a `"role": "tool"` message and continue the conversation as usual.

## MCP prompt cost (read this before enabling servers)

Every MCP server that is active in a chat has its tool schemas rendered into that
chat's prompt, adding prefill time before the first token — noticeable on Macs and
CPU boxes. The llama-server UI keeps its MCP servers **per-chat opt-in**. Open
WebUI attaches local tools and the selected web search to new model records;
Hugging Face and DeepWiki remain opt-in there. Existing model selections are kept.

Measured from the live servers (2026-07; will drift as they update their tools):

| MCP server | Tools | Approx. prompt tokens |
|---|---|---|
| Hugging Face | 8 | ~2,600 (biggest: `hf_fs` ~670, `hub_repo_details` ~490, `hub_repo_search` ~440) |
| DeepWiki | 3 | ~400 |
| Brave Search | 3 (web/news/summarizer) | ~2,900 (its full 8-tool set is ~29k - `brave_place_search` alone is ~20k - so the demo enables only these three via `--enabled-tools`) |

The cost is one-time per server run, not per chat: the schemas form a stable prompt
prefix and llama-server reuses the cached prefix across new chats, as long as the
enabled set (and order) doesn't change. On slow hardware prefer a small fixed subset
over toggling servers between chats; on a fast GPU turning everything on is cheap.

## MCP in the llama-server chat UI

The built-in UI (http://localhost:8080) has an MCP client with an agentic loop.
The start scripts pass `--webui-config-file scripts/webui-config.json`, which
preconfigures two servers:

- **Hugging Face** (`https://huggingface.co/mcp`) — search models, datasets and
  Spaces on the Hub.
- **DeepWiki** (`https://mcp.deepwiki.com/mcp`) — ask questions about any public
  GitHub repository (Cognition's auto-generated repo wikis).

They appear in the MCP selector in the message box (and in Settings → MCP Client),
but **no tool schemas are sent until you turn a server on for a chat**:

- Toggling a server inside an open conversation enables it for that conversation only.
- Toggling on the **new-chat screen** makes it your default for all future chats
  (stored in the browser; toggle it off the same way to stop).

`agenticMaxTurns` (default 10) bounds the tool loop. All of this state lives in the
browser (localStorage), per-user and per-machine.

**Troubleshooting: every new chat prefills ~2–3k tokens.** A server was toggled on
from the new-chat screen at some point, making it this browser's default for new
chats. Toggle it off in the new-chat screen's MCP selector, or clear site data for
`localhost:8080` (browser DevTools → Application/Storage → Clear site data). A
private/incognito window shows what a fresh browser would see; there is no way to
reset browser state from the server side.

### Optional: web search (Brave) in the llama-server UI

The llama-server UI ships out-of-the-box features only, so it does **not** auto-start
a bridge — but you can add Brave web search yourself with a Brave Search API key. Run
the bridge (key via env, never committed):

```bash
npm i -g @brave/brave-search-mcp-server
BRAVE_API_KEY=your_key brave-search-mcp-server --transport http --host 127.0.0.1 --port 8001
```

Then add it in the UI: **Settings → MCP Client → add** `http://127.0.0.1:8001/mcp`
(or add an entry to `scripts/webui-config.json`, keeping `"enabled":true` so it's a
per-chat opt-in). In the **Open WebUI** demo this is wired for you (next section).

## Tools & MCP in the Open WebUI demo

`./scripts/start_openwebui.sh` seeds a set of **on-by-default** capabilities:

- **weather**, **web fetch**, **demo SQL database** — local Python tools (small schemas).
- **code interpreter** (server-side Python via Jupyter — plots, pandas, yfinance).
- **time** — `get_current_timestamp` (a builtin tool); the model is also told the
  current date/time in its system prompt (`{{CURRENT_DATE}}`), so "this year" /
  "recent" reasoning works without a tool call.
- **Web search** — Parallel Search MCP on a fresh installation; configured Brave
  credentials select Brave instead (key + bridge, below).

Hugging Face and DeepWiki are connected but **per-chat opt-in** (their schemas are
heavy); pick them from the tool menu in the message box when a chat needs them.

### Web search selection

The default `BONSAI_WEB_SEARCH=auto` uses [Parallel Search MCP](https://docs.parallel.ai/integrations/mcp/search-mcp)
at `https://search.parallel.ai/mcp` when no Brave key is configured. It provides
`web_search` and `web_fetch`, with anonymous search using Fast mode. No account,
API key, npm package, or local bridge is needed. The free endpoint has limits
and is intended for exploration and light use; inference still runs on your
local model. This is the standalone Search MCP endpoint, which Parallel retains
for existing clients; its documentation also describes the newer unified MCP.

Set the provider explicitly on launch:

```bash
BONSAI_WEB_SEARCH=parallel ./scripts/start_openwebui.sh  # even with a Brave key
BONSAI_WEB_SEARCH=brave ./scripts/start_openwebui.sh     # needs key + bridge
BONSAI_WEB_SEARCH=none ./scripts/start_openwebui.sh      # no general-search server
```

A `BRAVE_API_KEY` or gitignored `.brave_key` keeps Brave selected in auto mode.
If its bridge is missing or fails, the demo does not switch providers silently.
Brave's news and summarizer tools remain available through its existing setup.

New model records attach the selected search server. Re-seeding preserves
existing `toolIds` (including an empty list) and model access grants, so upgrading
does not re-enable disabled tools or replace a saved selection. For an existing
model, pick the available search server from the chat's tool menu, or edit the
model's tool selection. Provider overrides control which search connection is
available; they do not rewrite those saved selections. `none` removes both search
connections, including for models that previously selected one. Weather, web fetch,
and the other tools remain available.

With Brave selected, its schemas add ~2.9k prompt tokens. Keep search per-chat by
removing its `server:mcp:<id>` entry from the model's saved tool selection.

`web_fetch` reads arbitrary public pages, but some sites (e.g. Reuters) block
automated fetches and return 401/403 - that's the site, not the tool.

**Optional: Brave Search (web search).** Needs a Brave Search API key and a local
bridge. Install the bridge once:

```bash
npm i -g @brave/brave-search-mcp-server
```

Then provide the key one of two ways — either is local-only and never committed:

```bash
BRAVE_API_KEY=your_key ./scripts/start_openwebui.sh
```

or drop it in a gitignored file so you don't have to pass it each time:

```bash
echo "your_key" > .brave_key
./scripts/start_openwebui.sh
```

The script starts the bridge on `127.0.0.1:8001`, passes your key to it via the
environment (the key never touches the repo or the config), connects it as the
`brave` MCP server, and shuts it down with everything else on Ctrl+C.

## Adding your own MCP servers

Only servers speaking **streamable HTTP** work directly — a stdio-only server needs
a local HTTP bridge first (the Brave setup above is the pattern: run the bridge,
point the config at `http://127.0.0.1:<port>/mcp`).

**llama-server chat UI** — two places:

- Per-browser (no restart): Settings → MCP Client → add name + URL.
- Shipped default for everyone: add an entry to the `mcpServers` JSON-string in
  [scripts/webui-config.json](scripts/webui-config.json) and restart the server:

  ```json
  {"id":"context7","enabled":true,"name":"Context7","url":"https://mcp.context7.com/mcp","requestTimeoutSeconds":300}
  ```

  `"enabled":true` only lists the server in the per-chat selector — chats still opt
  in individually, so this costs nothing by default. Add `"useProxy":true` if the
  server rejects browser CORS requests (llama-server ships a `/cors-proxy`).

**Open WebUI** — edit the `TOOL_SERVER_CONNECTIONS` JSON in
[scripts/openwebui/mcp_servers.sh](scripts/openwebui/mcp_servers.sh), sourced by
[scripts/start_openwebui.sh](scripts/start_openwebui.sh), and restart. Do **not** add
servers through the admin panel: the demo runs with `ENABLE_PERSISTENT_CONFIG=false`,
so panel edits are lost on restart — the script is the source of truth. Entry shape:

```json
{"id":"context7","type":"mcp","url":"https://mcp.context7.com/mcp","path":"","auth_type":"none","key":"","config":{"enable":true,"access_grants":[{"principal_type":"user","principal_id":"*","permission":"read"}]},"info":{"id":"context7","name":"Context7","description":"Library docs"}}
```

For servers that need a token, set `"auth_type":"bearer"` and inject the secret at
runtime instead of hardcoding it in the tracked script: keep it in an environment
variable or a gitignored file (the Brave key below uses `.brave_key`), and reference
it from the JSON the script builds, e.g. `"key":"'"'"'$MY_MCP_KEY'"'"'"` inside the
`TOOL_SERVER_CONNECTIONS` block. Never commit a literal token. `config.enable: true` means connected and visible in the chat tool menu —
still per-chat opt-in. To attach a server to new model records, add `server:mcp:<id>`
to the default tool selection in [scripts/openwebui/seed_openwebui.py](scripts/openwebui/seed_openwebui.py).
For existing records, edit the model's saved tool selection (mind the prompt-token
table above).
