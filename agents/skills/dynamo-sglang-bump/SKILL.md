---
name: dynamo-sglang-bump
description: Upgrade Dynamo's SGLang version and resolve compatibility breakage.
user-invocable: true
---

# Dynamo SGLang Version Bump

Upgrade the requested SGLang dependency and its supported Dynamo integration, using the target checkout's current compatibility policy and representative launch results.

## Inputs and isolation

Resolve the target version, source tag/commit, branch, any linked ticket, and requested container variants from the request and current manifests. Reuse supplied answers. Inspect published runtime tags; ask only about an unresolved variant or release decision, not every tag by default.

Preserve dirty canonical checkouts. Create task-owned worktrees at the selected Dynamo base and SGLang target commits, following the shared layout convention. Use only the Dynamo worktree's `.venv` for the paired runtime and its own Cargo target. Do not delete a previous environment; a new worktree provides a fresh one. Use `access-compute` for the requested source and `setup-dynamo-sglang-from-src` for the paired build. Include SGLang's diffusion extra when testing the diffusion launch matrix.

## Compatibility and execution

1. Read the checked-out component instructions and `_compat.py` if present. Record the actual minimum and target supported versions. A target N does not automatically make N the minimum.
2. Validate relevant launch paths and fix observed integration breakage. Keep each fix scoped to its cause and preserve a result table with pass/fail/skipped reasons.
3. Remove compatibility fallbacks only when no supported version needs them. Validate affected imports/behavior at the actual minimum as well as the target. Read [compatibility.md](references/compatibility.md) for pruning and CI collection details.
4. For runtime tags and container manifests, read [containers.md](references/containers.md). For the full backend launch matrix, read [launch-matrix.md](references/launch-matrix.md). When a failure resembles a prior release regression, consult its symptom in [historical-fixes.md](references/historical-fixes.md); do not apply historical fixes without checking current source.

Use task-owned process groups or scheduler jobs and record them before testing. Stop only those resources between phases; never kill by broad program name. Use bounded readiness plus a representative request, record exact responses/logs, and preserve intermittent failures. Re-run affected checks after a fix or compatibility pruning; do not repeat a passing unchanged matrix without a reason.

## Completion

Finish when the dependency and available requested container references are updated, in-scope compatibility fixes and pruning are validated across the support window, applicable launch results are recorded, and repository-required checks pass. Run the repository's full pre-commit hooks after import/mock-list changes; repeat only after changes or unresolved failures warrant it.

Keep unrelated cleanups separate. Bundle a feature gated on the new version only when requested. Record exact commits, environment, result matrix, each fix, compatibility additions/removals, and skipped/unavailable targets through `memory-log`. For an implementation request that includes publishing, push the canonical branch and open a draft PR with the validation summary and linked ticket. Report any genuine external blocker with the completed evidence and remaining action.
