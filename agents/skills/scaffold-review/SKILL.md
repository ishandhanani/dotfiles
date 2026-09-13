---
name: scaffold-review
description: Audit agent instructions and skills for conflicts, stale workflows, and unnecessary context. Inspect session history when behavior evidence is needed.
---

# Scaffold Review

Audit the requested instruction surface and improve it within the user's scope. Preserve operational knowledge and explicit preferences; remove contradictions, stale assumptions, repeated rules, and irrelevant loading.

## Select the evidence

- For a static skill/instruction audit, inspect discovery descriptions, root instructions, linked references, scripts, and relevant host policies. Measure root and transitive loading separately. Do not read session history merely because this skill is selected.
- For questions about observed behavior, corrections, or usage, read [history.md](references/history.md) and run the bundled extractor. Check coverage before interpreting counts. Use compact findings rather than raw transcripts.
- For a proposed behavior change that is complex or consequential, use an independent forward test when delegation is permitted. Give a realistic request and minimum raw fixtures without the intended answer; validate outcomes in isolation.

## Findings and action

For each material finding, give the source location, evidence, current behavior, exact replacement or patch, confidence, and a forward test. Distinguish a demonstrated conflict from a preference change or a missing observation. Shorter instructions are not automatically better; preserve non-obvious invariants.

For an audit-only request, return concrete proposals. When the user requests fixes, apply the authorized scope and validate it without another blanket approval gate. Ask only for a material unresolved scope decision. Continue independent work while resolving it.

Zero observed reads means “not observed in this sample,” not “unused.” Retire a skill only with corroborating evidence that its capability is obsolete or unwanted. Do not create speculative skills or install-profile mechanisms solely to reduce counts. Provider-managed cache files are not durable edit targets; record any upstream recommendation separately.

## Completion

Verify references, metadata, and consistency of changed workflows. Run meaningful tests for changed scripts and fixture-based checks for fragile recipes. For wording-only edits, inspect representative action/draft requests and relevant boundaries rather than writing tests that match prose.

Record applied, deferred, or rejected findings through [ledger.md](references/ledger.md), preserving previous entries. Use `memory-log` for meaningful results. Finish with changes, validation, remaining limitations, and the requested deliverable.
