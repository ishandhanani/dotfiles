## Claude Overlay

### Agent Identity

- If Claude-specific env vars are present, set `AGENT_KIND=claude`, `AGENT_HOME=${CLAUDE_HOME:-~/.claude}`, and `AGENT_INSTRUCTIONS=CLAUDE.md`.
- Claude project/session history commonly lives under `~/.claude/projects/`.

### Message And Log Shape

- Claude exports may use top-level `user`, `assistant`, `system`, or `progress` records rather than Codex `response_item` envelopes.
- Normalize those older shapes before comparing them with Codex sessions during scaffold review.
