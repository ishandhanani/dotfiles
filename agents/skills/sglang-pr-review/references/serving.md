# Pure SGLang serving

In the detached PR worktree:

```bash
cd "$WORK"
test -L .venv && { echo '.venv must be checkout-local' >&2; exit 1; }
test -x .venv/bin/python || uv venv .venv
source .venv/bin/activate
uv pip install -e python
python -c 'import sglang; print(sglang.__version__, sglang.__file__)'
```

Verify the editable import belongs to this checkout. Resolve native wheels against its dependency constraints and the selected source's CUDA/toolchain; distinguish a missing environment prerequisite from a PR regression. For A/B, install each exact revision into its own worktree environment.

Inspect the checked-out server arguments and choose an unoccupied port. Example:

```bash
setsid python -m sglang.launch_server \
  --model-path "$MODEL" --port "$PORT" --enable-metrics \
  >"$LOG_DIR/server.log" 2>&1 &
SERVER_PID=$!
```

Add the flags the PR needs before the log redirection. Record the process group or scheduler job ID. Use bounded readiness polling, watch the process/logs, and send a small completion before traffic. A liveness endpoint alone is insufficient. Clean only this recorded process group with TERM, escalating to KILL if it fails to exit; preserve unrelated servers and benchmark clients.

Exercise the changed invariant: limited cache capacity for eviction, shared prefixes for prefix reuse, long prompts for chunked prefill, or the specific kernel/model topology. Trace changed contracts through callers and consumers. Inspect the relevant response, counter, histogram, or log, not only aggregate throughput.

Inspect the installed `aiperf profile --help` for current flags. Use explicit artifact paths and noninteractive output. Verify error/cancel counts and keep warmup outside measured samples. For an A/B claim, report exact base/head SHAs, model, request shape, concurrency, and comparable TTFT/ITL/throughput measurements. For srt-slurm recipes, use `server-lifecycle` rather than creating a competing permanent launcher.
