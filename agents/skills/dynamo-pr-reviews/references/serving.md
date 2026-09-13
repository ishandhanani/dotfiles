# Dynamo serving validation

## Exact checkouts and comparison base

Resolve `REPO`, `PR`, and `ROOT` from the request and repository. Use the PR's actual base branch, including release branches. Run from the canonical repository without switching its branch:

```bash
PR_HEAD_SHA=$(gh pr view "$PR" --repo "$REPO" --json headRefOid --jq .headRefOid)
BASE_BRANCH=$(gh pr view "$PR" --repo "$REPO" --json baseRefName --jq .baseRefName)
git -C "$ROOT" fetch origin "refs/pull/$PR/head" "refs/heads/$BASE_BRANCH"
BASE_REF="refs/remotes/origin/review-base-$PR"
git -C "$ROOT" fetch origin "refs/heads/$BASE_BRANCH:$BASE_REF"
BASE_SHA=$(git -C "$ROOT" merge-base "$PR_HEAD_SHA" "$BASE_REF")
WORK="${ROOT}-wt/pr-$PR"
git -C "$ROOT" worktree add --detach "$WORK" "$PR_HEAD_SHA"
```

If the head moves during fetch, resolve and fetch again before claiming coverage. If a worktree already exists, inspect it; reuse only task-owned matching state or choose a fresh path. For A/B, add a separate detached worktree at `BASE_SHA`, with its own `.venv` and Cargo target. `HEAD~1` is not a general PR baseline. Record both full SHAs and the base branch. Keep model, traffic, hardware, and benchmark settings controlled; use a fresh server per phase and check ordering effects when measuring small deltas.

## Build the active worktree

```bash
cd "$WORK"
test -L .venv && { echo '.venv must be checkout-local' >&2; exit 1; }
test -x .venv/bin/python || uv venv .venv
source .venv/bin/activate
```

Read the checked-out dependency constraints and install the pinned SGLang backend. Inspect the source note's CUDA paths and service configuration. Rebuild Rust bindings if Rust/native inputs changed or the installed binding does not match this revision:

```bash
cd "$WORK/lib/bindings/python"
CARGO_TARGET_DIR="$WORK/target" maturin develop --uv
cd "$WORK"
uv pip install -e .
python -c 'import dynamo._core, dynamo.sglang, sglang; print(dynamo._core.__file__, dynamo.sglang.__file__, sglang.__version__)'
```

Verify Dynamo imports resolve inside this worktree. For a paired editable SGLang build, use `setup-dynamo-sglang-from-src` at recorded commits. Preserve the selected runtime dependency strategy; do not unconditionally upgrade or downgrade historical pins.

## Services and process ownership

Use the source note and current launch script for etcd/NATS requirements, ports, and caches. Reuse compatible services when permitted. Start task-owned services on available ports when necessary, record their PIDs or job IDs, and keep data/logs inside the task session. Do not replace shared services or install host packages unless provisioning is authorized.

For a local aggregated test, run the checked-out `examples/backends/sglang/launch/agg.sh` in its own process group. It can trap EXIT with `kill 0`, so isolation is essential:

```bash
setsid bash "$WORK/examples/backends/sglang/launch/agg.sh" \
  --model-path "$MODEL" >"$LOG_DIR/server.log" 2>&1 &
SERVER_PID=$!
```

Record `SERVER_PID` before doing other work. On cleanup, send TERM to this recorded process group, wait for exit, and escalate to KILL only if it remains alive. For scheduler workloads, clean up the recorded job. Never use a broad program-name kill. If a port is occupied by unrelated work, choose a different port or an isolated allocation.

For an srt-slurm benchmark, use `server-lifecycle` and its renderer-owned cleanup instead of creating a second permanent launch script.

## Readiness and the changed path

Use the current model-readiness endpoint and a bounded timeout, watch the launched process and logs for startup failure, then send one small inference request. The frontend's `/health` or HTTP port alone does not prove a worker is ready. The helper at `../server-lifecycle/scripts/wait_for_openai_ready.py` relative to this skill directory supports model/worker checks; confirm endpoint compatibility for the checked-out version.

For output formatting, compare identical deterministic streaming and non-streaming requests, including supported Unicode/tool-call shapes that exercise the change. Let streams finish; an early client disconnect can produce misleading cancellation errors.

For load tests, inspect `aiperf profile --help` from the installed version, pass explicit artifact paths, and disable the interactive UI. Use workload sizes representative of the hypothesis; verify request errors/cancellation before reporting TTFT, ITL, throughput, or latency. Save exact requests, response fields, metrics, and relevant log lines. Diagnose environment failures separately from PR regressions; use a baseline or dependency evidence before attributing a build failure to the PR.
