---
name: dynamo-pr-reviews
description: Empirically review a Dynamo pull request by building, running, and load-testing it.
---

# Dynamo PR Review

Review the requested Dynamo PR empirically. Form hypotheses from the changed code and verify them with the smallest representative tests, responses, logs, or measurements.

## Scope and completion

- A review request authorizes isolated local testing, not changes to the author's branch. Describe fixes locally unless the user also asks to implement them. Keep throwaway build adjustments separate from the reviewed patch and record their effect on validation.
- Findings need a supported precondition, affected path, and material outcome. Preserve security and data-safety findings; skip speculative defensive code, style preferences, and unsupported inputs.
- Resolve compute through `access-compute` and the selected source note. Choose the smallest model and topology that exercise the change; do not reject a requested source based on a fixed GPU default.
- Inspect existing checkouts and use an isolated detached worktree at the PR head. Preserve unrelated changes, checkout-local `.venv`, and per-worktree Cargo targets.
- For docs-only changes, inspect the claims and relevant links. For isolated code, run targeted tests. Serving changes need a real server and representative traffic; performance claims need a controlled baseline. A full backend upgrade needs its launch coverage matrix.
- Separate benchmark warmup from measurement. Repeat for variability, failure investigation, or a changed fix, not a fixed number of times. Report intermittent failures with occurrence counts and evidence.

## Select the needed procedure

- For building, launching, readiness, or A/B testing, read [serving.md](references/serving.md).
- When a build or runtime symptom needs diagnosis, use the matching item in [troubleshooting.md](references/troubleshooting.md). Check current dependencies before using historical version advice.
- For posting an authorized review or preparing a requested pending review, read [github-review.md](references/github-review.md). Draft-only requests produce a local artifact.

Finish the empirical review with findings, validation scope, exact commits, hardware, commands, artifacts, and limitations. After normal testing, offer `full-code-review` if it was not requested already; do not let that optional decision delay this report. For an explicitly combined general/deep review, honor that scope directly.

Stop only task-owned processes or jobs and verify cleanup. Retain needed artifacts and follow the shared worktree-retention policy. Record meaningful results through `memory-log` under `dynamo-pr-reviews/<PR>-<slug>/`, updating the umbrella index and committing only exact task paths.
