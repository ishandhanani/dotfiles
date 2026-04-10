---
name: insight-codex
description: Generate a shareable HTML usage report from local Codex session logs. Use when the user asks for an insights page like Claude Code's `/insights`, wants a summary of how they use Codex over time, wants session/tool/git/subagent/friction metrics, or wants machine-readable per-session metadata derived from `~/.codex/sessions`.
---

# Insight Codex

Generate a local-only usage report from Codex JSONL session logs. The main artifact is `"$CODEX_HOME/usage-data/report.html"`, with per-session JSON written alongside it.

## Workflow

1. Resolve `CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"`.
2. Run the generator script with defaults unless the user asks for a narrower slice.
3. Return the path to `report.html` and summarize the most useful numbers.
4. If the user wants a smaller window, rerun with `--days` or `--limit`.

## Commands

```bash
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
python3 "$CODEX_HOME/skills/insight-codex/scripts/generate_report.py"
python3 "$CODEX_HOME/skills/insight-codex/scripts/generate_report.py" --days 30
python3 "$CODEX_HOME/skills/insight-codex/scripts/generate_report.py" --limit 20
python3 "$CODEX_HOME/skills/insight-codex/scripts/generate_report.py" --output-dir /tmp/codex-insights
```

## Outputs

- `report.html`: static shareable report
- `session-meta/*.json`: per-session counters and metadata
- `facets/*.json`: lighter-weight per-session summaries for downstream tooling
- `manifest.json`: top-level totals for the run

## Notes

- Use only local files under `"$CODEX_HOME/sessions"`; do not browse.
- The report is intentionally operational rather than speculative. It summarizes stable signals from message phases, function calls, command prefixes, token counters, and non-zero exit codes.
- Correction-style user turns are heuristic. Treat them as a friction indicator, not ground truth.
