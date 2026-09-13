---
name: pyspy-hang-debug
description: Diagnose a live, stalled Python process with py-spy, including container and SLURM workloads.
user-invocable: true
---

# py-spy Hang Debug

Diagnose a live Python process that appears stalled. Verify the PID/job is still running, inspect expected progress, and capture evidence before restarting or cancelling it. Quiet logs or two identical stack samples do not prove a hang.

Use an existing standalone `py-spy` where possible. If installation, ptrace permissions, container namespaces, or SLURM attachment require work, read [environments.md](references/environments.md) and the selected compute source note. Do not modify an unrelated workload's virtual environment.

Capture complete Python stack dumps for relevant task-owned PIDs. For multi-rank behavior or native waits, read [traces.md](references/traces.md), collect native stacks, and compare ranks with progress counters and CPU/GPU activity. Preserve raw dumps; truncated console previews are not the evidence artifact.

Treat collective ordering, network stalls, and a busy rank as hypotheses until observations distinguish them. Repeat sampling when it resolves that uncertainty. An intermittent hang remains reportable; give occurrence counts rather than requiring two identical failures.

Finish with PID/job identity, exact frames, configuration, observations, evidence paths, leading supported explanation, and unresolved alternatives. Draft an upstream report if requested; do not post it without authorization. Exit only diagnostic sessions you opened. Cancel the workload only when that action is authorized; otherwise preserve it for further investigation.
