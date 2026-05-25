# AGENTS.md - Bonsai-demo


## GitHub / OpenSpec / LLM Wiki Standard

Treat Karpathy's LLM Wiki pattern as governing law for durable agent memory: https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f

- `docs/wiki/` is the durable project memory for architecture, decisions, gotchas, and onboarding.
- `AGENTS.md` is the agent instruction schema.
- `openspec/` is the structured change/spec layer.
- Start non-trivial work with `openspec/changes/<change-id>/proposal.md`.
- Track implementation in `openspec/changes/<change-id>/tasks.md`.
- Update `docs/wiki/` whenever work reveals durable repo knowledge future agents need.
- Keep changes surgical, simple, and verified by repo-native checks.
