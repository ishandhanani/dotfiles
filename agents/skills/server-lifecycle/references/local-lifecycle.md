# Local lifecycle debugging

Resolve `SKILL_DIR` from this loaded skill directory. Use this template only for temporary local validation or renderer debugging; srt-slurm owns durable recipes. Keep paths and ports task-specific.

## Readiness Helper

Use the bundled helper instead of hand-writing curl/jq loops:

```bash
READY_SCRIPT="${READY_SCRIPT:-${SKILL_DIR:?set the loaded server-lifecycle skill directory}/scripts/wait_for_openai_ready.py}"
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
ARTIFACT_DIR="${AIPERF_ARTIFACT_DIR:-$(mktemp -d /tmp/aiperf-smoke.XXXXXX)}"
mkdir -p "$ARTIFACT_DIR"
SERVER_LOG="${SERVER_LOG:-$ARTIFACT_DIR/server.log}"
READY_SCRIPT="${READY_SCRIPT:-${SKILL_DIR:?set the loaded server-lifecycle skill directory}/scripts/wait_for_openai_ready.py}"
DYNAMO_ROOT="${DYNAMO_ROOT:?set the active checkout}"
SERVER_PID=""

cleanup() {
  local rc=$?
  trap - EXIT INT TERM
  if [[ -n "${SERVER_PID:-}" ]]; then
    echo "Stopping server process group -${SERVER_PID}"
    kill -TERM "-${SERVER_PID}" 2>/dev/null || true
    for attempt in {1..5}; do
      kill -0 "-${SERVER_PID}" 2>/dev/null || break
      sleep 1
    done
    if kill -0 "-${SERVER_PID}" 2>/dev/null; then
      kill -KILL "-${SERVER_PID}" 2>/dev/null || true
    fi
    wait "${SERVER_PID}" 2>/dev/null || true
  fi
  exit "$rc"
}
trap cleanup EXIT INT TERM

setsid "$DYNAMO_ROOT/examples/backends/sglang/launch/agg.sh" \
  --model-path "$MODEL" >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!

smoke_chat() {
  python3 - "$MODEL" >"$ARTIFACT_DIR/request.json" <<'PY'
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
    -d "@$ARTIFACT_DIR/request.json" >"$ARTIFACT_DIR/response.json"
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
