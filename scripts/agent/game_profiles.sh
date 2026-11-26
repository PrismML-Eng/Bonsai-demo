# Per-reply cap (llama-server -n) of the game server profiles. Sourced by scripts/start_agent_server.sh (which passes
# it as -n) and scripts/agent/run_agent_demo.sh (which writes it into the Hermes config and has the proxy send it as
# every request's max_tokens), so the two cannot drift. The runner needs its own copy because llama-server's /props
# does not report -n (it shows n_predict -1 whatever -n is), so the value cannot be read back from the server.
game_profile_n_predict() {
    case "$1" in
        game16) echo 49152 ;;
        game48) echo 65536 ;;
        *) return 1 ;;
    esac
}
