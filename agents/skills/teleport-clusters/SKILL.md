---
name: teleport-clusters
description: Use when the user asks to access, inventory, troubleshoot, or refresh authentication for a Teleport-managed Kubernetes or SLURM cluster. Reads the private compute registry and source note before it runs tsh, kubectl, SSH, or SLURM commands.
---

# Teleport Clusters

Use this skill only for Teleport-managed compute. Use `access-compute` as the entry point when the access type is not known.

## Load Private State First

1. Read `~/memory/compute/INDEX.md`.
2. Resolve the source through the aliases in that registry.
3. Read the linked source note.
4. Read the linked Teleport authentication note.

If the source note says `direct-ssh`, stop this flow and use `access-compute`. Do not try Teleport as a fallback.

## Check Authentication

Prefer the local authentication helper when the source note defines one:

```bash
<auth-helper> -- tsh ls
```

If `tsh status` hangs, inspect the Teleport SSH certificate from the path in the private authentication note:

```bash
ssh-keygen -Lf <teleport-certificate>
```

Read the `Valid:` line. If the certificate is absent or expired, pause cluster work and start the refresh flow.

## Refresh Authentication

Build the `tsh login` command from the proxy, user, bind address, and callback in the private authentication note.

When `tsh login` prints a localhost URL, give the user the exact port-forward command from that note. Ask the user to open the URL and complete MFA.

Keep the login command active until the user reports completion. Do not ask for passwords, MFA codes, recovery codes, cookies, or tokens.

## Inspect the Cluster

Use the context or login node from the source note.

For Kubernetes:

```bash
kubectl config get-contexts
kubectl --context <context> get nodes -o wide
kubectl --context <context> get pods -A
kubectl --context <context> get namespaces
```

For SLURM:

```bash
sinfo
squeue -u "$USER"
scontrol show nodes
nvidia-smi
```

Report the exact command failure and authentication state. Do not report that a source is unavailable before you read its note and check authentication.

## Update Private Memory

When stable access facts change, update the target note under `~/memory/compute/` or its linked private cluster note. Update `~/memory/compute/INDEX.md` when aliases or access types change.
