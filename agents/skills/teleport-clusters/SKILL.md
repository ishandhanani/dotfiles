---
name: teleport-clusters
description: Use when the user asks to access, inventory, troubleshoot, or refresh auth for Teleport-managed clusters, NVIDIA DGX Cloud clusters, tsh login, Kubernetes cluster contexts, SLURM clusters behind Teleport, or asks which clusters are available. Reads ~/memory/clusters first, checks Teleport certificate state, and prompts the user for MFA/port-forward refresh when needed.
user-invocable: true
---

# Teleport Clusters

Use this skill for cluster work that depends on `tsh`, NVIDIA DGX Cloud Teleport, or the cluster registry in `~/memory`.

## Start Here

1. Read `~/memory/clusters/INDEX.md` first. Treat it as the map of known clusters.
2. Read the linked note for the target cluster before probing live state.
3. If Teleport auth is involved, read `~/memory/clusters/nv-prd-dgxc-teleport.md`.
4. Verify live state with `tsh`, `kubectl`, `ssh`, or SLURM commands only after loading the relevant memory note.

Current registry shape to expect from memory:

| Cluster | Access type |
|---------|-------------|
| `sa-b200` | SLURM |
| `sa-gb200` | SLURM |
| `sgl-gb200` | SLURM |
| `dynamo-gb200-k8s` | Kubernetes |
| `nscale-b200-k8s` | Kubernetes |
| `try-67676-h100-nvl` | direct VM |

## Auth Check

Prefer the local helper when it exists:

```bash
~/.local/bin/tsh-ensure -- tsh ls
```

For a direct certificate check, avoid relying on `tsh status` because it has been observed to hang in this environment. Inspect the Teleport SSH certificate instead:

```bash
ssh-keygen -Lf ~/.tsh/keys/nv-prd-dgxc.teleport.sh/idhanani@nvidia.com-ssh/nv-prd-dgxc.teleport.sh-cert.pub
```

Look at the `Valid:` line. If the certificate is missing or expired, pause cluster work and ask the user for a Teleport refresh.

## Refresh Workflow

Use this login command when a full refresh is needed:

```bash
tsh login \
  --proxy=nv-prd-dgxc.teleport.sh:443 \
  --user=idhanani@nvidia.com \
  --browser=none \
  --bind-addr=127.0.0.1:45693 \
  --callback=http://127.0.0.1:45693
```

When the command prints a localhost URL, tell the user exactly what is needed:

```bash
ssh -N -L 45693:127.0.0.1:45693 <vm-ssh-alias>
```

If the user's local SSH alias is known from recent context, include the concrete alias too, for example:

```bash
ssh -N -L 45693:127.0.0.1:45693 d
```

Then ask them to open the printed `http://127.0.0.1:45693/...` URL locally and complete NVIDIA/Microsoft MFA. Keep the terminal command running until the user confirms login completed.

Notes:
- Observed full-login cert TTL is about 7 hours.
- VM-local/headless browser automation has not completed the NVIDIA/Microsoft WebAuthn flow in this environment.
- `tsh login --headless` is not a replacement for full login here.
- Command-scoped Teleport headless flows may work for `tsh ls`, `tsh ssh`, and `tsh scp`, but must use `--user=idhanani@nvidia.com`.
- Do not store or ask for passwords, MFA codes, recovery codes, or cookies.

## Cluster Probing

For Kubernetes clusters:

```bash
kubectl config get-contexts
kubectl --context <context> get nodes -o wide
kubectl --context <context> get pods -A
kubectl --context <context> get namespaces
```

For SLURM clusters, after reaching the login node:

```bash
sinfo
squeue -u "$USER"
scontrol show nodes
nvidia-smi
```

For direct VMs:

```bash
ssh <alias-or-host> nvidia-smi
```

Report exact command failures and auth state. Do not claim a cluster is unavailable until auth has been checked and the relevant memory note has been read.

## Update Memory

When the session discovers meaningful cluster facts, update `~/memory/clusters/`:

1. Edit the target cluster note or create one if it is a new cluster.
2. Update `~/memory/clusters/INDEX.md` if the cluster list, access type, or support notes changed.
3. Commit memory changes from `~/memory` with a `clusters: ...` message.
