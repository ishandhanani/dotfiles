---
name: server-lifecycle
description: "Manage inference server lifecycle through NVIDIA srt-slurm: author benchmark YAMLs, render lifecycle bash with `srtctl apply --bash`, run SGLang/Dynamo/AIPerf jobs, configure first-class telemetry/observability, validate artifacts, and improve the srtctl lifecycle renderer. Use for server lifecycle tasks where srt-slurm is the unified control plane."
---

# Server Lifecycle

Use `srt-slurm` as the unified control plane for server lifecycle work. YAML is the durable benchmark definition and rendered bash is the execution artifact. Do not maintain a separate hand-written launch script for the same benchmark unless it is temporary local validation glue.

Use this workflow for SGLang/Dynamo/vLLM/TRT-LLM benchmark recipes, local smoke runs, SLURM jobs, `srtctl apply --bash`, AIPerf, and srt-slurm telemetry.

## Source Of Truth

- Author or update `srt-slurm` YAML first.
- Validate renderer behavior with `srtctl dry-run` and `srtctl apply --bash`.
- If the rendered bash is missing lifecycle behavior, fix the renderer/templates in `srt-slurm`; do not work around it with a second long-lived shell script.
- Use local bash only to test a launch pattern before encoding it in YAML or renderer logic.

## Orient

Before editing:

```bash
git status --short
rg -n "benchmark:|run_benchmark|apply --bash|lifecycle|telemetry|observability|aiperf" src tests recipes examples
rg --files recipes examples | rg 'sglang|dynamo|vllm|trtllm'
```

Read the closest existing recipe and backend launch script. For Dynamo/SGLang, inspect `examples/backends/sglang/launch/{agg,disagg}.sh` in the Dynamo checkout when available, especially its traps and process cleanup.

## YAML Recipe Rules

For benchmark YAMLs:

- Put model identity, topology, backend config, and benchmark command in YAML.
- Use `benchmark.type: custom` for inline AIPerf until a first-class benchmark type exists.
- Keep artifact paths deterministic with `AIPERF_ARTIFACT_DIR`, `--output-artifact-dir`, and `--profile-export-prefix`.
- Always pass `--ui none`.
- Usually pass `--no-server-metrics` when `srt-slurm` telemetry owns metrics. This avoids SGLang nullable Prometheus metric issues and keeps AIPerf focused on request records.
- For local shared-node disagg in `srt-slurm`, use the repo's shared-node convention, for example `decode_nodes: 0` when decode shares the prefill node.
- For SGLang disagg, put connector/backend flags in `backend.sglang_config.prefill` and `.decode` using the repo's schema. Validate with `dry-run`; do not guess unsupported YAML keys.

## Telemetry And Observability

Use first-class `srt-slurm` config. Do not embed raw tachometer/scraper commands in benchmark YAML.

- `telemetry:` is the metrics scraper path. It generates `telemetry_config.toml`, starts DCGM/node exporters, scrapes backend/frontend metrics from the rendered topology, and stores artifacts under `logs/<storage_subdir>`.
- `observability:` is for OTEL tracing env injection (`enable_otel`, `otel_endpoint`), not metrics scraping.
- Resolve `container_image`, `dcgm_exporter.container_image`, and `node_exporter.container_image` through `srtslurm.yaml` container aliases when possible.

Telemetry YAML shape:

```yaml
telemetry:
  enabled: true
  container_image: "telemetry-scraper"
  storage_subdir: "telemetry"
  default_frequency: 1.0
  sync_interval_secs: 0
  dcgm_exporter:
    container_image: "dcgm-exporter"
    port: 9401
  node_exporter:
    container_image: "node-exporter"
    port: 9101
```

Optional OTEL tracing:

```yaml
observability:
  enable_otel: true
  otel_endpoint: "http://<otel-collector>:4317"
```

For standalone `--bash` lifecycle behavior, use the renderer's built-in telemetry hooks and controls (`SRTCTL_ENABLE_TACHOMETER`, `SRTCTL_REQUIRE_TACHOMETER`, `SRTCTL_TACHOMETER_ARGS`) only when debugging that path. Prefer YAML-level `telemetry:` for normal recipes.

Inline AIPerf command shape:

```yaml
benchmark:
  type: "custom"
  command: |
    set -euo pipefail
    ARTIFACT_DIR="${AIPERF_ARTIFACT_DIR:-/logs/aiperf/smoke}"
    mkdir -p "$ARTIFACT_DIR"
    aiperf profile Qwen/Qwen3-0.6B \
      --url http://localhost:8000 \
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
      --output-artifact-dir "$ARTIFACT_DIR" \
      --profile-export-prefix smoke \
      --ui none \
      --no-server-metrics
```

## Render And Validate

Run these before any real execution:

```bash
uv run srtctl dry-run -f path/to/config.yaml
uv run srtctl apply -f path/to/config.yaml --bash > /tmp/srtctl_rendered.sh
bash -n /tmp/srtctl_rendered.sh
```

For PRs touching renderer behavior, add or update tests around the rendered script:

```bash
uv run pytest tests/test_lifecycle_render.py tests/test_submit_cli.py -q
```

Use `make check` when changes touch shared schema, CLI, topology, or backend rendering.

## Rendered Bash Requirements

The rendered bash should handle the lifecycle end to end:

- `set -Eeuo pipefail`.
- Trap `EXIT INT TERM`.
- Start server process(es), save PIDs, and clean by PID/process group.
- Use `setsid` around child launch scripts that trap `kill 0`, such as Dynamo example launchers, so their cleanup cannot kill the parent lifecycle runner.
- Avoid broad server `pkill`; list candidates first and narrow cleanup to user-owned benchmark processes, known launch scripts, model, or ports.
- Wait for real readiness. `/health` alone is not enough for Dynamo/SGLang; poll model readiness, then send a tiny chat completion before AIPerf.
- Use `scripts/wait_for_openai_ready.py` to poll `/v1/models/<model>/ready` and optional `/health` instance counts before the tiny chat completion; do not benchmark just because the HTTP port is open.
- Treat metrics endpoints as generated/configured by `telemetry:`. For disagg, the telemetry config should include every backend/frontend endpoint from topology.
- Start configured telemetry before load and stop it during lifecycle cleanup.
- Run the benchmark command after readiness.
- Verify AIPerf JSON before reporting numbers.
- Verify GPU/process cleanup after each phase.

If any item is missing, patch the `srt-slurm` renderer/template rather than adding a parallel script to the recipe.

## Readiness Helper

Use the bundled helper instead of hand-writing curl/jq loops:

```bash
READY_SCRIPT="${READY_SCRIPT:-${CODEX_HOME:-$HOME/.codex}/skills/server-lifecycle/scripts/wait_for_openai_ready.py}"
python3 "$READY_SCRIPT" --base-url "$BASE_URL" --model "$MODEL"
python3 "$READY_SCRIPT" --base-url "$BASE_URL" --model "$MODEL" --expect-worker aggregated=1
python3 "$READY_SCRIPT" --base-url "$BASE_URL" --model "$MODEL" --expect-worker prefill=1 --expect-worker decode=1
```

The helper prefers `GET /v1/models/<model>/ready`, which exposes model-level readiness and worker-type counts (`aggregated`, `prefill`, `decode`, `encode`). Use `--min-health-instances N` only as an extra liveness guard because `/health` lists discovery instances across endpoints, not model-specific readiness.

## Bash Lifecycle Template

Use this shape when the rendered lifecycle owns a local server process. Dynamo launch scripts often trap `EXIT` and call `kill 0`; run them in their own session so their cleanup only tears down their process group.

```bash
set -Eeuo pipefail

MODEL="${MODEL:-Qwen/Qwen3-0.6B}"
BASE_URL="${BASE_URL:-http://localhost:8000}"
ARTIFACT_DIR="${AIPERF_ARTIFACT_DIR:-/tmp/aiperf-smoke}"
SERVER_LOG="${SERVER_LOG:-/tmp/server.log}"
READY_SCRIPT="${READY_SCRIPT:-${CODEX_HOME:-$HOME/.codex}/skills/server-lifecycle/scripts/wait_for_openai_ready.py}"
SERVER_PID=""

cleanup() {
  local rc=$?
  trap - EXIT INT TERM
  if [[ -n "${SERVER_PID:-}" ]]; then
    echo "Stopping server process group -${SERVER_PID}"
    kill -TERM "-${SERVER_PID}" 2>/dev/null || true
    sleep 5
    kill -KILL "-${SERVER_PID}" 2>/dev/null || true
    wait "${SERVER_PID}" 2>/dev/null || true
  fi
  exit "$rc"
}
trap cleanup EXIT INT TERM

setsid /ephemeral/dynamo/examples/backends/sglang/launch/agg.sh \
  --model-path "$MODEL" >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!

smoke_chat() {
  python3 - "$MODEL" >/tmp/server-smoke-request.json <<'PY'
import json
import sys

print(json.dumps({
  "model": sys.argv[1],
  "messages": [{"role": "user", "content": "hello"}],
  "max_tokens": 1,
}))
PY
  curl -sf "$BASE_URL/v1/chat/completions" \
    -H 'Content-Type: application/json' \
    -d @/tmp/server-smoke-request.json >/tmp/server-smoke.json
}

python3 "$READY_SCRIPT" \
  --base-url "$BASE_URL" \
  --model "$MODEL" \
  --expect-worker aggregated=1 \
  --watch-pid "$SERVER_PID" \
  --timeout "${MODEL_READY_TIMEOUT:-3600}" \
  --interval "${MODEL_READY_SLEEP:-5}"
smoke_chat

mkdir -p "$ARTIFACT_DIR"
aiperf profile "$MODEL" \
  --url "$BASE_URL" \
  --endpoint-type chat \
  --streaming \
  --concurrency "${AIPERF_CONCURRENCY:-2}" \
  --request-count "${AIPERF_REQUEST_COUNT:-8}" \
  --warmup-request-count "${AIPERF_WARMUP_REQUEST_COUNT:-1}" \
  --isl "${AIPERF_ISL:-128}" \
  --osl "${AIPERF_OSL:-32}" \
  --request-timeout-seconds 300 \
  --tokenizer-trust-remote-code \
  --output-artifact-dir "$ARTIFACT_DIR" \
  --profile-export-prefix smoke \
  --ui none \
  --no-server-metrics
```

## AIPerf Flags

Find flags from the installed version:

```bash
aiperf profile --help | sed -n '1,220p'
rg -n "no-server-metrics|output-artifact-dir|profile-export-prefix|ui" ~/aiperf 2>/dev/null || true
```

Defaults for agent-run `srt-slurm` benchmarks:

- Smoke: concurrency 1-2, request count 5-10, warmup 1.
- Load: concurrency 16-32, fresh server per phase.
- Always `--ui none`.
- Usually `--no-server-metrics` when `srt-slurm` telemetry is enabled.
- Always explicit `--output-artifact-dir` and `--profile-export-prefix`.
- Use `--tokenizer-trust-remote-code` for HF models that need it.
- If exact OSL matters, add server-supported `ignore_eos` or `min_tokens`; `--osl` alone may not force generation length.

## Result Verification

Verify AIPerf JSON:

```bash
python3 - "$ARTIFACT_DIR/smoke.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
error_counts = data.get("error_request_count") or {}
error_total = sum(v.get("value", 0) for v in error_counts.values() if isinstance(v, dict))
assert not data.get("was_cancelled"), "aiperf was cancelled"
assert not data.get("error_summary"), data.get("error_summary")
assert error_total == 0, error_counts
PY
```

Verify telemetry artifacts when `telemetry.enabled`:

```bash
test -f "$LOG_DIR/telemetry_config.toml"
test -d "$LOG_DIR/telemetry"
find "$LOG_DIR/telemetry" -type f | head
```

Report:

- Artifact root.
- AIPerf request count, error/cancel state, TTFT, latency, ITL, throughput.
- Telemetry storage path, endpoint names from `telemetry_config.toml`, and scraper/exporter log status.
- GPU memory/process cleanup state.

## Cleanup

Before launch, list candidate stale processes and only kill known benchmark-owned processes:

```bash
pgrep -afu "$USER" '[s]glang|[d]ynamo|[v]llm|[t]rtllm|[a]iperf profile|[t]elemetry-scraper|[d]cgm-exporter|[n]ode_exporter' || true
pkill -9 -u "$USER" -f '[a]iperf profile' 2>/dev/null || true
# Only after confirming they belong to this benchmark:
# pkill -TERM -u "$USER" -f 'path/to/launch.sh|--port 8000|--model-path Qwen/Qwen3-0.6B' 2>/dev/null || true
sleep 3
nvidia-smi --query-gpu=index,name,memory.used,memory.total --format=csv,noheader
```

After each phase:

```bash
nvidia-smi --query-gpu=index,name,memory.used,memory.total --format=csv,noheader
pgrep -afu "$USER" '[s]glang|[d]ynamo|[v]llm|[t]rtllm|[a]iperf|[t]elemetry-scraper|[d]cgm-exporter|[n]ode_exporter' || true
```

## Memory

After meaningful benchmark results or renderer decisions, invoke `/memory-log` and include:

- Config path and commit.
- Render/validation commands.
- Artifact root.
- Key metrics and cleanup state.
