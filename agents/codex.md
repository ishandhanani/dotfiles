## Codex Overlay

### Agent Identity

- If `CODEX_THREAD_ID` or other `CODEX_*` env vars are present, set `AGENT_KIND=codex`, `AGENT_HOME=${CODEX_HOME:-~/.codex}`, and `AGENT_INSTRUCTIONS=CLAUDE.md`.
- Maintain `AGENTS.md -> CLAUDE.md` in the Codex home so Codex-compatible repo entrypoints resolve cleanly.

### Repo Contract

- If the active repo has a project-level `CLAUDE.md` or `AGENTS.md`, follow that contract before applying older personal memory-layout assumptions.
- For `~/memory`, treat the repo-local contract as canonical: `INDEX.md` is the live brief, chronology stays in `worklogs/`, and evidence belongs in `experiments/`.

### Message And Log Shape

- Codex session logs are usually under `~/.codex/sessions/` and use `response_item.payload`.
- Commentary and final responses are distinct phases on assistant messages; preserve both when reviewing transcripts.
- Tool calls are encoded as `function_call` records with JSON `arguments`.
