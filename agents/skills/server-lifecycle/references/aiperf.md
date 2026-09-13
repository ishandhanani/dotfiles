# AIPerf and result interpretation

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
