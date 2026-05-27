---
name: server-lifecycle
description: Launch inference servers, run AIPerf or custom benchmarks, collect telemetry with tachometer or Prometheus, verify results, and clean up GPU processes. Use for SGLang, Dynamo, vLLM, TRT-LLM, or any server/load-generator lifecycle.
user-invocable: true
---

# Server Lifecycle Management

Own the full benchmark lifecycle: clean stale processes -> launch server -> wait for real readiness -> collect telemetry -> run load -> verify artifacts -> tear down -> log results.

Project-specific launch args come from the repo `CLAUDE.md`/`AGENTS.md`, `~/memory/<project>/INDEX.md`, and existing launch scripts. Prefer existing project launch scripts over inventing new flags.

## Operating Rules

- Fresh server per phase. For A/B comparisons, run A/B and B/A if results matter.
- Use a trap-based script when there is more than one process, any GPU server, telemetry, or a benchmark command.
- Put artifacts under a timestamped run root. Keep server logs, telemetry, AIPerf output, and GPU snapshots together.
- Treat `/health` and `/v1/models` as partial readiness only. Before load, send a tiny request to `/v1/chat/completions` or the target inference endpoint.
- Always verify AIPerf JSON and final GPU/process cleanup before trusting numbers.
- Invoke `/memory-log` for benchmark results, root causes, or durable launch decisions.

## Choose The Representation

Use one source of truth per task:

- **Use `srt-slurm` YAML** when working in `srt-slurm` or when the benchmark should be reusable on SLURM. Put model, topology, backend config, and inline AIPerf command in YAML; validate with `srtctl dry-run` and `srtctl apply --bash | bash -n`.
- **Use a bash lifecycle runner** for local-only experiments, repos without a YAML renderer, or glue around existing launch scripts. This is the right shape for a 2x GPU workstation run that starts Dynamo/SGLang locally and collects tachometer output.
- **Use both only when YAML is the durable artifact and bash is generated or local validation glue.** Do not maintain two independent launch definitions for the same benchmark.

## Clean First

Use targeted cleanup first, then verify GPU memory:

```bash
pkill -9 -f 'sglang|dynamo|vllm|trtllm|aiperf profile|tachometer-scraper' 2>/dev/null || true
sleep 3
nvidia-smi --query-gpu=index,name,memory.used,memory.total --format=csv,noheader
pgrep -af 'sglang|dynamo|vllm|trtllm|aiperf|tachometer-scraper' || true
```

If GPU memory is still held:

```bash
nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv,noheader
```

## Launch Pattern

This pattern is for local/ad hoc runners and for understanding what rendered lifecycle scripts should do. If `srt-slurm` YAML is the source of truth, prefer rendering the script from YAML instead of hand-maintaining this shell.

Use `setsid` for child launch scripts that may trap `kill 0` internally, such as Dynamo example launchers. That isolates the child process group so its cleanup cannot kill the parent benchmark runner.

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

RUN_ROOT="${RUN_ROOT:-$PWD/outputs/$(date +%Y%m%d_%H%M%S)}"
MODEL="${MODEL:-Qwen/Qwen3-0.6B}"
PORT="${PORT:-8000}"
METRICS_PORT="${METRICS_PORT:-8081}"
TACHOMETER_BIN="${TACHOMETER_BIN:-$(command -v tachometer-scraper || true)}"
AIPERF_BIN="${AIPERF_BIN:-$(command -v aiperf || true)}"
SERVER_PID=""
TACHOMETER_PID=""

log() { printf '[server-lifecycle] %s\n' "$*"; }

stop_process_group() {
  local pid="${1:-}"
  [[ -n "$pid" ]] || return 0
  kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}

stop_tachometer() {
  [[ -n "${TACHOMETER_PID:-}" ]] || return 0
  kill -INT "$TACHOMETER_PID" 2>/dev/null || true
  wait "$TACHOMETER_PID" 2>/dev/null || true
  TACHOMETER_PID=""
}

cleanup() {
  local rc=$?
  stop_tachometer
  stop_process_group "$SERVER_PID"
  pkill -9 -f 'aiperf profile|tachometer-scraper' 2>/dev/null || true
  exit "$rc"
}
trap cleanup EXIT INT TERM

wait_http_ready() {
  local url="$1" timeout="${2:-420}" start
  start="$(date +%s)"
  until curl -fsS --max-time 2 "$url" >/dev/null 2>&1; do
    if (( "$(date +%s)" - start >= timeout )); then
      log "Timed out waiting for $url"; return 1
    fi
    sleep 5
  done
}

wait_chat_ready() {
  local timeout="${1:-600}" start
  start="$(date +%s)"
  until curl -fsS --max-time 30 -H 'Content-Type: application/json' \
    -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}],\"max_tokens\":1,\"stream\":false}" \
    "http://localhost:${PORT}/v1/chat/completions" >/dev/null 2>&1; do
    if (( "$(date +%s)" - start >= timeout )); then
      log "Timed out waiting for chat completions"; return 1
    fi
    sleep 5
  done
}

start_tachometer() {
  local out_dir="$1"; shift
  [[ -x "$TACHOMETER_BIN" ]] || { log "tachometer unavailable; skipping"; return 0; }
  rm -rf "$out_dir/tachometer/run" "$out_dir/tachometer-local"
  mkdir -p "$out_dir/tachometer" "$out_dir/tachometer-local"
  "$TACHOMETER_BIN" "$@" \
    --storage "$out_dir/tachometer/run" \
    --local-dir "$out_dir/tachometer-local" \
    --freq "${TACHOMETER_FREQ:-1.0}" \
    --save-interval 2 \
    --sync-interval 0 >"$out_dir/tachometer.log" 2>&1 &
  TACHOMETER_PID=$!
}
```

Launch server inside the script and capture logs:

```bash
mkdir -p "$RUN_ROOT/server"
(
  # Activate venv, export HF_HOME, CUDA_VISIBLE_DEVICES, etc. here.
  exec setsid bash path/to/launch.sh --model-path "$MODEL"
) >"$RUN_ROOT/server/server.log" 2>&1 &
SERVER_PID=$!

wait_http_ready "http://localhost:${PORT}/v1/models" 420
wait_http_ready "http://localhost:${METRICS_PORT}/metrics" 120
wait_chat_ready 600
```

For multi-worker disagg, wait for every metrics endpoint and scrape each endpoint with a stable name:

```bash
start_tachometer "$RUN_ROOT" \
  --endpoint prefill=http://localhost:8081/metrics \
  --endpoint decode=http://localhost:8082/metrics
```

If tachometer is missing and the user wants it, build it from `NVIDIA-dev/warnold-tachometer`:

```bash
git clone git@github.com:NVIDIA-dev/warnold-tachometer.git /ephemeral/warnold-tachometer
cargo build --release --manifest-path /ephemeral/warnold-tachometer/tachometer-scraper/Cargo.toml
find "${CARGO_TARGET_DIR:-/ephemeral/cargo-target}" target -path '*/release/tachometer-scraper' -type f 2>/dev/null
```

## AIPerf

Find flags from the installed version, not memory:

```bash
aiperf profile --help | sed -n '1,220p'
rg -n "no-server-metrics|output-artifact-dir|profile-export-prefix|ui" ~/aiperf 2>/dev/null || true
```

Agent-run AIPerf defaults:
- Always pass `--ui none`.
- Keep `--output-artifact-dir` and `--profile-export-prefix` explicit.
- Use `--no-server-metrics` when tachometer, curl scraping, DCGM, or another collector owns metrics. For SGLang this avoids nullable Prometheus payload issues and keeps AIPerf focused on request records.
- For smoke runs, use small synthetic load: concurrency 1-2, request count 5-10, warmup 1. For load tests, use concurrency 16-32.
- Add `--tokenizer-trust-remote-code` for HF models that need it.
- If using `--osl`, set `ignore_eos`/`min_tokens` through server-supported inputs when exact output length matters.

Baseline command:

```bash
"$AIPERF_BIN" profile "$MODEL" \
  --url "http://localhost:${PORT}" \
  --endpoint-type chat \
  --streaming \
  --concurrency "${AIPERF_CONCURRENCY:-2}" \
  --request-count "${AIPERF_REQUEST_COUNT:-8}" \
  --warmup-request-count "${AIPERF_WARMUP_REQUEST_COUNT:-1}" \
  --isl "${AIPERF_ISL:-128}" \
  --osl "${AIPERF_OSL:-32}" \
  --image-batch-size 0 \
  --audio-batch-size 0 \
  --video-batch-size 0 \
  --request-timeout-seconds 300 \
  --tokenizer-trust-remote-code \
  --output-artifact-dir "$RUN_ROOT/aiperf" \
  --profile-export-prefix smoke \
  --ui none \
  --no-server-metrics 2>&1 | tee "$RUN_ROOT/aiperf.log"
```

## srt-slurm

When the repo supports it, prefer declarative configs as the durable benchmark definition:

```bash
uv run srtctl dry-run -f path/to/config.yaml
uv run srtctl apply -f path/to/config.yaml --bash | bash -n
```

For benchmark YAMLs:
- Inline the AIPerf command under `benchmark.type: custom`.
- Include `--ui none`, deterministic artifact dir/prefix, and usually `--no-server-metrics`.
- For local shared-node disagg in `srt-slurm`, use the repo's shared-node topology convention (for example `decode_nodes: 0` when decode shares the prefill node).
- Treat `srtctl apply --bash` output as the execution/rendering artifact, not a second hand-written source of truth.

## Verify Results

Check AIPerf JSON before quoting metrics:

```bash
python3 - "$RUN_ROOT/aiperf/smoke.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
error_counts = data.get("error_request_count") or {}
error_total = sum(v.get("value", 0) for v in error_counts.values() if isinstance(v, dict))
assert not data.get("was_cancelled"), "aiperf was cancelled"
assert not data.get("error_summary"), data.get("error_summary")
assert error_total == 0, error_counts
PY
```

Check tachometer output when enabled:

```bash
test -s "$RUN_ROOT/tachometer/run/final.parquet"
python3 - "$RUN_ROOT/tachometer/run/final.parquet" <<'PY'
import sys, pyarrow.parquet as pq
pf = pq.ParquetFile(sys.argv[1])
print({"rows": pf.metadata.num_rows, "cols": pf.metadata.num_columns, "columns": pf.schema.names})
PY
```

Capture the numbers that matter:
- TTFT, request latency, ITL, output token throughput, request throughput, request count.
- Error count and cancellation state.
- Tachometer row count and endpoint names.
- GPU memory after cleanup.

## Cleanup

Stop telemetry with SIGINT before killing the server so tachometer writes `final.parquet`. Then terminate the server process group and verify GPUs:

```bash
stop_tachometer
stop_process_group "$SERVER_PID"
sleep 2
nvidia-smi --query-gpu=index,name,memory.used,memory.total --format=csv,noheader
pgrep -af 'sglang|dynamo|vllm|trtllm|aiperf|tachometer-scraper' || true
```

## Datasets

Common local datasets:
- `~/datasets/long_multiturn_opus.jsonl` - 10 synthetic multi-turn sessions.
- `~/datasets/claude_history_sonnet.jsonl` - single real coding-agent session.
- `~/datasets/claude_history_10_sessions.jsonl` - 10 sessions, 585 turns.
- `~/datasets/claude_history_10_sessions_with_thinking.jsonl` - same with thinking blocks.

## Notes

- If the server hangs without logs, inspect the server log and live stacks before retrying blindly.
- For SGLang/Dynamo readiness, a successful `/v1/models` response can precede worker registration. Use a tiny chat completion before AIPerf.
- Server-specific flags such as memory fractions, TP/DP, cache settings, or connector backends belong in project configs or launch scripts, not hardcoded into this skill.
