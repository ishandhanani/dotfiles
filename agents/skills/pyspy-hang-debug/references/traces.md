# Stack evidence and multi-rank hypotheses

Sample task-owned PIDs and retain full dumps in durable artifacts; a stack location alone does not prove a deadlock or its root cause.

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

- **All ranks in the same `all_gather` / `broadcast` / collective and `idle`** → the ranks appear to be waiting in a collective; this alone does not identify a network fault. Check peer participation and progress as well as NCCL/fabric evidence. Next step: `NCCL_DEBUG=INFO`, `dmesg`, fabric checks.
- **Different ranks in DIFFERENT collectives, all `idle`** → investigate incompatible collective ordering. Compare call paths, expected participation, and progress over time; asynchronous samples alone do not prove deadlock.
- **One rank `active+gil`, others `idle` in a collective** → investigate whether that rank has useful extra work or is stuck in a loop. Capture native frames and progress evidence before concluding it cannot reach synchronization.
- **All ranks `active+gil` in different non-collective code** → not necessarily a hang; it may be useful work. Take a second dump 30 seconds later and diff. Unchanged frames suggest a stall but can also represent long useful work. Correlate stack samples with CPU/GPU activity, counters, and expected progress before concluding a hang.

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

The first sample shows a native wait under the collective call path; the second shows Python execution with the GIL held. These observations distinguish where to investigate, but neither proves a permanent stall or an infinite loop without progress evidence.

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
| All ranks in same collective, all `pthread_cond_wait` under it | Possible collective/network stall; verify peers and progress | NCCL logs, fabric / NIC checks |
| 7 ranks in collective A, 1 rank in collective B | Different call ordering across ranks | Find the divergent code path; one branch picks a different collective |
| 7 ranks in collective + `pthread_cond_wait`, 1 rank `active+gil` in pure Python | A busy rank may be delaying synchronization | Inspect that rank's frames and progress |
| All ranks `active+gil`, different frames | Activity alone does not prove progress | Repeat sampling and compare progress counters |
