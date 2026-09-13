# Renderer validation

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
- Clean only the recorded task-owned PIDs/process groups or scheduler jobs. Matching the same user, script name, model, or port is not enough to establish ownership of another workload.
- Wait for real readiness. `/health` alone is not enough for Dynamo/SGLang; poll model readiness, then send a tiny chat completion before AIPerf.
- Use the helper in the skill's `scripts/wait_for_openai_ready.py` to poll `/v1/models/<model>/ready` and optional `/health` instance counts before the tiny chat completion; do not benchmark just because the HTTP port is open.
- Treat metrics endpoints as generated/configured by `telemetry:`. For disagg, the telemetry config should include every backend/frontend endpoint from topology.
- Start configured telemetry before load and stop it during lifecycle cleanup.
- Run the benchmark command after readiness.
- Verify AIPerf JSON before reporting numbers.
- Verify GPU/process cleanup after each phase.

If any item is missing, patch the `srt-slurm` renderer/template rather than adding a parallel script to the recipe.
