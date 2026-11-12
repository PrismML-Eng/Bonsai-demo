# OpenCode with the local Bonsai 2 model

This is an optional OpenCode-only profile. It is separate from the Hermes
agent demo and does not change the default llama-server or OpenCode setup.

## Start

From PowerShell, launch the full workflow:

```powershell
.\scripts\Start-BonsaiCode.ps1
```

The launcher reuses a matching server or starts the dedicated profile in a
visible second PowerShell window, waits up to 15 minutes for the expected model
API to become ready, then starts OpenCode in this repository. It does not
elevate. To create a desktop shortcut, target
`powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<repo>\scripts\Start-BonsaiCode.ps1"`
and set **Start in** to the repository root. Override the readiness timeout
with `BONSAI_START_TIMEOUT` (30–3600 seconds).

To run the server and OpenCode manually instead:

```powershell
.\scripts\start_opencode_server.ps1
opencode .
```

The project-scoped `.opencode/opencode.json` selects the local model at
`http://127.0.0.1:8080/v1`. The server profile defaults to a 262,144-token
context, one request slot, and a 2,048-token reasoning budget. Set
`BONSAI_CTX` to a smaller explicit value if the machine cannot hold the full
context; OpenCode's configured input limit is 196,608 tokens to leave room for
generation and protocol overhead. If you lower the server context, lower the
model's `limit.context` and `limit.input` in `.opencode/opencode.json` to match.
Set `BONSAI_OPENCODE_REASONING_BUDGET` to raise or lower the thinking cap.

OpenCode starts background compaction before the configured input budget is
nearly full, preserves about 12,000 recent tokens, and bounds retained tool
output. For an already oversized conversation, start a fresh session or run
OpenCode's `/compact` once; profile changes apply to new sessions, not the
model and history already attached to an existing session.
Use `/mcps` to keep only task-relevant MCP servers enabled: their tool schemas
consume prompt context before the model starts working.

The `build` agent gets a finite step budget and concise repository-specific
workflow instructions. `/review` starts a read-only reviewer subagent.
Background compaction is experimental in OpenCode and can still wait for the
local model when its single server slot is busy. The reasoning cap limits
unbounded thinking, but it does not make cold model loading or a large prompt
prefill instantaneous.
