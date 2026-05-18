---
name: pyspy-hang-debug
description: Diagnose hung or stalled Python processes using py-spy. Captures live Python and native (C/C++) stack traces from one or more PIDs without restarting the process — works for local processes, processes inside containers, and processes inside SLURM jobs. Use when a Python process has stopped emitting output but is still alive, when distributed workers appear deadlocked, or when you need to attribute a stall to NCCL / mutexes / pure Python work for an upstream bug report.
user-invocable: true
---

# py-spy Hang Debug

py-spy reads the live stack of a running CPython process and prints it without attaching a debugger or stopping the process. It's the right tool when:

- A Python process has stopped logging but is still alive
- A distributed worker (multi-process, multi-rank) appears deadlocked
- A long-running task is "slow" and you want to know what it's actually doing
- You need stack-level evidence to file an upstream bug

This skill walks the full diagnostic flow: confirm the hang, install py-spy in whatever environment the process lives in, capture both Python-only and `--native` (Python + C/C++) traces, and read the output.

## When to use

- A process you can identify by PID hasn't emitted log output in N minutes
- A multi-rank job (DP/TP workers in SGLang/vLLM, MPI ranks, multiprocessing pools) reports timeouts upstream while the workers are still alive
- A task is hot on CPU but never returns
- A non-deterministic hang you want to attribute, not just kill-and-retry

## When NOT to use

- The process has already exited — py-spy needs a live PID. Look at logs / core dumps instead.
- The process is doing slow but useful work. Tail the log for one minute first; only call it hung if it stops emitting output.
- You don't have permission to read the target process. py-spy needs `ptrace` access (same UID, or root, or `CAP_SYS_PTRACE`). On hardened hosts you'll get `Permission Denied` and need sudo.

## Step 1 — confirm the hang

Don't py-spy a healthy process. Verify the symptom:

- Last log line timestamp is materially older than the polling cadence the process should have
- The PID is still alive (`ps -p <pid>`)
- For SLURM jobs: `squeue -j <jobid>` shows `R` (running), not `CG` (completing) or `PD` (pending)

If all three hold, you have a hang.

## Step 2 — install py-spy

Pick the path that matches your environment.

**Local / your dev box:**
```bash
pip install py-spy        # or: cargo install py-spy
```

**Inside a venv that the target process uses:**
```bash
<venv>/bin/pip install py-spy
```

**Inside a container with read-only `/home` and PEP 668-managed system Python** (common in inference-serving containers):
```bash
PYTHONUSERBASE=/tmp/pyspy pip install --break-system-packages --quiet py-spy
# binary lands at /tmp/pyspy/bin/py-spy
```

The `--break-system-packages` flag bypasses the PEP 668 marker that says "don't touch the system Python." `PYTHONUSERBASE=/tmp/pyspy` redirects the user-site install to a writable directory (the default `~/.local` is often root-owned in containers).

**No internet inside the container:**
Either pre-build a static py-spy binary on a connected host (`cargo build --release --target x86_64-unknown-linux-musl`) and `scp` it in, or wrap the container with one that has py-spy preinstalled.

## Step 3 — get into the right shell

You need a shell that can `ptrace` the target PID. The kernel rule: same UID, or root/`CAP_SYS_PTRACE`.

**Local same-user process:** just open a terminal.

**Process inside a container started by you:** `docker exec -it <name> bash` or `enroot exec <name> bash`.

**Process inside a SLURM job:**
```bash
srun --jobid <jobid> -w <node> --overlap --pty bash
# or non-interactively for one command:
srun --jobid <jobid> -w <node> --overlap bash -c '<command>'
```

`--overlap` is critical — it lets you attach a new step to an existing job without claiming new resources. Without it the new srun will queue or fail.

**Process inside a SLURM-allocated container:** the `srun --overlap` step lands you inside the same container the workers run in. No additional `enroot exec` needed.

## Step 4 — find the PIDs

Common patterns:

| Workload | How to enumerate |
|---|---|
| SGLang scheduler workers | `pgrep -af sglang::scheduler` (one PID per DP/TP/EP rank) |
| vLLM workers | `pgrep -af vllm` |
| MPI ranks | `pgrep -af your-binary` |
| Single Python process | `pgrep -af python` |
| Anything you launched | `ps -ef | grep <name>` |

For multi-rank deadlocks you almost always want **all** ranks. Capture the PID list before dumping:

```bash
PIDS=$(pgrep -f sglang::scheduler)
echo "$PIDS"
```

## Step 5 — basic dump (Python frames only)

Quick first pass. Tells you which Python function each rank is executing right now:

```bash
for pid in $PIDS; do
  echo "=== PID $pid ==="
  /tmp/pyspy/bin/py-spy dump --pid $pid 2>&1 | head -25
  echo
done
```

Read the output. Each thread shows as `Thread <tid> (active|idle): "name"` followed by frames innermost-first.

Common patterns and what they mean:

- **All ranks in the same `all_gather` / `broadcast` / collective and `idle`** → the collective is genuinely waiting at the network layer. Often a NCCL or wire-level issue. Next step: `NCCL_DEBUG=INFO`, `dmesg`, fabric checks.
- **Different ranks in DIFFERENT collectives, all `idle`** → classic NCCL ordering deadlock. Two distinct call paths both ending in `all_gather`/etc., each waiting for everyone, neither completes. Look at the divergent Python call paths above the collective; the bug is whichever code branch decided to enter a different collective on a subset of ranks.
- **One rank `active+gil`, others `idle` in a collective** → the active rank is busy and never reaches the sync. Either it has work the others don't, or it's stuck in a CPU-bound loop. Capture `--native` next to find out which.
- **All ranks `active+gil` in different non-collective code** → not necessarily a hang; might just be slow. Take a second dump 30 seconds later and diff. If they're in the same frames, it's hung. If they advance, it's just slow.

## Step 6 — native dump (Python + C/C++ frames)

When step 5 shows a rank stuck in pure Python without an obvious cause, or you need to attribute below the Python layer (NCCL state, mutex wait, CUDA driver call, syscall), use `--native`. It interleaves C/C++/libc frames into the Python trace.

```bash
mkdir -p /path/to/save/pyspy
for pid in $PIDS; do
  out=/path/to/save/pyspy/dump_native_$pid.txt
  echo "Dumping $pid -> $out"
  /tmp/pyspy/bin/py-spy dump --native --pid $pid > $out 2>&1
done
```

Save to a durable path (not `/tmp` if you want the dumps to survive the container/job). For SLURM jobs, save under the job's output dir on shared storage so the dumps outlive the allocation.

**What `--native` reveals.** Compare two stuck ranks:

A rank genuinely waiting on a NCCL collective:
```
Thread (idle): "MainThread"
    pthread_cond_wait (libc.so.6)                          ← blocked on mutex
    std::condition_variable::wait (libstdc++.so.6.0.33)
    0x7caaa50b1a9b (?)                                     ← unsymbolized C++ (NCCL)
    all_gather_into_tensor (torch/distributed/distributed_c10d.py:4193)
    <python frames above>
```

A rank busy in pure Python:
```
Thread (active+gil): "MainThread"
    init_next_round_input (some_module.py:989)             ← deepest Python frame
    <python frames above>
    0x7fdc6442a1ca (libc.so.6)                             ← CPython interpreter, NOT blocking
```

The first is genuinely waiting in NCCL via libc's `pthread_cond_wait`. The second is **busy in Python with the GIL held** — no syscall, no mutex, just running. That's how you separate "stuck on a collective" from "stuck in an infinite Python loop."

Other native frames worth recognizing:

- `pthread_cond_wait`, `futex_wait` → blocked on a mutex/semaphore
- `clock_nanosleep`, `nanosleep` → sleeping
- `epoll_wait`, `poll`, `select` → waiting on I/O
- `recvmsg`, `read`, `write` → in a syscall, possibly waiting on the kernel
- `cuLaunchKernel`, `cudaStreamSynchronize` → inside CUDA driver
- `_PyEval_EvalFrameDefault` → CPython interpreter executing Python (so the Python frames above are real)
- `0x...... (?)` → unsymbolized C/C++; usually means a closed-source or stripped binary (NCCL is the common one)

## Step 7 — make sense of multi-rank deadlocks

For a deadlock across N ranks, lay all N traces out side by side. Patterns:

| Pattern | Meaning | Action |
|---|---|---|
| All ranks in same collective, all `pthread_cond_wait` under it | NCCL stalled at network/wire | NCCL logs, fabric / NIC checks |
| 7 ranks in collective A, 1 rank in collective B | Different call ordering across ranks | Find the divergent code path; one branch picks a different collective |
| 7 ranks in collective + `pthread_cond_wait`, 1 rank `active+gil` in pure Python | The CPU-bound rank never reaches the sync | Bottom Python frame on the busy rank — that's the bug location |
| All ranks `active+gil`, different frames | Not deadlocked; check progress | Second dump 30s later; diff |

## Step 8 — file the report

Once you've attributed the hang, the dumps are your evidence. A useful upstream issue includes:

- The exact deepest Python frame on the stuck rank (e.g. `some_module.py:989 some_function`)
- Which configuration flags were on (so the maintainer can repro)
- Whether the hang reproduces 2-for-2 (run it twice; if both hang, it's deterministic enough to file)
- A flag-bisection if you can: "with flag X off it ran clean; with flag X on it hung again" narrows the suspect code path
- All N native dumps attached (they're small, 1-2KB each)

## After: don't forget to clean up

If you opened a `srun --pty` session, exit it. If you scancel a SLURM job, do it explicitly — hung jobs sit in the queue eating allocation until the time limit, and SLURM accounting won't mark them failed unless you cancel.

## Reference workflow (for an SGLang / DP-attention deadlock)

End-to-end, copy-paste shape:

```bash
# 1. confirm hang
ssh <cluster> 'squeue -j <jobid>'
ssh <cluster> 'tail -3 /path/to/logs/*_agg_w0.out; ls -la /path/to/logs/*_agg_w0.out'
# (last log timestamp >5min old + still RUNNING = hang)

# 2. install + dump in one srun
ssh <cluster> "srun --jobid <jobid> -w <node> --overlap bash -c '
  PYTHONUSERBASE=/tmp/pyspy pip install --break-system-packages --quiet py-spy
  mkdir -p /path/to/logs/pyspy
  for pid in \$(pgrep -f sglang::scheduler); do
    /tmp/pyspy/bin/py-spy dump --native --pid \$pid > /path/to/logs/pyspy/dump_native_\$pid.txt 2>&1
  done
  ls -la /path/to/logs/pyspy/
'"

# 3. read the dumps locally
ssh <cluster> 'cat /path/to/logs/pyspy/dump_native_*.txt' | less

# 4. cancel the hung job
ssh <cluster> 'scancel <jobid>'
```
