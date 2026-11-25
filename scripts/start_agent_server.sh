#!/bin/sh
# Start llama-server with the "agent profile": the settings the Bonsai 2 agentic demo (AGENT-DEMO.md)
# was recorded with. Thin wrapper over start_llama_server.sh; every flag below is passed through to
# llama-server, so anything you add on the command line is appended after these.
#
#   ./scripts/start_agent_server.sh                 # exact video settings (131072 ctx, 16384 thinking budget)
#   BONSAI_CTX=262144 ./scripts/start_agent_server.sh   # recommended for long agent runs (see AGENT-DEMO.md)
#   AGENT_REASONING_BUDGET=20480 ./scripts/start_agent_server.sh
#   AGENT_MODEL_ALIAS=my-bonsai ./scripts/start_agent_server.sh   # model id (default = the recorded one)
#   AGENT_PROFILE=game16 ./scripts/start_agent_server.sh   # the game setting (demos/games/): 262144 ctx,
#                                                          # 16384 thinking budget, 49152 tokens per reply (-n)
#   AGENT_PROFILE=game48 ./scripts/start_agent_server.sh   # "48k": 262144 ctx, 49152 thinking budget, 65536 per reply
#   (both game profiles use min-p 0. AGENT_N_PREDICT=N replaces the profile's -n, e.g. 32768 for the run-4 setting of
#   Neon Racer; demos/games/README.md lists the overrides per published game.)
#   AGENT_PROFILE=game16 AGENT_MTP=1 ./scripts/start_agent_server.sh   # + the GGUF's built-in MTP draft head
#
# MTP draft head (game profiles): off by default, AGENT_MTP=1 turns it on. It is start_llama_server.sh's
# BONSAI_SPECULATIVE=1 (--spec-type draft-mtp; needs the *-mtp.gguf the demo downloads, see SPECULATIVE.md): faster
# decode on CUDA/ROCm, the same sampling settings. Without a profile the launcher's own default applies (on for
# CUDA/ROCm/Metal, see SPECULATIVE.md); AGENT_MTP=0|1 sets it either way.
#
# What the profile pins and why:
#   --min-p 0.05                 the model card's thinking-mode value (AGENT_MIN_P). The skateboard rounds were
#                                recorded with 0 before the card changed; the worldcup example uses 0.05
#   --temp 1.0 --top-p 0.95 --top-k 20   model card; start_llama_server.sh sets these for Bonsai 2
#   presence 0 / repeat 1.0      model card values == llama.cpp defaults, nothing to pass
#   --reasoning-format deepseek  thinking is returned in message.reasoning_content and never echoed
#                                back into the conversation by the agent (the fork's default "auto"
#                                does the same under --jinja; pinned so the transcript is explicit)
#   --reasoning-budget N         server-side cap on thinking tokens per turn; 16384 is the demo value
#   --parallel 1                 one slot: the whole context belongs to the one agent conversation
#   -s 42                        fixed sampler seed (AGENT_SERVER_SEED; empty = none). With one slot this is the
#                                same as seeding every request; the demo was recorded with seed 42. A fixed seed makes
#                                an identical request return the same reply, so in game mode (empty replies are
#                                resampled with the identical request) the proxy gives a repeated request a new seed
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
: "${BONSAI_MODEL:=27B}"
if [ -z "${BONSAI_FAMILY:-}" ]; then
    case "$BONSAI_MODEL" in 27B) BONSAI_FAMILY=bonsai25 ;; *) BONSAI_FAMILY=bonsai2 ;; esac
fi
export BONSAI_FAMILY BONSAI_MODEL
NPRED_FLAG=""
case "${AGENT_PROFILE:-}" in
    "") ;;
    game16) : "${BONSAI_CTX:=262144}"; : "${AGENT_REASONING_BUDGET:=16384}"; : "${AGENT_MIN_P:=0}"; : "${AGENT_N_PREDICT:=49152}"; : "${AGENT_MTP:=0}" ;;
    game48) : "${BONSAI_CTX:=262144}"; : "${AGENT_REASONING_BUDGET:=49152}"; : "${AGENT_MIN_P:=0}"; : "${AGENT_N_PREDICT:=65536}"; : "${AGENT_MTP:=0}" ;;
    *) echo "unknown AGENT_PROFILE '$AGENT_PROFILE' (game16 | game48)"; exit 1 ;;
esac
if [ -n "${AGENT_N_PREDICT:-}" ]; then
    case "$AGENT_N_PREDICT" in *[!0-9]*) echo "AGENT_N_PREDICT must be a positive integer"; exit 1 ;; esac
    NPRED_FLAG="-n $AGENT_N_PREDICT"
fi
case "${AGENT_MTP:-}" in
    "") ;;
    0|1) BONSAI_SPECULATIVE="$AGENT_MTP"; export BONSAI_SPECULATIVE ;;
    *) echo "AGENT_MTP must be 0 or 1"; exit 1 ;;
esac
export BONSAI_CTX="${BONSAI_CTX:-131072}"
BUDGET="${AGENT_REASONING_BUDGET:-16384}"
AGENT_SERVER_SEED="${AGENT_SERVER_SEED-42}"; SEED_FLAG=""; [ -n "$AGENT_SERVER_SEED" ] && SEED_FLAG="-s $AGENT_SERVER_SEED"
# the model id is part of the agent's system prompt; the recorded one is the default so a rerun matches
_alias_default="bonsai25-27b-v1"; _minp_default=0
if [ "$BONSAI_FAMILY" = "bonsai2" ]; then _alias_default="bonsai2-27b-pq2-v16_2"; _minp_default=0.05; fi
ALIAS="${AGENT_MODEL_ALIAS:-$_alias_default}"
MINP="${AGENT_MIN_P:-$_minp_default}"
echo "=== agent profile${AGENT_PROFILE:+ $AGENT_PROFILE}: ctx $BONSAI_CTX, thinking budget $BUDGET,${NPRED_FLAG:+ $NPRED_FLAG per reply,} min-p $MINP, reasoning-format deepseek, 1 slot${AGENT_SERVER_SEED:+, seed $AGENT_SERVER_SEED}${AGENT_MTP:+, MTP draft head $([ "$AGENT_MTP" = 1 ] && echo on || echo off)} ==="
# shellcheck disable=SC2086
exec sh "$SCRIPT_DIR/start_llama_server.sh" \
    --min-p "$MINP" --reasoning-format deepseek --reasoning-budget "$BUDGET" --parallel 1 --alias "$ALIAS" $SEED_FLAG $NPRED_FLAG "$@"
