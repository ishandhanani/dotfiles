---
name: server-lifecycle
description: Launch an inference server, run benchmarks, and clean up. Handles the full lifecycle of server + load generator + results collection.
user-invocable: true
---

# Server Lifecycle Management

Manages the full cycle: kill stale -> launch -> health check -> benchmark -> collect results -> kill.

Works with any inference server (SGLang, vLLM, TRT-LLM, etc.). Project-specific args come from the project's CLAUDE.md or `~/memory/<project>/INDEX.md`.

## Step 1: Clean Environment

Kill any stale processes from previous runs:

```bash
pkill -9 -f sglang 2>/dev/null
pkill -9 -f vllm 2>/dev/null
pkill -9 -f aiperf 2>/dev/null
sleep 3
nvidia-smi --query-gpu=index,memory.used,memory.total --format=csv,noheader
```

Verify GPU memory is free. If not, find and kill the holding process:
```bash
nvidia-smi --query-compute-apps=pid,used_memory --format=csv,noheader
```

## Step 2: Launch Server

Determine project context:
1. Check user prompt or cwd for project identity
2. Read the project's CLAUDE.md and `~/memory/<project>/INDEX.md` for launch args
3. Activate the project's venv

Launch as background task. Poll for health:
```bash
for i in $(seq 1 60); do
  curl -s localhost:${PORT}/health 2>/dev/null && echo " Server ready" && break
  sleep 5
done
```

If no health endpoint, fall back to checking `/v1/models` or process status.

### Launch Script Pattern (optional)

Use a self-contained launch script instead of inline commands when:
- Multiple processes need coordinating (e.g. Dynamo frontend + prefill + decode workers)
- You need clean signal-based shutdown across a process group
- The launch is complex enough that inline commands are unwieldy

For simple single-process launches (one sglang server, one aiperf run), inline commands are fine.

When using this pattern:
1. Write the script with the trap template below
2. Save to `/tmp/launch_<name>.sh` or the project's benchmarks dir
3. Run with `bash /tmp/launch_<name>.sh &`

```bash
#!/bin/bash
set -e

LOG_FILE="/tmp/server_$(date +%Y%m%d_%H%M%S).log"

cleanup() {
    echo "Cleaning up..."
    kill $SERVER_PID 2>/dev/null || true
    wait $SERVER_PID 2>/dev/null || true
    echo "Done. Logs: $LOG_FILE"
}
trap cleanup EXIT INT TERM

# Launch server, tee to log file
python -m sglang.launch_server \
  --model-path <model> \
  --port <port> \
  <flags> 2>&1 | tee "$LOG_FILE" &
SERVER_PID=$!

# Health check
for i in $(seq 1 60); do
  curl -s localhost:<port>/health 2>/dev/null && echo "Server ready" && break
  sleep 5
done

wait $SERVER_PID
```

Benefits:
- Signal-safe cleanup (no orphaned GPU processes)
- Logs always in `/tmp/` for debugging (`grep`, `tail -f`, etc.)
- Script is saveable and re-runnable
- Extensible for multi-process (frontend + workers) with multiple PIDs
- Replaces blind `pkill -9` with targeted PID cleanup

## Step 3: Run Benchmark

Use the appropriate benchmark script or aiperf command. Always:
- Run **baseline first**, then **treatment**
- If results matter, run **both orderings** (A/B then B/A) to control for ordering bias
- Use a **fresh server** for each phase (kill + relaunch between phases)
- Save results to `~/memory/<project>/benchmarks/results/` (or wherever the project INDEX.md specifies)

Example with aiperf:
```bash
cd ~/aiperf
uv run aiperf profile <model> \
  --url http://localhost:${PORT} \
  --endpoint-type chat \
  --input-file <dataset> \
  --custom-dataset-type multi-turn \
  --concurrency 16 \
  --streaming \
  --request-timeout-seconds 300 \
  --artifact-dir ~/memory/<project>/benchmarks/results/
```

## Step 4: Collect and Verify

```bash
# Check metrics during run (adjust grep patterns per server)
curl -s localhost:${PORT}/metrics | grep -E 'cache|hit|evict|request' | grep -v '^#'
```

After collecting results, invoke `/memory-log` to record findings.

## Step 5: Cleanup

If a launch script was used, cleanup is already handled by the trap -- just kill the script process or send SIGTERM and it will clean up its children.

For orphaned or unknown processes, fall back to `pkill`:
```bash
pkill -9 -f sglang 2>/dev/null
pkill -9 -f vllm 2>/dev/null
pkill -9 -f aiperf 2>/dev/null
sleep 2
nvidia-smi --query-gpu=index,memory.used,memory.total --format=csv,noheader
```

## Datasets

All in `~/datasets/`:
- `long_multiturn_opus.jsonl` -- 10 synthetic multi-turn sessions (flood/eviction workload)
- `claude_history_sonnet.jsonl` -- single real Claude Code session (VIP workload)
- `claude_history_10_sessions.jsonl` -- 10 real sessions, 585 turns
- `claude_history_10_sessions_with_thinking.jsonl` -- same with thinking blocks

### aiperf Concurrency Guidelines

- Quick smoke test: `--concurrency 1 --request-count 5`
- Standard load test: `--concurrency 16-32`
- Stress test: `--concurrency 64`

## Notes

- If server hangs with no errors logged, check for silent scheduler spin
- aiperf repo has its own CLAUDE.md with architecture details -- read it if making aiperf changes
- Server-specific flags (mem fractions, cache ratios, TP size) belong in the project's CLAUDE.md, not here
