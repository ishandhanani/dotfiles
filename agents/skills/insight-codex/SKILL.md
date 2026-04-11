---
name: insight-codex
description: Generate a shareable HTML usage report from local Codex session logs. Use when the user asks for an insights page like Claude Code's `/insights`, wants a summary of how they use Codex over time, wants session/tool/git/subagent/friction metrics, or wants machine-readable per-session metadata derived from the active Codex home.
---

# Insight Codex

Generate a local-only usage report from Codex JSONL session logs. The main artifact is `"$CODEX_HOME/usage-data/report.html"`, with per-session JSON written alongside it.

## Workflow

1. Resolve `CODEX_HOME` from the environment or pass `--codex-home` explicitly.
2. Run the extractor first:
   `python3 "${CODEX_HOME:?}/skills/insight-codex/scripts/generate_report.py" --extract-only`
3. Read `analysis-input.json` plus only the specific `facets/*.json` or `session-meta/*.json` files you need for evidence. Do not read the full session JSONL corpus directly once the extracted evidence exists.
4. Perform a real Codex synthesis pass in-session. Write `"$CODEX_HOME/usage-data/synthesis.json"` with evidence-backed content for:
   - `at_a_glance`
   - `usage_paragraphs`
   - `big_wins`
   - `friction_sections`
   - `agent_md_additions`
   - `feature_cards`
   - `pattern_cards`
   - `horizon_cards`
   - `feedback_cards`
5. Render the final report with:
   `python3 "${CODEX_HOME:?}/skills/insight-codex/scripts/generate_report.py" --synthesis-file "${CODEX_HOME:?}/usage-data/synthesis.json"`
6. Return the path to `report.html` and summarize the most useful numbers.

## Commands

```bash
python3 "${CODEX_HOME:?}/skills/insight-codex/scripts/generate_report.py" --extract-only
python3 "${CODEX_HOME:?}/skills/insight-codex/scripts/generate_report.py" --extract-only --days 30
python3 "${CODEX_HOME:?}/skills/insight-codex/scripts/generate_report.py" --extract-only --limit 20
python3 "${CODEX_HOME:?}/skills/insight-codex/scripts/generate_report.py" --synthesis-file "${CODEX_HOME:?}/usage-data/synthesis.json"
python3 "${CODEX_HOME:?}/skills/insight-codex/scripts/generate_report.py" --codex-home "$CODEX_HOME" --output-dir /tmp/codex-insights --extract-only
```

## Outputs

- `report.html`: static shareable report
- `analysis-input.json`: compact evidence bundle for the Codex synthesis pass
- `synthesis.json`: Codex-authored narrative and recommendation layer
- `session-meta/*.json`: per-session counters and metadata
- `facets/*.json`: lighter-weight per-session summaries for downstream tooling
- `manifest.json`: top-level totals for the run

## Notes

- Use only local files under the resolved Codex home; do not browse.
- The extractor is deterministic. The final report should not rely only on those heuristics; Codex should analyze the extracted evidence and write the section content in `synthesis.json`.
- Keep the HTML structure fixed and the evidence grounded, but treat the interpretation-heavy sections as an actual synthesis task rather than a pure template fill.
- Correction-style user turns are heuristic. Treat them as a friction indicator, not ground truth.
