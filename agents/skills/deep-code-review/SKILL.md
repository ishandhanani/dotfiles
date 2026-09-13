---
name: deep-code-review
description: Perform an adversarial review of correctness, performance, and maintainability. Use for deep or strict code reviews.
---

# Deep Code Review

Adapted from Cursor's `thermo-nuclear-code-quality-review` in `cursor-team-kit` at `b8f2564c2e8da66b331c1dd63c2a2925d6739961`.

Perform the requested strict review of changed code and its affected contracts. When no target is supplied, inspect the current branch against its actual base. A finding needs a concrete causal path to material correctness, performance, or maintainability impact. Preserve security/data-safety concerns; skip unsupported hypothetical inputs and cosmetic nits.

Challenge the overall approach, trace changed contracts through consumers, and inspect production failure paths that local tests may miss. Compare hot-path work before/after: allocations, copies, synchronization, serialization, repeated scans, batching, and resource bounds. Use a representative measurement when available; distinguish measured results from a code-based causal argument.

For structural or performance-heavy changes, read [quality.md](references/quality.md). File length is a navigation signal, not a blocker by itself. Prefer simplifications that remove actual complexity; do not demand an abstraction or redesign solely to satisfy a checklist. Explicitly requested style or architectural redesign feedback can be reported separately from defects.

Use an independent subagent or `phone-a-friend` only when an unresolved independent question would benefit or the user requests it, and delegation is permitted. Give raw artifacts and constraints without seeding your conclusion. Verify every material claim locally; agreement is not evidence by itself. Missing delegation does not prevent completing a local review.

Finish after the relevant surfaces and candidate findings are checked. Return severity-ordered findings with exact code locations, triggers, consequences, evidence, and smallest remedies, then validation limitations. Do not keep repeating passes to produce more comments once the requested scope is exhausted.
