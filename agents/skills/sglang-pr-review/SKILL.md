---
name: sglang-pr-review
description: Empirically review an SGLang pull request by building, running, and load-testing it.
---

# SGLang PR Review

Empirically review the requested SGLang PR at its exact head. A finding needs a supported trigger, affected path, and material outcome; prefer a reproduction or a direct code trace. Skip speculative defensive code and style preferences while retaining security and data-safety findings.

## Scope and validation

- A review alone does not authorize modifying the author's branch or posting to GitHub. Local build adjustments are isolated, recorded, and excluded from the reviewed patch. If the user also requests fixes or publication, complete that authorized scope.
- Use `access-compute` and the requested source's current note. Pick the smallest model/topology that exercises the change; do not stop at a hard-coded GPU limit when an appropriate source is available.
- Use a detached worktree at the PR head and its own `.venv`. Preserve existing source trees and unrelated work.
- Docs-only reviews need relevant documentation checks; isolated logic needs targeted tests; serving/kernel changes need representative execution. Performance claims need controlled A/B with exact baseline and head SHAs.
- Separate warmup and measurement. Repeat when needed to characterize variance or investigate a failure, and report intermittent failures with their occurrence counts.

## Procedures

- For checkout and A/B identity, use the exact-checkout section of [the shared serving reference](../dynamo-pr-reviews/references/serving.md). Set `REPO=sgl-project/sglang`; use the actual PR base branch and `git merge-base`, never assume the previous commit is the baseline.
- For a pure SGLang install and launch, read [serving.md](references/serving.md).
- For an authorized GitHub review or requested pending review, use [the review publication procedure](../dynamo-pr-reviews/references/github-review.md).

Finish with severity-ordered findings, exact commits, representative test/traffic evidence, environment, and coverage limitations. After normal empirical testing, offer `full-code-review` if it was not requested already; report the completed empirical result before that optional decision.

Stop only recorded task-owned processes or scheduler jobs and verify cleanup. Retain needed evidence and follow the shared worktree-retention policy. Use `memory-log` under `sglang-pr-reviews/<PR>-<slug>/` and update that umbrella index, staging only exact task paths.
