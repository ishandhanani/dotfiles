---
name: full-code-review
description: Run general-review, deep-code-review, and an mh-draw-the-owl reviewability pass as one consolidated review. Use when the user asks for a full code review, a combined general and deep review, or a comprehensive review of code, a diff, branch, or pull request.
---

# Full Code Review

## Finding threshold — set before every pass

Establish this bar before invoking any child skill: include a finding only when it gives a concrete, in-scope failure case — precondition/input, affected code path, and outcome (wrong behavior, crash, data loss, security-boundary violation, or measurable regression). Prefer a reproduction; otherwise trace the path and show why its precondition is supported.

For example, “A zero-length batch reaches this division and returns 500” is a finding. “A future caller might pass an undocumented shape” is not one without an in-scope caller or contract. Skip speculative edge cases, style preferences, unsupported inputs, and alternative designs; do not recommend defensive code solely for them. Retain findings about trust-boundary validation, data safety, or security.

Run all three existing skills against the same target:

1. Read and follow `../general-review/SKILL.md` completely, applying the finding threshold above.
2. Read and follow `../deep-code-review/SKILL.md` completely, applying the finding threshold above.
3. Read and follow `../mh-draw-the-owl/SKILL.md` completely as a read-only reviewability pass. Measure the handwritten diff and recommend decomposition when it exceeds the skill's threshold. Do not modify the target.
4. Use the same scope and evidence for all three reviews.
5. Verify and deduplicate their findings, then return one severity-ordered report.

This sets the admission bar for the consolidated report; do not copy, weaken, or replace any child skill's rubric.
