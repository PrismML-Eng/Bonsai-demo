#!/usr/bin/env bash
# Run one round of the Bonsai 2 agentic demo (AGENT-DEMO.md) against a running llama-server.
#
#   ./scripts/agent/run_agent_demo.sh round0                       # the brief -> agent-runs/sk16_skateboard_1/
#   ./scripts/agent/run_agent_demo.sh feedback <prev-run-dir> <feedback.md> [name]
#   ./scripts/agent/run_agent_demo.sh task <task.md> [name]        # any brief of your own
#
# Environment:
#   AGENT_UPSTREAM   host:port of llama-server            (default 127.0.0.1:8080)
#   AGENT_MODEL      model id to send / expect             (default: first id from /v1/models)
#   AGENT_TRACE      1 = put scripts/agent/logproxy.py between Hermes and the server: records every request
#                    and response to <run>/wire.jsonl and injects AGENT_SEED / AGENT_EFFORT per request.
#                    0 (default) = Hermes talks to llama-server directly; the seed is the server's -s
#                    (start_agent_server.sh sets -s 42) and the runner checks it before launching.
#   AGENT_SEED       expected sampler seed (default 42; empty = do not check / do not inject)
#   AGENT_EFFORT     reasoning effort: xhigh | medium (default: unset = template default, xhigh). Without
#                    AGENT_TRACE=1 pass it to the server instead: --chat-template-kwargs '{"reasoning_effort":"medium"}'
#   AGENT_CONFIG     Hermes config to use                  (default: round0 -> hermes-config-round0.yaml,
#                                                                    feedback -> hermes-config-feedback.yaml)
#   AGENT_CTX        declared context in the Hermes config (default 131072; must be <= the server's -c)
#   AGENT_WORKSPACE_ROOT  where the agent's working directory is created (default /private/tmp/collect, the
#                    recorded path; falls back to $TMPDIR/bonsai-agent if that is not writable)
#   AGENT_HOME_ROOT  where the run's private HERMES_HOME is created (default: agent-runs/, i.e. <run>/home)
#
# The working directory path, the model id and the skill list are part of the system prompt Hermes builds, so the
# defaults match the recording: run name sk16_skateboard_1 under /private/tmp/collect, model id
# bonsai2-27b-pq2-v16_2 (start_agent_server.sh's default alias), and the one extra skill shipped in
# scripts/agent/skills/. Change any of them and the run is still valid, just a different sample.
#
# What it does, in order: verifies the server answers with the expected model id (a stale or foreign
# server on the port is the classic silent failure), checks the server's sampler seed (or, with
# AGENT_TRACE=1, starts scripts/agent/logproxy.py so every request and response is written to
# <run>/wire.jsonl and the seed/effort are injected per request), prepares a workspace OUTSIDE any git repo (inside one, Hermes switches
# to its coding-agent profile and behaves differently), copies the brief in as TASK.md (and the previous
# round's files for a feedback round), then launches Hermes detached. Follow progress with
#   wc -l agent-runs/<name>/wire.jsonl ; the deliverable lands in agent-runs/<name>/workspace/.
set -euo pipefail
MODE=${1:?round0 | feedback <prev-run> <feedback.md> [name] | task <task.md> [name]}
A="$(cd "$(dirname "$0")" && pwd)"; DEMO_DIR="$(cd "$A/../.." && pwd)"
VENV="$DEMO_DIR/.venv-hermes"; [ -x "$VENV/bin/python" ] || { echo "run ./scripts/agent/install_hermes.sh first"; exit 1; }
UP="${AGENT_UPSTREAM:-127.0.0.1:8080}"; UPH=${UP%:*}; UPP=${UP##*:}
case "$MODE" in
  round0)   TASK="$DEMO_DIR/demos/skateboard/prompts/round0.md"; NAME=${2:-sk16_skateboard_1}; SEED_DIR=""; CFG_DEFAULT=hermes-config-round0.yaml ;;
  feedback) PREV=${2:?previous run dir}; TASK=${3:?feedback .md}; NAME=${4:-$(basename "$PREV")_fb}; SEED_DIR="$PREV/workspace"; CFG_DEFAULT=hermes-config-feedback.yaml ;;
  task)     TASK=${2:?task .md}; NAME=${3:-task_$(date +%Y%m%dT%H%M%S)}; SEED_DIR=""; CFG_DEFAULT=hermes-config-round0.yaml ;;
  *) echo "unknown mode $MODE"; exit 1 ;;
esac
CFG="${AGENT_CONFIG:-$A/$CFG_DEFAULT}"
# the run name becomes a directory under agent-runs/ and under the workspace root and is removed there first,
# so it must be a plain name: no slashes, no leading dot
[[ "$NAME" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]] || { echo "ABORT: run name '$NAME' must match [A-Za-z0-9][A-Za-z0-9._-]*"; exit 1; }
RUN="$DEMO_DIR/agent-runs/$NAME"; [ -e "$RUN" ] && { echo "$RUN exists; pick another name"; exit 1; }

# 1. the server must be ours (checked before anything is created, so a failed check leaves nothing behind)
TMPM=$(mktemp); trap 'rm -f "$TMPM"' EXIT
curl -sf --max-time 10 "http://$UP/v1/models" > "$TMPM" || { echo "ABORT: no llama-server at $UP"; exit 1; }
MODEL="${AGENT_MODEL:-$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["data"][0]["id"])' "$TMPM")}"
grep -q "\"$MODEL\"" "$TMPM" || { echo "ABORT: $UP does not serve '$MODEL' (it serves: $(python3 -c 'import json,sys; print([m["id"] for m in json.load(open(sys.argv[1]))["data"]])' "$TMPM"))"; exit 1; }
SERVED=$(curl -sf --max-time 10 "http://$UP/props" | python3 -c 'import json,sys; d=json.load(sys.stdin); g=d.get("default_generation_settings") or {}; n=int(g.get("n_ctx") or d.get("n_ctx") or 0); print(n//max(1,int(d.get("total_slots") or 1)))' 2>/dev/null || echo 0)
CTX="${AGENT_CTX:-131072}"
[ "$SERVED" -ge "$CTX" ] || { echo "ABORT: server slot context $SERVED < declared $CTX (start the server with BONSAI_CTX>=$CTX or lower AGENT_CTX)"; exit 2; }
mkdir -p "$RUN"; mv "$TMPM" "$RUN/models.json"
# until Hermes is launched, any failure removes the run directory and stops the proxy
LAUNCHED=0; cleanup(){ [ "$LAUNCHED" = 1 ] && return 0; { [ -f "$RUN/proxy.pid" ] && kill "$(cat "$RUN/proxy.pid")" 2>/dev/null; } || true; rm -rf -- "$RUN" || true; echo "launch failed; $RUN removed" >&2; }
trap cleanup EXIT
curl -sf --max-time 10 "http://$UP/props" > "$RUN/server-props.json"

# 2. seed and (optionally) the wire proxy
TRACE="${AGENT_TRACE:-0}"; SEED="${AGENT_SEED-42}"; EFFORT="${AGENT_EFFORT:-}"
INJECT='{}'; BASE="http://$UP/v1"
if [ "$TRACE" = 1 ]; then
  PROXY_PORT=$(python3 -c 'import socket,random
for p in range(10000+random.randint(0,1500),13000):
    s=socket.socket()
    try: s.bind(("127.0.0.1",p)); s.close(); print(p); break
    except OSError: pass')
  INJECT=$(python3 -c "import json,os; d={}; s=os.environ.get('SEED',''); e=os.environ.get('EFFORT','');
d.update({'seed':int(s)} if s else {}); d.update({'chat_template_kwargs':{'reasoning_effort':e}} if e else {}); print(json.dumps(d))")
  SEED="$SEED" EFFORT="$EFFORT" INJECT_BODY="$INJECT" python3 "$A/logproxy.py" "$PROXY_PORT" "$UPH" "$UPP" "$RUN/wire.jsonl" > "$RUN/proxy.log" 2>&1 &
  echo $! > "$RUN/proxy.pid"; sleep 2
  curl -sf --max-time 10 "http://127.0.0.1:$PROXY_PORT/v1/models" >/dev/null || { echo "ABORT: proxy not relaying"; exit 3; }
  BASE="http://127.0.0.1:$PROXY_PORT/v1"
else
  # no proxy: the seed has to be the server's. llama-server reports its -s in /props (4294967295 = none)
  SERVER_SEED=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print((d.get("default_generation_settings") or {}).get("params",{}).get("seed",""))' "$RUN/server-props.json" 2>/dev/null || echo "")
  if [ -n "$SEED" ] && [ "$SERVER_SEED" != "$SEED" ]; then
    echo "ABORT: expected sampler seed $SEED but the server runs with seed ${SERVER_SEED:-unknown}. Start it with AGENT_SERVER_SEED=$SEED (start_agent_server.sh default), or run with AGENT_TRACE=1 to inject the seed per request, or AGENT_SEED= to skip this check."; exit 5
  fi
  [ -n "$EFFORT" ] && { echo "ABORT: AGENT_EFFORT needs AGENT_TRACE=1, or pass --chat-template-kwargs '{\"reasoning_effort\":\"$EFFORT\"}' to the server."; exit 5; }
fi

# 3. a private HERMES_HOME with the recorded config; stock skills from the pinned checkout plus the one
#    extra skill that was present when the demo was recorded (it is named in the system prompt)
HR="${AGENT_HOME_ROOT:-$DEMO_DIR/agent-runs}"; case "$HR" in /*) ;; *) HR="$PWD/$HR" ;; esac   # Hermes gets this path after a cd, so make it absolute here
HH="$HR/$NAME/home"; mkdir -p "$HH"; [ "$HH" = "$RUN/home" ] || ln -sfn "$HH" "$RUN/home"
[ -d "$DEMO_DIR/.hermes-agent/skills" ] && cp -a "$DEMO_DIR/.hermes-agent/skills" "$HH/skills"
[ -d "$A/skills" ] && cp -a "$A/skills"/. "$HH/skills"/
sed -e "s/^  default: .*/  default: ${MODEL}/" -e "s#base_url: http://localhost:[0-9]*/v1#base_url: ${BASE}#" -e "s/^  context_length: .*/  context_length: ${CTX}/" "$CFG" > "$HH/config.yaml"

# 4. workspace outside any git repo, at the recorded path when possible
ROOT="${AGENT_WORKSPACE_ROOT:-/private/tmp/collect}"
if ! mkdir -p "$ROOT" 2>/dev/null; then ROOT="${TMPDIR:-/tmp}/bonsai-agent"; echo "NOTE: cannot create the recorded workspace root; using $ROOT instead. The working directory is part of the system prompt, so this run is a different sample from the recording."; fi
case "$ROOT" in /*) ;; *) echo "ABORT: AGENT_WORKSPACE_ROOT must be an absolute path"; exit 1 ;; esac
WORK="$ROOT/$NAME/workspace"; [ -d "$ROOT/$NAME" ] && rm -rf -- "$ROOT/$NAME"; mkdir -p "$WORK"; ln -sfn "$WORK" "$RUN/workspace"
[ -n "$SEED_DIR" ] && cp -a "$SEED_DIR"/. "$WORK"/ && rm -f "$WORK/TASK.md"
cp "$TASK" "$WORK/TASK.md"
{ echo "model=$MODEL"; echo "upstream=$UP"; echo "base_url=$BASE"; echo "trace=$TRACE"; echo "seed=${SEED:-none} ($([ "$TRACE" = 1 ] && echo injected-per-request || echo server -s))"; echo "inject=$INJECT"; echo "config=$(basename "$CFG")"; echo "declared_ctx=$CTX"; echo "server_ctx_per_slot=$SERVED"; echo "task=$TASK"; [ -n "$SEED_DIR" ] && echo "seeded_from=$SEED_DIR"; echo "hermes=$(git -C "$DEMO_DIR/.hermes-agent" rev-parse --short HEAD 2>/dev/null)"; echo "hermes_home=$HH"; echo "workspace=$WORK"; echo "agent_browser=$( { [ -x "$DEMO_DIR/.agent-browser/node_modules/.bin/agent-browser" ] && "$DEMO_DIR/.agent-browser/node_modules/.bin/agent-browser" --version; } 2>/dev/null || echo unpinned-npx)"; echo "started=$(date -u +%FT%TZ)"; } > "$RUN/run.txt"

# 5. launch Hermes detached; the task text is read from a file so it never sits in argv. The pinned
#    agent-browser (install_hermes.sh) goes first on PATH so Hermes does not fall back to npx.
[ -x "$DEMO_DIR/.agent-browser/node_modules/.bin/agent-browser" ] && export PATH="$DEMO_DIR/.agent-browser/node_modules/.bin:$PATH"
cd "$WORK"
HERMES_HOME="$HH" "$VENV/bin/python" "$A/daemonize.py" "$RUN/hermes.pid" "$RUN/stdout.log" "$RUN/stderr.log" \
  "$VENV/bin/python" "$A/hermes_z.py" "$WORK/TASK.md" -m "$MODEL" --provider custom -t file,terminal,coding,web,search,browser --yolo --cli
# daemonize.py returns before Hermes execs: wait for the pid file, then require the process to survive a few seconds
HPID=""; for _ in $(seq 1 50); do [ -s "$RUN/hermes.pid" ] && HPID=$(cat "$RUN/hermes.pid") && break; sleep 0.2; done
sleep 4
if [ -z "$HPID" ] || ! kill -0 "$HPID" 2>/dev/null; then
  echo "ABORT: Hermes did not start or exited within 4 s. stderr tail:" >&2; tail -n 20 "$RUN/stderr.log" >&2 2>/dev/null; exit 4
fi
LAUNCHED=1; trap - EXIT
echo "launched: $NAME  (hermes pid $HPID${TRACE:+$([ "$TRACE" = 1 ] && echo ", proxy pid $(cat "$RUN/proxy.pid")")})"; sed 's/^/  /' "$RUN/run.txt"
if [ "$TRACE" = 1 ]; then echo "watch:  wc -l $RUN/wire.jsonl        deliverable: $RUN/workspace/"; else echo "watch:  tail -f $RUN/stdout.log        deliverable: $RUN/workspace/"; fi
echo "stop:   kill \$(cat $RUN/hermes.pid)$([ "$TRACE" = 1 ] && echo " \$(cat $RUN/proxy.pid)")"
