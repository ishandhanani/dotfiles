---
name: server-lifecycle
description: Manage inference server lifecycle through NVIDIA srt-slurm: author benchmark YAMLs, render lifecycle bash with `srtctl apply --bash`, run SGLang/Dynamo/AIPerf jobs, collect tachometer telemetry, validate artifacts, and improve the srtctl lifecycle renderer. Use for server lifecycle tasks where srt-slurm is the unified control plane.
user-invocable: true
---

# Server Lifecycle

Use `srt-slurm` as the unified control plane for server lifecycle work. YAML is the durable benchmark definition and rendered bash is the execution artifact. Do not maintain a separate hand-written launch script for the same benchmark unless it is temporary local validation glue.

Use this workflow for SGLang/Dynamo/vLLM/TRT-LLM benchmark recipes, local smoke runs, SLURM jobs, `srtctl apply --bash`, AIPerf, and tachometer.

## Source Of Truth

- Author or update `srt-slurm` YAML first.
- Validate renderer behavior with `srtctl dry-run` and `srtctl apply --bash`.
- If the rendered bash is missing lifecycle behavior, fix the renderer/templates in `srt-slurm`; do not work around it with a second long-lived shell script.
- Use local bash only to test a launch pattern before encoding it in YAML or renderer logic.

## Orient

Before editing:

```bash
git status --short
rg -n "benchmark:|run_benchmark|apply --bash|lifecycle|tachometer|aiperf" src tests recipes examples
rg --files recipes examples | rg 'sglang|dynamo|vllm|trtllm'
```

Read the closest existing recipe and backend launch script. For Dynamo/SGLang, inspect `examples/backends/sglang/launch/{agg,disagg}.sh` in the Dynamo checkout when available, especially its traps and process cleanup.

## YAML Recipe Rules

For benchmark YAMLs:

- Put model identity, topology, backend config, and benchmark command in YAML.
- Use `benchmark.type: custom` for inline AIPerf until a first-class benchmark type exists.
- Keep artifact paths deterministic with `AIPERF_ARTIFACT_DIR`, `--output-artifact-dir`, and `--profile-export-prefix`.
- Always pass `--ui none`.
- Usually pass `--no-server-metrics` when tachometer/direct scraping owns telemetry. This avoids SGLang nullable Prometheus metric issues and keeps AIPerf focused on request records.
- For local shared-node disagg in `srt-slurm`, use the repo's shared-node convention, for example `decode_nodes: 0` when decode shares the prefill node.
- For SGLang disagg, put connector/backend flags in `backend.sglang_config.prefill` and `.decode` using the repo's schema. Validate with `dry-run`; do not guess unsupported YAML keys.

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
- Wait for real readiness. `/health` and `/v1/models` are not enough for Dynamo/SGLang; send a tiny chat completion before AIPerf.
- Treat metrics endpoints as optional/configured. For disagg, wait/scrape every endpoint explicitly.
- Start tachometer before load, stop it with SIGINT, and verify `final.parquet`.
- Run the benchmark command after readiness.
- Verify AIPerf JSON before reporting numbers.
- Verify GPU/process cleanup after each phase.

If any item is missing, patch the `srt-slurm` renderer/template rather than adding a parallel script to the recipe.

## Tachometer

If `tachometer-scraper` is not installed and the user wants telemetry:

```bash
git clone git@github.com:NVIDIA-dev/warnold-tachometer.git /ephemeral/warnold-tachometer
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/ephemeral/cargo-target}"
cargo build --release --manifest-path /ephemeral/warnold-tachometer/tachometer-scraper/Cargo.toml
find "$CARGO_TARGET_DIR" /ephemeral/warnold-tachometer -path '*/release/tachometer-scraper' -type f 2>/dev/null
```

Rendered/local lifecycle scripts should run tachometer like this:

```bash
tachometer-scraper \
  --endpoint worker=http://localhost:8081/metrics \
  --storage "$ARTIFACT_DIR/tachometer/run" \
  --local-dir "$ARTIFACT_DIR/tachometer-local" \
  --freq "${TACHOMETER_FREQ:-1.0}" \
  --save-interval 2 \
  --sync-interval 0 >"$ARTIFACT_DIR/tachometer.log" 2>&1 &
TACHOMETER_PID=$!
# ...benchmark...
kill -INT "$TACHOMETER_PID"; wait "$TACHOMETER_PID" 2>/dev/null || true
```

For disagg, name endpoints:

```bash
--endpoint prefill=http://localhost:8081/metrics \
--endpoint decode=http://localhost:8082/metrics
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
- Usually `--no-server-metrics` when tachometer/direct scrape is enabled.
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

Verify tachometer parquet:

```bash
test -s "$ARTIFACT_DIR/tachometer/run/final.parquet"
python3 - "$ARTIFACT_DIR/tachometer/run/final.parquet" <<'PY'
import sys, pyarrow.parquet as pq
pf = pq.ParquetFile(sys.argv[1])
print({"rows": pf.metadata.num_rows, "cols": pf.metadata.num_columns, "columns": pf.schema.names})
PY
```

Report:

- Artifact root.
- AIPerf request count, error/cancel state, TTFT, latency, ITL, throughput.
- Tachometer row counts and endpoint names.
- GPU memory/process cleanup state.

## Cleanup

Before launch, list candidate stale processes and only kill known benchmark-owned processes:

```bash
pgrep -afu "$USER" '[s]glang|[d]ynamo|[v]llm|[t]rtllm|[a]iperf profile|[t]achometer-scraper' || true
pkill -9 -u "$USER" -f '[a]iperf profile|[t]achometer-scraper' 2>/dev/null || true
# Only after confirming they belong to this benchmark:
# pkill -TERM -u "$USER" -f 'path/to/launch.sh|--port 8000|--model-path Qwen/Qwen3-0.6B' 2>/dev/null || true
sleep 3
nvidia-smi --query-gpu=index,name,memory.used,memory.total --format=csv,noheader
```

After each phase:

```bash
nvidia-smi --query-gpu=index,name,memory.used,memory.total --format=csv,noheader
pgrep -afu "$USER" '[s]glang|[d]ynamo|[v]llm|[t]rtllm|[a]iperf|[t]achometer-scraper' || true
```

## Memory

After meaningful benchmark results or renderer decisions, invoke `/memory-log` and include:

- Config path and commit.
- Render/validation commands.
- Artifact root.
- Key metrics and cleanup state.
