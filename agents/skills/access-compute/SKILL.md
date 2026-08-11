---
name: access-compute
description: Use when the user asks to access a compute source, run local work on a remote GPU machine, use a direct SSH development box, choose between direct compute and a Teleport cluster, or move a branch to remote compute for a Dynamo or SGLang build and run. Reads the private compute registry before any connection attempt and creates an isolated remote session.
---

# Access Compute

Use this skill as the entry point for compute work. Keep all source names, aliases, endpoints, paths, and live state in `~/memory/compute/`.

## Required Flow

1. Read `~/memory/compute/INDEX.md`.
2. Resolve the user's source name through the aliases in that registry.
3. Read the linked source note before any DNS, SSH, `tsh`, Kubernetes, or SLURM probe.
4. Use the access type and command from the source note.

Do not search old project notes for an endpoint when the active source note exists. Do not retry a retired endpoint.

## Select the Access Path

- For a direct SSH source, use the direct-session flow in this skill.
- For a Teleport-managed Kubernetes or SLURM source, load `teleport-clusters` and obey its authentication flow.
- For a large or distributed run, prefer a cluster source unless the user selects a direct source.
- If the registry has no matching source, stop and ask the user which source to use.

## Publish Local Work

Before the remote connection, identify the local repository, branch, commit, canonical remote, and dirty state.

```bash
git status --short
git branch --show-current
git rev-parse HEAD
git remote -v
```

If the requested work is dirty, create one focused commit that contains only that work. Preserve unrelated changes.

Push the exact commit to a named branch on the canonical remote. Record the branch and full commit SHA.

```bash
git push origin HEAD:<branch>
```

Use a Git bundle only when the user does not permit a remote push. Do not copy a working tree with `rsync` or `scp`.

## Start a Direct Session

Use the SSH alias or command from the private source note. Native OpenSSH connection sharing supplies the persistent connection.

First, inspect the source without changing it:

```bash
hostname
id -un
nvidia-smi
git --version
uv --version
```

Also inspect active GPU processes, existing `tmux` sessions, disk space, and the source note's base repositories. Preserve unrelated workloads.

Create one session root under the parent path from the source note. Use a UTC timestamp and a short task name.

```text
<session-parent>/<timestamp>-<task>/
├── dynamo/
├── sglang/
├── logs/
└── artifacts/
```

Fetch the pushed branch from the canonical remote. Check out the recorded commit SHA in the session repository. Do not build from a moving branch head.

Keep all checkouts, virtual environments, build targets, logs, and output inside this session root. Do not mutate another session's checkout or virtual environment.

## Build and Run

For a Dynamo and SGLang source build, load `setup-dynamo-sglang-from-src` after both exact commits exist in the session root.

Run long commands in a named `tmux` session. Send stdout and stderr to the session's `logs/` directory. Put benchmark output and traces in `artifacts/`.

Use the source note for model caches, service ports, build limits, and existing infrastructure. Do not install host packages or replace shared services unless the user authorizes provisioning.

## Cleanup and Handoff

Stop only processes that this session started. Do not kill processes by broad name or clear shared caches.

Report these facts:

- compute source and access type
- local branch and exact commit SHA
- remote session root and `tmux` session
- build and run commands
- log and artifact paths
- health or benchmark result
- processes that remain active

Update the private source note when its access method, stable paths, or durable host state changes.
