---
name: server-lifecycle
description: Run and validate SGLang or Dynamo benchmarks through srt-slurm.
---

# Server Lifecycle

Use this skill for SGLang/Dynamo benchmark recipes managed by srt-slurm. YAML is the durable benchmark definition; rendered bash owns execution. A one-off diagnostic in another project does not authorize changing srt-slurm.

## Core contract

- Read the closest current recipe and backend launcher. Put model, topology, backend settings, and benchmark command in the repository's supported YAML schema; validate rather than guessing keys.
- Render with `srtctl dry-run` and `srtctl apply --bash`, then check generated shell syntax before execution. If renderer behavior is the requested change, fix and test the renderer; use temporary local glue only to validate a launch pattern.
- Record task-owned server/client PIDs, process groups, or scheduler jobs. Isolate launchers that trap `kill 0` with `setsid`. Clean only recorded resources, TERM before KILL if needed. A same-user AIPerf process can belong to another benchmark; never blanket-kill it.
- Use bounded model readiness plus a tiny inference request before load. Watch startup logs and process exit; a listening port or frontend `/health` alone does not establish readiness.
- Start requested telemetry before load and stop task-owned telemetry at cleanup. Verify request errors, cancellation, and GPU/process cleanup before reporting measurements.

## Conditional references

- For schema/renderer/CLI changes, read [rendering.md](references/rendering.md) for targeted checks and required lifecycle behavior.
- For metrics or OTEL configuration, read [telemetry.md](references/telemetry.md). Do not load telemetry details for runs that do not use them.
- For local lifecycle debugging or readiness-helper usage, read [local-lifecycle.md](references/local-lifecycle.md). Resolve the helper relative to this skill, not a fixed agent home.
- For benchmark command flags or interpreting artifacts, read [aiperf.md](references/aiperf.md); verify flags against the installed version.

Finish with the config and commit, commands, artifact root, request/error counts, relevant latency/throughput metrics, configured telemetry status, and cleanup state. Repeat measurements to characterize variance or investigate changes/failures, not by a fixed ritual. Log meaningful results through `memory-log`.
