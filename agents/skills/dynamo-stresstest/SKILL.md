---
name: dynamo-stresstest
description: Run local Dynamo stress tests by launching mocker and frontend with raised file descriptor limits, delaying AIPerf start, capturing logs, and shutting all processes down cleanly. Use for high-concurrency mocker reproductions, file-descriptor failures, frontend request failures, and local SGLang-scheduler stress tests.
---

# Dynamo Stress Test

Use this skill for a local high-concurrency Dynamo stress run with mocker, frontend, and `aiperf`. Prefer the three-terminal launch flow so each process has separate live logs. Use the one-shell orchestration only when the user explicitly requests single-shell automation.

Keep bulky raw service logs, AIPerf artifacts, JSON, traces, and other machine-generated output under `/tmp`. After a meaningful run, invoke [`$memory-log`](../memory-log/SKILL.md). Record the repository, commit, exact launch configuration, process IDs, artifact paths, exit statuses, health signals, cleanup result, and conclusions.

## What This Skill Does

- Raises `ulimit -n` in the same shell that launches each child process.
- In the default path, launches mocker, frontend, and delayed `aiperf` in three separate terminals.
- In the single-shell fallback path, starts `dynamo.mocker` and `dynamo.frontend` in the background.
- Waits a short period before starting `aiperf`.
- Captures logs under `/tmp` in the single-shell mode.
- Sends termination signals to the background services after `aiperf` exits in the single-shell mode.
- Waits for clean shutdown and reports exit codes in the single-shell mode.

## Environment Rules

- Resolve the repository in scope with `git rev-parse --show-toplevel`.
- Make sure that the repository is a Dynamo checkout and run from its root.
- If no Dynamo checkout is in scope, read `~/memory/INDEX.md` and offer one strong candidate. If discovery is ambiguous, stop instead of guessing.
- Always use the repository virtual environment: `.venv/bin/python`.
- Use `uv pip` for missing dependencies.
- Export at least:
  - `ETCD_ENDPOINTS=http://localhost:2379`
  - `NATS_SERVER=nats://localhost:4222`
- Assume that etcd and NATS are already running unless the user explicitly requests their startup.

## Default Local Shape

Before the stress run, make sure that the local control-plane dependencies are reachable. Inspect these resources:

- etcd on `localhost:2379`
- NATS on `localhost:4222`
- stale `aiperf` processes
- stale `dynamo.mocker` processes
- stale `dynamo.frontend` processes, especially a process bound to `localhost:8000`

List each candidate process and inspect its command, PID, and parent PID. Terminate only a process that belongs to an earlier local stress run. If an unrelated process owns port `8000`, stop and report it. If etcd or NATS is unavailable, stop and correct that failure before launch.

Use this configuration for the closest local mocker reproduction of the tested aggregated SGLang shape:

- backend: `dynamo.mocker`
- frontend: `dynamo.frontend --router-mode round-robin --http-port 8000`
- mocker flags:
  - `--engine-type sglang`
  - `--num-workers 1`
  - `--data-parallel-size 4`
  - `--no-enable-prefix-caching`
- AIPerf shape:
  - `isl=1000`
  - `osl=1`
  - user-provided concurrency and request count

## Default Three-Terminal Flow

Use this flow unless the user explicitly requests one-shell automation:

1. Make sure that `localhost:2379` and `localhost:4222` are reachable.
2. Inspect `localhost:8000` and stale processes from earlier local stress runs.
3. Terminate only confirmed stale stress processes.
4. Open one terminal for mocker with `ulimit -n 65536`.
5. Open one terminal for frontend on `8000` with `ulimit -n 65536`.
6. Open one terminal for `aiperf` with `ulimit -n 65536` and a 10-second launch delay.

This flow gives separate live logs and avoids a stale one-shell supervisor.

## Proven Orchestration Pattern

This pattern completed locally with zero exit statuses and graceful service shutdown.

Use a single shell command with this shape. Use a 60-second command timeout by default. Increase it only when the user explicitly requests a longer run.

```bash
set -euo pipefail
mkdir -p /tmp/dynamo-stress
rm -f /tmp/dynamo-stress/mocker.log /tmp/dynamo-stress/frontend.log /tmp/dynamo-stress/aiperf.log /tmp/dynamo-stress/runner.log
(
  ulimit -n 65536
  export ETCD_ENDPOINTS=http://localhost:2379
  export NATS_SERVER=nats://localhost:4222
  export MODEL=Qwen/Qwen3-0.6B

  cleanup() {
    set +e
    if [ -n "${AIPERF_PID:-}" ]; then kill -TERM "$AIPERF_PID" 2>/dev/null || true; fi
    if [ -n "${FRONTEND_PID:-}" ]; then kill -TERM "$FRONTEND_PID" 2>/dev/null || true; fi
    if [ -n "${MOCKER_PID:-}" ]; then kill -TERM "$MOCKER_PID" 2>/dev/null || true; fi
    wait "$AIPERF_PID" 2>/dev/null || true
    wait "$FRONTEND_PID" 2>/dev/null || true
    wait "$MOCKER_PID" 2>/dev/null || true
  }
  trap cleanup EXIT INT TERM

  .venv/bin/python -m dynamo.mocker \
    --model-path "$MODEL" \
    --model-name "$MODEL" \
    --endpoint dyn://test.mocker.generate \
    --engine-type sglang \
    --num-workers 1 \
    --data-parallel-size 4 \
    --block-size 16 \
    --sglang-page-size 16 \
    --sglang-max-prefill-tokens 81920 \
    --sglang-chunked-prefill-size 81920 \
    --max-num-seqs 2048 \
    --max-num-batched-tokens 81920 \
    --speedup-ratio 1.0 \
    --no-enable-prefix-caching \
    > /tmp/dynamo-stress/mocker.log 2>&1 &
  MOCKER_PID=$!

  .venv/bin/python -m dynamo.frontend \
    --router-mode round-robin \
    --http-port 8000 \
    > /tmp/dynamo-stress/frontend.log 2>&1 &
  FRONTEND_PID=$!

  sleep 10

  .venv/bin/aiperf profile \
    --model "$MODEL" \
    --tokenizer "$MODEL" \
    --url http://localhost:8000 \
    --synthetic-input-tokens-mean 1000 \
    --synthetic-input-tokens-stddev 0 \
    --output-tokens-mean 1 \
    --output-tokens-stddev 0 \
    --concurrency 4096 \
    --request-count 12288 \
    --num-dataset-entries 12288 \
    --random-seed 0 \
    --artifact-dir /tmp/aiperf-mocker-formal-12288 \
    --endpoint-type chat \
    --endpoint v1/chat/completions \
    --streaming \
    --extra-inputs ignore_eos:true \
    --no-gpu-telemetry \
    -H 'Authorization: Bearer NOT USED' \
    -H 'Accept: text/event-stream' \
    > /tmp/dynamo-stress/aiperf.log 2>&1 &
  AIPERF_PID=$!

  wait "$AIPERF_PID"
  AIPERF_STATUS=$?

  kill -TERM "$FRONTEND_PID" "$MOCKER_PID"
  wait "$FRONTEND_PID"
  FRONTEND_STATUS=$?
  wait "$MOCKER_PID"
  MOCKER_STATUS=$?

  printf 'aiperf=%s frontend=%s mocker=%s\n' "$AIPERF_STATUS" "$FRONTEND_STATUS" "$MOCKER_STATUS" > /tmp/dynamo-stress/runner.log
)
cat /tmp/dynamo-stress/runner.log
```

## Log Checks

After the run, inspect:

- `/tmp/dynamo-stress/runner.log`
- `/tmp/dynamo-stress/frontend.log`
- `/tmp/dynamo-stress/mocker.log`
- `/tmp/dynamo-stress/aiperf.log`

Healthy signals:

- runner log shows `aiperf=0 frontend=0 mocker=0`
- frontend log shows request receive/completion lines and `http response sent status=200`
- mocker log shows `request received` and `request completed`
- frontend and mocker both log graceful shutdown

Report these failure signals explicitly:

- `Too many open files (os error 24)`
- TCP accept failures from `dynamo_runtime::pipeline::network::tcp::server`
- request-level `500` responses from the frontend
- background services that do not exit after `SIGTERM`

## Notes

- Set `ulimit -n` in the same shell that launches the child process.
- If the user requests separate GUI terminals, use them directly.
- If the user requests a lighter run first, reduce `--concurrency` and `--request-count`. Keep the same orchestration structure.
