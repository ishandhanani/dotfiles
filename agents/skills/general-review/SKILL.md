---
name: general-review
description: Review a design, document, or code change for material correctness, scope, and performance issues.
---

# General Review

Review the artifact the user named: a design, document, code surface, or explicit diff. Do not reconstruct scope from a long conversation or collect Git metadata for an ordinary document review.

## Finding bar

Focus on issues introduced or materially amplified by the proposed change. A finding needs a supported precondition, affected path, and meaningful correctness, performance, safety, or maintainability consequence. Trace contracts through callers and consumers. For a design, name the concrete scenario that fails and its consequence. Skip speculative defensive code and cosmetic preferences unless the user requests a style review.

Challenge whether the proposal solves the stated problem, owns state in the right layer, survives partial failure, and has validation that can detect its risks. Prefer the smallest correction that preserves the intended contract. Mark inherited issues explicitly and include them only when severe or materially affected by this change.

## Choose the review surfaces

Use [risk-buckets.md](references/risk-buckets.md) for detailed checks when the target contains relevant semantics, in-process concurrency, distributed recovery, architecture, or hot-path performance. Read the applicable sections; do not dispatch a pass just because a bucket exists.

For independent surfaces that benefit from parallel inspection, use bounded subagents when delegation is permitted. Give each its target, relevant evidence, one question, and an early-exit condition. Evaluate small targets locally. The main reviewer independently checks material candidates and deduplicates the result; extra agents are not a completion requirement.

Finish when relevant surfaces and candidate findings have been checked. Return severity-ordered findings with exact locations, causal evidence, and smallest remedies, followed by meaningful validation limits. If none survive, say so. An explicit exhaustive request retains its requested scope, without manufacturing a quota of issues.
