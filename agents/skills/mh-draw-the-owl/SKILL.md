---
name: mh-draw-the-owl
description: MANUAL-ONLY. Use only when the user explicitly invokes `mh-draw-the-owl` or asks to use the draw-the-owl workflow. Never auto-invoke it based on feature or diff size. Explore a feature end to end, then decompose oversized work into atomic, incremental, reviewable tasks.
---

# MH Draw the Owl

1. Draw the owl.
   - For implementation work, attempt the whole feature directly enough to expose the real seams.
   - For planning work, sketch the complete implementation shape and estimate its reviewable diff.
   - Treat this as reconnaissance, not an architecture that must be preserved.

2. Check reviewability.
   - Measure or estimate added plus deleted handwritten lines. Report generated, vendored, lockfile, formatting-only, and other mechanical churn separately.
   - At roughly 1,500 reviewable lines or less, stop decomposing and recommend normal review and iteration.
   - Above roughly 1,500 lines, stop expanding the solution and decompose it.

3. Decompose twice.
   - Derive a top-down split from the feature outcome, public boundaries, and architectural invariants.
   - Derive a bottom-up split from the attempted implementation and its actual dependencies.
   - Reconcile them around the general problem, not the accidental files, classes, or abstractions in the first attempt.

4. Produce slices.
   - Make each task independently correct, testable, reviewable, and preferably mergeable.
   - Give each task one behavioral outcome, dependencies, the smallest meaningful validation, and a parallelization wave.
   - Do not pretend a large change is decomposed by merely splitting it into commits.

5. Keep the human in the loop.
   - Ask for approval of UI/API boundaries, architectural invariants, and the task split before implementation or agent fan-out.
   - When execution is explicitly requested, implement independent slices in parallel where authorized and repeat the loop until the remaining feature is reviewable.
