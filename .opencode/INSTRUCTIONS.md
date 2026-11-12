# Bonsai local coding workflow

- Start with a brief progress update before lengthy investigation or edits.
- Search narrowly, then read only relevant files or ranges; avoid dumping the repository, generated files, or large command output into context.
- Prefer file/search/edit tools for source changes. Keep shell commands short and bounded; do not generate or rewrite large files through a shell command.
- For multi-step work, track the next concrete actions with todos. Make focused changes, then run the smallest relevant check.
- If a tool fails, inspect its result and change approach instead of repeating it. If generation or a command stalls, report what is blocked rather than waiting silently.
- Before context gets large, summarize the objective, decisions, changed files, checks, and exact next action so the session can be compacted or continued cleanly.
