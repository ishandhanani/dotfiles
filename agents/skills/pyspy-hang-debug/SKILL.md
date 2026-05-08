---
name: pyspy-hang-debug
description: Diagnose hung Python processes (esp. SGLang/vLLM scheduler workers) on a SLURM cluster using py-spy dumps. Captures Python + native stack traces from every scheduler rank to attribute deadlocks, infinite loops, and NCCL collective stalls. Use when an inference server has stopped logging but its SLURM job is still RUNNING, or aiperf/load-gen reports timeouts while the engine appears alive.
user-invocable: true
---

# py-spy Hang Debug for SLURM Inference Workers

When an inference server's worker process stops logging but the SLURM job is still `RUNNING`, the engine is almost certainly hung. py-spy gives you the live Python stack traces from every rank without restarting the job, and `--native` adds the C/C++ frames so you can attribute the hang to NCCL, CUDA, libc mutexes, or pure Python work.

This skill is the canonical workflow for diagnosing those hangs on SLURM clusters where the worker runs inside a container with a read-only `/home` and `/usr` (PEP 668-managed Python). The pattern is what we used to attribute hisparse + dp-attention deadlocks on sa-b200.

## When to use

- An inference job has been allocated and started but the worker log (`*_agg_w0.out`, `*_prefill_w0.out`, etc.) hasn't written a new line in N minutes
- aiperf / your load gen reports `TimeoutError`, `request timed out`, `deadline has elapsed`, or progress stuck at warmup
- `sacct`/`squeue` shows the job as `RUNNING` (not failed, not killed)
- You need to file an upstream bug and want stack-level evidence

## When NOT to use

- The job has already exited — py-spy needs a live process. Look at logs instead.
- A single quick `ps`/`top` shows the worker isn't even there — it crashed; check stderr / SLURM step exit codes.
- The process is doing slow but useful work. Watch the worker log for one minute first; only call it hung if it stops emitting lines.

## Step 1 — confirm the hang

Don't py-spy a healthy process. Verify two things:

```bash
ssh <cluster> 'squeue -j <jobid> 2>&1 | tail -2'
ssh <cluster> 'ls -la /path/to/logs/*_agg_w0.out; tail -3 /path/to/logs/*_agg_w0.out'
```

Note the timestamp on the last log line. If it's >5 minutes old and the SLURM job is still `R`, you have a hang.

## Step 2 — install py-spy inside the container

The cluster's container typically has read-only `/home` (root-owned) and `/usr` (PEP 668), so the obvious `pip install py-spy` fails. Install to `/tmp` instead:

```bash
ssh <cluster> "srun --jobid <jobid> -w <node> --overlap bash -c '
PYTHONUSERBASE=/tmp/pyspy pip install --break-system-packages --quiet py-spy 2>&1 | tail -3
ls /tmp/pyspy/bin/py-spy
'"
```

The binary lands at `/tmp/pyspy/bin/py-spy`. It survives until the SLURM step exits.

> **Note on flags.** `--break-system-packages` is needed because the container marks the system Python as PEP 668 externally-managed. `PYTHONUSERBASE=/tmp/pyspy` redirects the user-site install to a writable dir (the default `/home/$USER/.local` is root-owned in this container). Don't drop either flag.

## Step 3 — find the worker PIDs

For SGLang: each DP/TP rank runs as its own process named `sglang::scheduler_DP<n>_TP<n>_EP<n>`. For vLLM you'd grep for `vllm` worker names; for TRT-LLM, `mpirun`/`tritonserver`.

```bash
ssh <cluster> "srun --jobid <jobid> -w <node> --overlap bash -c '
pgrep -af sglang::scheduler
'"
```

Note all PIDs. For DP=8 / TP=8 you should see 8 schedulers.

## Step 4 — basic dump (Python frames only)

Quick first pass to see Python-level state:

```bash
ssh <cluster> "srun --jobid <jobid> -w <node> --overlap bash -c '
for pid in \$(pgrep -f sglang::scheduler); do
  echo === PID \$pid ===
  /tmp/pyspy/bin/py-spy dump --pid \$pid 2>&1 | head -25
  echo
done
'"
```

What to look for:

- **Different ranks in different collectives** → classic NCCL ordering deadlock. Two distinct call paths both ending in `all_gather_into_tensor` mean both are waiting for everyone, neither completes. Example we hit on sa-b200: 7 ranks in `prefill_delayer.all_gather`, 1 rank in `dp_attn.prepare_mlp_sync_batch.all_gather`. Both wait forever.
- **One rank `active+gil`, others `idle` in a collective** → the active rank isn't reaching the sync barrier. Either it has work the others don't (look at scheduler decision logic), or it's stuck in a CPU-bound loop. Capture `--native` next to find out which.
- **All ranks in the same collective and `idle`** → almost always a NCCL/network problem at the wire level (lost packet, bad NIC, fabric misconfig). Look at NCCL env (`NCCL_DEBUG=INFO`), check `dmesg` for hardware events.
- **All ranks in `event_loop_overlap` doing useful Python work** → not a hang; just slow. Watch a few seconds before declaring it stuck.

## Step 5 — native dump (Python + C/C++ frames)

When step 4 shows a rank stuck in pure Python work without an obvious cause, or you need to attribute below the Python layer (NCCL state, mutex wait, CUDA driver call), use `--native`:

```bash
ssh <cluster> "srun --jobid <jobid> -w <node> --overlap bash -c '
mkdir -p /path/to/logs/pyspy
for pid in \$(pgrep -f sglang::scheduler); do
  out=/path/to/logs/pyspy/dump_native_\$pid.txt
  echo Dumping \$pid -\\> \$out
  /tmp/pyspy/bin/py-spy dump --native --pid \$pid > \$out 2>&1
done
ls -la /path/to/logs/pyspy/
'"
```

Save to lustre (`/path/to/logs/pyspy/`) so the dumps survive the job, are attachable to upstream bug reports, and show up in your archive.

What `--native` adds:

```
Process 117489: sglang::scheduler_DP3_TP3_EP3
Thread 117489 (idle): "MainThread"
    pthread_cond_wait (libc.so.6)                   ← genuinely blocked on mutex
    std::condition_variable::wait (libstdc++.so.6.0.33)
    0x7caaa50b1a9b (?)                              ← unsymbolized C++ (NCCL)
    all_gather_into_tensor (torch/distributed/distributed_c10d.py:4193)
    prepare_mlp_sync_batch_raw (scheduler_dp_attn_mixin.py:202)
    ...
```

vs. a "stuck in Python" rank:

```
Thread 117492 (active+gil): "MainThread"
    init_next_round_input (schedule_batch.py:989)   ← deepest Python frame
    _get_new_batch_prefill_raw (scheduler.py:2700)
    ...
    0x7fdc6442a1ca (libc.so.6)                       ← Python interpreter, not blocking
```

The first is genuinely waiting in NCCL. The second is **busy in Python with the GIL held** — no syscall, no mutex, just running. That's how you confirm "infinite loop in init_next_round_input" vs "blocked on collective".

## Step 6 — make sense of the picture

For an N-rank deadlock, you almost always want to see all N traces side by side. Standard patterns:

| Pattern | Meaning | Where to look |
|---|---|---|
| All ranks in same `all_gather`, all `idle` + `pthread_cond_wait` | NCCL collective stalled at network layer | NCCL logs, `nvidia-smi nvlink -s`, fabric diagnostics |
| 7 ranks in collective A, 1 rank in collective B | Different call ordering across ranks → ordering deadlock | The two distinct Python call paths above each `all_gather_into_tensor` |
| 7 ranks in collective, 1 rank `active+gil` in pure Python | The CPU-bound rank never reaches the sync | Bottom Python frame on the busy rank — that's the bug location |
| All ranks `active+gil` in different non-collective code | Not a deadlock; just slow / progressing | Run a second dump 30s later and diff |

## Step 7 — file the report

Once you've attributed the hang, the dumps in `/path/to/logs/pyspy/` are your evidence. Useful upstream-report content:

- Job config (which flags are set: `enable-hisparse`, `enable-dp-attention`, `enable-prefill-delayer`, etc.)
- Worker log timestamp of the last activity
- All N native dumps (they're small, 1-2KB each)
- The exact deepest frame on the stuck rank (e.g. `schedule_batch.py:989 init_next_round_input`)
- Whether rerunning without one specific flag avoids the hang (this is how we narrowed down `prefill_delayer` then `hisparse` on sa-b200)

## After: cancel the hung job

```bash
ssh <cluster> 'scancel <jobid>'
```

Don't forget — a hung job sits in the queue eating its allocation until the time limit. The SLURM accounting won't mark it as failed unless you cancel.

## Reference: real attribution from sa-b200

Two failed hisparse runs on the sa-b200 cluster (jobs 16485, 16512):

- **16485:** 7 ranks blocked in `prefill_delayer._gather_info` (one collective), 1 rank blocked in `dp_attn.prepare_mlp_sync_batch` (different collective). Removed `--enable-prefill-delayer` → that race went away.
- **16512** (after fix): 7 ranks blocked in `dp_attn.prepare_mlp_sync_batch` waiting for everyone. DP6 was `active+gil` in `init_next_round_input (schedule_batch.py:989)` — busy in pure Python, never reaches the barrier. That's the actionable upstream evidence: hisparse changes scheduling such that one rank's `init_next_round_input` doesn't terminate.

Without `--native`, the second case looked indistinguishable from "DP6 just has more work". With `--native`, you can see DP6 is **not** in any syscall or collective — it's a pure-Python hot spot in hisparse code.
