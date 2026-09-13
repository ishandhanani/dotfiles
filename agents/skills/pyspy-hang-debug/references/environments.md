# Diagnostic access by environment

## Step 2 — install py-spy

Pick the path that matches your environment.

**Local / your dev box:**
```bash
uv tool install py-spy     # or use the existing standalone binary
```

Do not mutate the target process's environment just to install a diagnostic tool. Use a standalone binary or a task-owned tool environment.

**Inside a container with read-only `/home` and PEP 668-managed system Python** (common in inference-serving containers):
```bash
PYTHONUSERBASE=/tmp/pyspy python -m pip install --user --break-system-packages --quiet py-spy
# binary lands at /tmp/pyspy/bin/py-spy
```

The `--break-system-packages` flag bypasses the PEP 668 marker that says "don't touch the system Python." `PYTHONUSERBASE=/tmp/pyspy` redirects the user-site install to a writable directory (the default `~/.local` is often root-owned in containers).

**No internet inside the container:**
Either pre-build a static py-spy binary on a connected host (`cargo build --release --target x86_64-unknown-linux-musl`) and `scp` it in, or wrap the container with one that has py-spy preinstalled.

## Step 3 — get into the right shell

Use a shell with access to the target PID namespace and the required ptrace permissions. Same UID can still be restricted by Yama, container capabilities, or security policy; inspect the actual denial and use the source's authorized diagnostic path.

**Local same-user process:** just open a terminal.

**Process inside a container started by you:** `docker exec -it <name> bash` or `enroot exec <name> bash`.

**Process inside a SLURM job:**
```bash
srun --jobid <jobid> -w <node> --overlap --pty bash
# or non-interactively for one command:
srun --jobid <jobid> -w <node> --overlap bash -c '<command>'
```

`--overlap` is critical — it lets you attach a new step to an existing job without claiming new resources. Without it the new srun will queue or fail.

**Process inside a SLURM-allocated container:** check the cluster's container integration and PID namespace. An overlapping step does not universally enter the target container; use the source note's supported attachment command.
