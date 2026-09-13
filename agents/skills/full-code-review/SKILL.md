---
name: full-code-review
description: Perform a comprehensive code review with general and deep review passes.
---

# Full Code Review

Perform both general and deep review perspectives on the same explicit target. Set one admission bar first: every finding needs a supported trigger, affected path, and material correctness, safety, performance, or maintainability consequence. Do not recommend defensive code solely for undocumented hypothetical inputs.

1. Use the compact [general review entrypoint](../general-review/SKILL.md) for scope, semantic/concurrency/recovery coverage, and candidate validation.
2. Use the compact [deep review entrypoint](../deep-code-review/SKILL.md) for cross-boundary failure, hot-path cost, and structural simplification.
3. Load their detailed references only for relevant surfaces. Reuse evidence and completed checks; the second perspective need not repeat identical work or require an external agent.
4. Independently verify and deduplicate candidates, then return one severity-ordered report with exact locations and validation limits.

An explicit exhaustive review keeps the requested depth. File length and cosmetic preferences alone are not defects. Stop when the requested surfaces and material candidates have been checked.
