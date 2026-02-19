---
name: server-lifecycle
description: Launch SGLang server, run benchmarks, and clean up. Handles the full lifecycle of server + load generator + results collection.
user-invocable: true
---

# Server Lifecycle Management

Manages the full cycle: kill stale -> launch -> health check -> benchmark -> collect results -> kill.

## Step 1: Clean Environment

Kill any stale processes from previous runs:

```bash
pkill -9 -f sglang 2>/dev/null
pkill -9 -f aiperf 2>/dev/null
sleep 3
nvidia-smi --query-gpu=index,memory.used,memory.total --format=csv,noheader
```

Verify GPU memory is free. If not, find and kill the holding process:
```bash
nvidia-smi --query-compute-apps=pid,used_memory --format=csv,noheader
```

## Step 2: Launch Server

Determine which project/venv to use:
1. Check if user specified a project context
2. Default to `~/sglang-poc-pin` if it exists
3. Read the project's CLAUDE.md for standard launch args

Standard PIN dev launch:
```bash
source ~/sglang-poc-pin/.venv/bin/activate

CUDA_VISIBLE_DEVICES=0,1 python -m sglang.launch_server \
  --model-path Qwen/Qwen3-14B-FP8 \
  --port 30000 \
  --mem-fraction-static 0.50 \
  --tp-size 2 \
  --enable-hierarchical-cache \
  --hicache-ratio 2.0 \
  --hicache-write-policy write_through \
  --trust-remote-code \
  --log-level info \
  --watchdog-timeout 120000 \
  --enable-metrics \
  --enable-cache-report \
  --context-length 32768
```

Run as background task. Poll for health:
```bash
for i in $(seq 1 60); do
  curl -s localhost:30000/health 2>/dev/null && echo " Server ready" && break
  sleep 5
done
```

## Step 3: Run Benchmark

Use the appropriate benchmark script or aiperf command. Always:
- Run **baseline first**, then **treatment** (e.g., pinned)
- If results matter, run **both orderings** (A/B then B/A) to control for ordering bias
- Use a **fresh server** for each phase (kill + relaunch between phases)
- Save results to `~/memory/agentic-cache-control/benchmarks/results/`

Example with aiperf:
```bash
cd ~/aiperf
uv run aiperf profile Qwen/Qwen3-14B-FP8 \
  --url http://localhost:30000 \
  --endpoint-type chat \
  --input-file ~/datasets/long_multiturn_opus.jsonl \
  --custom-dataset-type multi-turn \
  --concurrency 16 \
  --streaming \
  --request-timeout-seconds 300 \
  --artifact-dir ~/memory/agentic-cache-control/benchmarks/results/
```

Example with benchmark script:
```bash
source ~/sglang-poc-pin/.venv/bin/activate
python ~/memory/agentic-cache-control/benchmarks/pin_benchmark_v8.py \
  --depths 10 \
  --phase baseline \
  --output-dir /tmp/benchmark_results
```

## Step 4: Collect and Verify

```bash
# Check metrics during run
curl -s localhost:30000/metrics | grep -E 'hicache|cache_hit|evicted|num_requests' | grep -v '^#'

# Copy results
cp /tmp/benchmark_results/results.json ~/memory/agentic-cache-control/benchmarks/results/

# Check PIN-specific logs if relevant
grep '\[PIN\]' /tmp/sglang_server_*.log | tail -20
```

## Step 5: Cleanup

Always kill server after benchmarks:
```bash
pkill -9 -f sglang 2>/dev/null
pkill -9 -f aiperf 2>/dev/null
sleep 2
ps aux | grep -E 'sglang|aiperf' | grep -v grep | wc -l  # should be 0
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

- If server hangs with no errors logged, that is a bug -- check for silent scheduler spin
- `--watchdog-timeout 120000` prevents false watchdog kills during long benchmarks
- `--mem-fraction-static 0.50` leaves room for HiCache host memory
- `--hicache-ratio 2.0` means 2x GPU memory allocated for host-side cache
- aiperf repo has its own CLAUDE.md with architecture details -- read it if making aiperf changes
