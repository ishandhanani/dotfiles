---
name: deep-code-review
description: Run a deep, adversarial code review focused on correctness, hot-path performance, maintainability, abstraction quality, and codebase health. Use when the user asks for deep-code-review, a deep or overall code review, a thermo-nuclear or thermonuclear review, a code-judo review, a strict performance review, or an especially harsh maintainability audit. Do not use for ordinary bug-focused review unless the user asks for this stricter rubric.
---

# Deep Code Review

Adapted from Cursor's `thermo-nuclear-code-quality-review` agent and skill in `cursor-team-kit` at commit `b8f2564c2e8da66b331c1dd63c2a2925d6739961`.

Use this skill for an unusually strict review focused on correctness, performance, implementation quality, maintainability, abstraction quality, and codebase health. Review adversarially: challenge the premise, trace failure modes across boundaries, and actively look for behavior-preserving changes that make the implementation smaller, faster, more direct, and easier to reason about.

## Workflow

1. Establish the review target:
   - If the user provides a diff or files, review only that scope.
   - Otherwise inspect the current branch against the likely base, usually `main`, using `git diff --stat`, `git diff`, and changed-file contents.
   - Check file sizes for changed files so crossings around 1000 lines are visible.
2. Apply the rubric below only to what the diff and surrounding contents support. Trace cross-file impact when module boundaries are touched.
3. Do not spawn nested agents unless the user explicitly asks for subagents or parallel agent work.
4. Report findings first, ordered by severity. Use `file_path:line_number` references where possible.
5. Skip cosmetic nits when structural issues exist. Prefer a small number of high-conviction findings over a long list of minor comments.

## Core Prompt

Perform a deep, adversarial code quality audit of the current branch's changes. Rethink how to structure or implement the changes to meaningfully improve correctness, performance, and code quality without changing intended behavior. Improve abstractions, modularity, succinctness, and legibility. Reduce spaghetti code. Be ambitious when there is a clear path to a better structure.

## Adversarial Pass

Challenge the change as a whole before reviewing individual lines:

- Ask whether the implementation solves the actual problem in the owning layer or merely patches a symptom.
- Find ways tests can pass while production behavior still fails, including defaults, error paths, partial rollout, rollback, recovery, and cross-component interactions.
- Identify hidden assumptions about ordering, ownership, lifecycle, compatibility, input shape, scale, and failure isolation.
- Trace changed contracts through callers and consumers rather than trusting the local diff.
- Compare against a materially simpler or safer direction when one is concrete.
- Report only adversarial concerns with a plausible causal path; do not manufacture hypothetical failures.

## Performance Pass

Trace each changed hot path end to end and compare the work before and after the change:

- Check allocations, cloning, boxing, dynamic dispatch, collection materialization, formatting, serialization, and copies.
- Check extra scans, branches, lookups, call depth, synchronization, lock scope, atomics, syscalls, IPC, and retries.
- Check whether the change loses batching, locality, cache friendliness, short-circuiting, boundedness, or backpressure.
- Check CPU, memory, latency, throughput, file-descriptor, task, queue, and connection growth at expected production scale.
- Distinguish hot-path cost from irrelevant cold-path micro-optimization.
- Use existing benchmarks or profiles when practical. Otherwise require a precise causal argument and the smallest measurement that would prove or disprove the risk.

## Non-Negotiable Standards

0. Be ambitious about structural simplification.
   - Do not stop at "this could be cleaner."
   - Look for opportunities to reframe the change so whole branches, helpers, modes, conditionals, or layers disappear.
   - Prefer the solution that makes the code feel inevitable in hindsight.
   - Assume there may be a code-judo move: a reorganization that uses the existing architecture more effectively and makes the change simpler.
   - If complexity can be deleted rather than rearranged, push hard for that path.

1. Do not let a PR push a file from under 1000 lines to over 1000 lines without a strong reason.
   - Treat this as a serious maintainability smell by default.
   - Prefer extracting helpers, subcomponents, modules, or local abstractions.
   - If the diff crosses the threshold, explicitly ask whether the code should be decomposed first.
   - Waive this only when there is a compelling structural reason and the resulting file is still clearly organized.

2. Do not allow random spaghetti growth in existing code.
   - Be suspicious of new ad-hoc conditionals, scattered special cases, or one-off branches inserted into unrelated flows.
   - Treat weird if-statements in random places as a design problem, not a style nit.
   - Prefer dedicated abstractions, helpers, state machines, policy objects, or separate modules.
   - Call out changes that make surrounding code harder to reason about even when they work.

3. Bias toward cleaning the design, not merely accepting working code.
   - If behavior can stay the same while structure becomes meaningfully cleaner, push for the cleaner version.
   - Do not rubber-stamp working implementations that leave the codebase messier.
   - Prefer simplifications that remove moving pieces over refactors that spread the same complexity around.

4. Prefer direct, boring, maintainable code over hacky or magical code.
   - Treat brittle, ad-hoc, or magic behavior as a code-quality problem.
   - Be skeptical of generic mechanisms that hide simple data-shape assumptions.
   - Flag thin abstractions, identity wrappers, and pass-through helpers that add indirection without clarity.

5. Push hard on type and boundary cleanliness when they affect maintainability.
   - Question unnecessary optionality, `unknown`, `any`, or cast-heavy code when a clearer boundary could exist.
   - Prefer explicit typed models or shared contracts over loosely shaped ad-hoc objects.
   - If a branch relies on silent fallback to paper over an unclear invariant, ask whether the boundary should be explicit.

6. Keep logic in the canonical layer and reuse existing helpers.
   - Call out feature logic leaking into shared paths or implementation details leaking through APIs.
   - Prefer canonical utilities and helpers over bespoke one-offs.
   - Push code toward the package, service, or module that already owns the concept.

7. Treat unnecessary sequential orchestration and non-atomic updates as design smells when the cleaner structure is obvious.
   - If independent work is serialized for no good reason, ask whether the flow should run in parallel.
   - If related updates can leave state half-applied, push for a more atomic structure.
   - Do not over-index on micro-optimizations, but flag avoidable orchestration complexity that makes the implementation brittle.

## Review Questions

For every meaningful change, ask:

- Is there a code-judo move that would make this dramatically simpler?
- Can this change be reframed so fewer concepts, branches, or helper layers are needed?
- Does this improve or worsen the local architecture?
- Did the diff add branching complexity where a better abstraction should exist?
- Did a cohesive module become more coupled, more stateful, or harder to scan?
- Is this logic living in the right file and layer?
- Did this change enlarge a file or component past a healthy size boundary?
- Are repeated conditionals signaling a missing model or helper?
- Is the implementation direct and legible, or does it rely on special cases and incidental control flow?
- Is this abstraction earning its keep, or is it just a wrapper?
- Did the diff introduce casts, optionality, or ad-hoc object shapes that obscure the invariant?
- Is this logic in the canonical layer, or did details leak across a boundary?
- Is this orchestration more sequential or less atomic than it needs to be?
- Can the change pass its tests while failing under partial rollout, recovery, concurrency, or production-scale inputs?
- What new work occurs per request, token, item, iteration, or connection on the hot path?
- Did the change add allocations, copies, dynamic dispatch, synchronization, serialization, or resource growth without evidence that the cost is acceptable?

## Flag Aggressively

Escalate findings for:

- Complicated implementations where cleaner reframing could delete whole categories of complexity.
- Refactors that move code around but fail to reduce the concepts a reader must hold in their head.
- Files crossing 1000 lines due to the change, especially when new code could be split out.
- New conditionals bolted onto unrelated code paths.
- One-off booleans, nullable modes, or flags that complicate existing control flow.
- Feature-specific logic leaking into general-purpose modules.
- Generic magic handling that hides simple structure.
- Thin wrappers or identity abstractions that add indirection without simplifying anything.
- Unnecessary casts, `any`, `unknown`, or optional params that muddy the contract.
- Copy-pasted logic instead of extracted helpers.
- Narrow edge-case handling in the middle of already busy functions.
- Refactors that pass tests but make the code less modular or readable.
- Temporary branching that is likely to become permanent debt.
- Bespoke helpers where a canonical utility already exists.
- Logic added in the wrong layer or package.
- Sequential async flow where independent work could stay simpler with parallel execution.
- Partial-update logic that leaves state less atomic than necessary.
- Locally correct changes that break callers, consumers, rollout, recovery, or failure isolation.
- New hot-path allocations, copies, materialization, dynamic dispatch, synchronization, IPC, or repeated scans without a demonstrated need.
- Performance claims supported only by intuition when an existing benchmark or targeted measurement is available.

## Preferred Remedies

When identifying a code-quality problem, prefer suggestions like:

- Delete a layer of indirection rather than polishing it.
- Reframe the state model so conditionals disappear.
- Change the ownership boundary so the feature becomes a natural extension of an existing abstraction.
- Turn special-case logic into a simpler default flow with fewer exceptions.
- Extract a helper or pure function.
- Split a large file into smaller focused modules.
- Move feature-specific logic behind a dedicated abstraction.
- Replace condition chains with a typed model or explicit dispatcher.
- Separate orchestration from business logic.
- Collapse duplicate branches into one clearer flow.
- Delete wrappers that do not clarify the API.
- Reuse the existing canonical helper instead of introducing a near-duplicate.
- Make type boundaries more explicit so control flow gets simpler.
- Move logic to the package, module, or layer that owns the concept.
- Parallelize independent work when that also simplifies orchestration.
- Restructure related updates into a more atomic flow when partial state is hard to reason about.
- Keep hot-path data borrowed, statically dispatched, batched, and allocation-free where the existing design allows it.
- Preserve bounded queues and backpressure instead of hiding overload behind buffering or retries.
- Use the repository's existing benchmark or profiler to measure the smallest representative path.

Do not be satisfied with rename-level feedback when the real issue is structural. Do not be satisfied with a cleaner version of the same messy idea if there is a plausible path to a much simpler idea.

## Tone

Be direct, serious, and demanding about quality. Do not be rude, but do not soften major maintainability issues into mild suggestions. If the code makes the codebase messier, say so clearly. If the implementation missed an opportunity for major simplification, say that clearly.

Useful comment shapes:

- `this pushes the file past 1k lines. can we decompose this first?`
- `this adds another special-case branch into an already busy flow. can we move this behind its own abstraction?`
- `this works, but it makes the surrounding code more spaghetti. let's keep the behavior and restructure the implementation.`
- `this feels like feature logic leaking into a shared path. can we isolate it?`
- `this abstraction seems unnecessary. can we keep the direct flow?`
- `why does this need a cast or optional here? can we make the boundary explicit instead?`
- `this looks like a bespoke helper for something we already have elsewhere. can we reuse the canonical one?`
- `i think there's a code-judo move here that makes this much simpler. can we reframe this so these branches disappear?`
- `this refactor moves complexity around, but doesn't delete it. is there a way to make the model itself simpler?`

## Output Order

Prioritize findings in this order:

1. Adversarial correctness, contract, rollout, and recovery failures
2. Hot-path performance and resource regressions
3. Structural code-quality regressions
4. Missed opportunities for dramatic simplification or code-judo restructuring
5. Spaghetti and branching complexity increases
6. Boundary, abstraction, and type-contract problems that make code harder to reason about
7. File-size, modularity, decomposition, and maintainability concerns

## Approval Bar

Do not approve merely because behavior appears correct. Approval requires:

- no clear structural regression
- no obvious missed opportunity for a dramatically simpler implementation
- no unjustified file-size explosion
- no obvious spaghetti growth from special-case branching
- no hacky or magical abstraction that makes code harder to reason about
- no unnecessary wrapper, cast, or optionality churn that obscures the real design
- no clear architecture-boundary leak or avoidable canonical-helper duplication
- no missed opportunity for an obvious decomposition that would materially improve maintainability
- no material cross-boundary failure mode hidden by locally passing tests
- no unjustified hot-path allocation, copying, synchronization, serialization, or resource growth
- no performance-sensitive change left unmeasured when a targeted benchmark is practical

Treat these as presumptive blockers unless the author can justify them clearly:

- preserving incidental complexity when a plausible code-judo move would delete it
- pushing a file from below 1000 lines to above 1000 lines
- adding ad-hoc branching that tangles an existing flow
- solving a local problem by scattering feature checks across shared code
- adding unnecessary abstraction, wrapper, or cast-heavy contracts
- duplicating an existing helper or putting logic in the wrong layer when there is a clear canonical home

If those conditions are not met, leave explicit, actionable feedback and push for a cleaner decomposition.
