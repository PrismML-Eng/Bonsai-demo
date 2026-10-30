#!/bin/sh
# Sourced by start_openwebui.sh after common.sh. Keep MCP setup independently
# testable without loading model weights or starting Open WebUI.
#
# BONSAI_WEB_SEARCH=auto (default): use configured Brave, otherwise Parallel.
# parallel / brave / none explicitly select or disable general web search.
_ACCESS='"access_grants":[{"principal_type":"user","principal_id":"*","permission":"read"}]'
_MCP_SEARCH=""
BONSAI_MCP_IDS="huggingface,deepwiki"

if [ -z "${BRAVE_API_KEY:-}" ] && [ -f "$DEMO_DIR/.brave_key" ]; then
    BRAVE_API_KEY="$(tr -d '\r\n' < "$DEMO_DIR/.brave_key")"
fi
BONSAI_WEB_SEARCH="${BONSAI_WEB_SEARCH:-auto}"
case "$BONSAI_WEB_SEARCH" in
    auto)
        if [ -n "${BRAVE_API_KEY:-}" ]; then
            _web_search=brave
        else
            _web_search=parallel
        fi ;;
    parallel|brave|none) _web_search="$BONSAI_WEB_SEARCH" ;;
    *)
        err "Unknown BONSAI_WEB_SEARCH='$BONSAI_WEB_SEARCH'. Valid values: auto, parallel, brave, none"
        exit 1 ;;
esac

if [ "$_web_search" = "parallel" ]; then
    # The pinned Open WebUI MCP transport sends custom headers on discovery and
    # calls. Leave the optional session_id to the host/model, never a global ID.
    _MCP_SEARCH=',{"id":"parallel","type":"mcp","url":"https://search.parallel.ai/mcp","path":"","auth_type":"none","key":"","headers":{"User-Agent":"BonsaiDemo/0.1.0"},"config":{"enable":true,'$_ACCESS'},"info":{"id":"parallel","name":"Parallel Search","description":"Search the public web and fetch pages, no API key required"}}'
    BONSAI_MCP_IDS="$BONSAI_MCP_IDS,parallel"
elif [ "$_web_search" = "brave" ]; then
    if [ -z "${BRAVE_API_KEY:-}" ]; then
        warn "BONSAI_WEB_SEARCH=brave needs BRAVE_API_KEY or .brave_key - web search is unavailable."
    elif command -v brave-search-mcp-server >/dev/null 2>&1; then
        export BRAVE_API_KEY
        step "Starting Brave Search MCP bridge on 127.0.0.1:8001 ..."
        # Keep Brave's web/news/summarizer tools; its full schema is ~29k tokens.
        _brave_tools="${BONSAI_BRAVE_TOOLS:-brave_web_search brave_news_search brave_summarizer}"
        # shellcheck disable=SC2086
        brave-search-mcp-server --transport http --host 127.0.0.1 --port 8001 \
            --enabled-tools $_brave_tools > "$_BRAVE_LOG" 2>&1 &
        BG_PIDS="$BG_PIDS $!"
        _MCP_SEARCH=',{"id":"brave","type":"mcp","url":"http://127.0.0.1:8001/mcp","path":"","auth_type":"none","key":"","config":{"enable":true,'$_ACCESS'},"info":{"id":"brave","name":"Brave Search","description":"Web search via Brave"}}'
        BONSAI_MCP_IDS="$BONSAI_MCP_IDS,brave"
    else
        # A configured provider stays selected even when unavailable.
        warn "BRAVE_API_KEY is set but brave-search-mcp-server is not installed - skipping Brave MCP."
    fi
fi
export TOOL_SERVER_CONNECTIONS='[
  {"id":"huggingface","type":"mcp","url":"https://huggingface.co/mcp","path":"","auth_type":"none","key":"","config":{"enable":true,'$_ACCESS'},"info":{"id":"huggingface","name":"Hugging Face","description":"Search models, datasets and Spaces on the HF Hub"}},
  {"id":"deepwiki","type":"mcp","url":"https://mcp.deepwiki.com/mcp","path":"","auth_type":"none","key":"","config":{"enable":true,'$_ACCESS'},"info":{"id":"deepwiki","name":"DeepWiki","description":"Ask questions about any public GitHub repository"}}'"$_MCP_SEARCH"'
]'
export BONSAI_MCP_IDS
