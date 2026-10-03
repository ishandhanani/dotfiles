---
name: access-compute
description: Access GPU compute over direct SSH, Teleport, or Modal. Use for remote builds, runs, or access routing.
---

# Access Compute

Use this skill as the entry point for compute work. Keep all source names, aliases, endpoints, paths, and live state in `~/memory/compute/`.

## Required Flow

1. Read `~/memory/compute/INDEX.md`.
2. Resolve the user's source name through the aliases in that registry.
3. Read the linked source note before any DNS, SSH, `tsh`, Kubernetes, SLURM, or Modal probe.
4. Check the source's tags and restrictions (Tailscale, Teleport, VPN, office network, shared account, restricted QoS, cgroup caps, etc.) and satisfy them before connecting.
5. Use the access type and command from the source note.

Do not search old project notes for an endpoint when the active source note exists. Do not retry a retired endpoint.

## Select the Access Path

- For a direct SSH source, use the direct-session flow in this skill.
- For a Teleport-managed Kubernetes or SLURM source, load `teleport-clusters` and obey its authentication flow.
- For a Modal source, use the Modal section below.
- For a large or distributed run, prefer a cluster source unless the user selects a direct source.
- If the registry has no matching source, stop and ask the user which source to use.

## Publish Local Work

For an inventory or authentication request, stop after resolving access; no repository publication is needed. For a build or run, record the requested repository and exact commit. If that commit is already available from the canonical remote, fetch it directly on the selected source. A PR review must not publish an unrelated local HEAD or commit the canonical checkout's dirty work.

Only when the requested run needs local changes, identify the local repository, branch, commit, canonical remote, and dirty state:

```bash
git status --short
git branch --show-current
git rev-parse HEAD
git remote -v
```

If the requested work is dirty, create one focused commit that contains only that work. Preserve unrelated changes.

When branch publication is within the user's authorized scope, push the exact task commit to a named branch on the canonical remote. Otherwise transfer a Git bundle. Record the branch or bundle and full commit SHA.

```bash
git push origin HEAD:<branch>
```

Do not copy a working tree with `rsync` or `scp`; preserve exact Git identity with a remote fetch or bundle. Modal is the exception; see the Modal section.

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

Fetch the requested existing ref, authorized published branch, or task bundle. Check out the recorded commit SHA in the session repository. Do not build from a moving branch head.

Keep all checkouts, virtual environments, build targets, logs, and output inside this session root. Do not mutate another session's checkout or virtual environment.

## Build and Run

For a Dynamo and SGLang source build, load `setup-dynamo-sglang-from-src` after both exact commits exist in the session root.

Run long commands in a named `tmux` session. Send stdout and stderr to the session's `logs/` directory. Put benchmark output and traces in `artifacts/`.

Use the source note for model caches, service ports, build limits, and existing infrastructure. Do not install host packages or replace shared services unless the user authorizes provisioning.

## Run on Modal

Modal has no SSH host, session root, or `tmux`. Containers are ephemeral and bill per second while alive. Use the profile, environment, image, volumes, and entry script from the source note.

- Edit and build on the local machine. Mount the local worktree into the container instead of fetching inside it.
- Record the worktree's commit SHA. If the worktree is dirty, also record `git diff | sha256sum`. Store both with the run's results.
- Run long jobs with `modal run --detach`. Write results to the source note's results volume.
- Use `modal shell` or a sandbox only for interactive work. Stop it when the work ends.
- At handoff, run `modal app list` and `modal container list`. Stop only the apps, containers, and sandboxes that this session started.

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
