## Codex Overlay

### Agent Identity

- If `CODEX_THREAD_ID` or other `CODEX_*` env vars are present, set `AGENT_KIND=codex`, `AGENT_HOME=${CODEX_HOME:-~/.codex}`, and `AGENT_INSTRUCTIONS=CLAUDE.md`.
- Maintain `AGENTS.md -> CLAUDE.md` in the Codex home so Codex-compatible repo entrypoints resolve cleanly.

### Message And Log Shape

- Codex session logs are usually under `~/.codex/sessions/` and use `response_item.payload`.
- Commentary and final responses are distinct phases on assistant messages; preserve both when reviewing transcripts.
- Tool calls are encoded as `function_call` records with JSON `arguments`.
