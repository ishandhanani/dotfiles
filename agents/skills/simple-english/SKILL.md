---
name: simple-english
description: Write or audit text in Simple English or ASD-STE100. Run only when explicitly requested.
license: MIT
metadata:
  standard: ASD-STE100 Issue 9 (2025-01-15)
---

# Simple English

Use only when explicitly requested. Preserve technical meaning, uncertainty, facts, code, identifiers, commands, paths, and quoted errors. Do not apply controlled technical language to unrelated brand or marketing prose unless the user explicitly requests that transformation and accepts its tradeoffs.

- For clear technical prose without standards compliance, read [pragmatic.md](references/pragmatic.md).
- For STE/ASD-STE100 compliance or a rule-numbered audit, read [strict-rules.md](references/strict-rules.md). Classify passages as procedural or descriptive and apply their relevant rules. Do not cite rule numbers from memory. Full vocabulary compliance requires the official dictionary; this skill is an unofficial aid.
- For a specific output such as an incident report, runbook, or error message that needs adaptation, consult its section in [use-cases.md](references/use-cases.md).
- For a full strict audit, use [checklist.md](references/checklist.md). Report the actual rule, offending passage, and a compliant rewrite.

Finish with the requested text or audit, checking the relevant mode once. Do not rewrite protected technical strings to satisfy sentence or vocabulary rules.
