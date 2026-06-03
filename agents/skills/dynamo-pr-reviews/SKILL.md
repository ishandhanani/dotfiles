---
name: dynamo-pr-reviews
description: Clone/checkout an ai-dynamo/dynamo PR, build it (maturin + editable Python), bring up etcd/NATS, run the end-to-end aggregated server via the repo's examples/backends/sglang/launch/agg.sh, drive load with uvx aiperf, verify the change empirically, then post a scoped evidence-backed GitHub review. Use when asked to test/try/review a Dynamo PR (e.g. "test ai-dynamo/dynamo#10254", "review this dynamo PR").
user-invocable: true
---

# Dynamo PR Review

Empirical, end-to-end workflow for testing an `ai-dynamo/dynamo` PR and leaving a scoped, evidence-backed review.

**Principle: read the diff to form hypotheses, then prove or refute them by running the code.** The end-to-end check is the repo's own `examples/backends/sglang/launch/agg.sh` (aggregated serving: one frontend + one SGLang worker on a single GPU), driven with real traffic.

Sibling skill: `sglang-pr-review` (pure SGLang). This one is for the Dynamo serving layer; it brings up the full frontend + worker stack.

## Boundaries — read-only on the PR

This skill **tests and reviews**; it never changes the PR. The PR author owns every code change.

- **Never** commit/push to the PR branch or the author's fork, never force-push, never apply suggestions or `gh pr` mutations (no edit, no commit-to-branch, no merge/close). You are a reviewer, not a committer.
- Any local edits needed to get the build/test running are **throwaway** — discarded at cleanup, never pushed anywhere.
- The **only** outbound action is leaving a review *comment* (findings + evidence), and **only after the user explicitly approves sharing it**. Default to producing the review locally and prompting the user to share.
- If you find a fix, **describe it in the review** for the author to apply — do not apply it for them.

## Hardware fit — check first

Default target: **1× L4** (~24 GB, Ada sm_89, single GPU). `agg.sh` is single-GPU aggregated serving.

After reading the PR, **stop and tell the user** if testing it needs more than 1 GPU / 24 GB, e.g.:
- Disaggregated serving (`disagg.sh` needs ≥2 GPUs: separate prefill + decode workers).
- A model that won't fit in 24 GB even quantized, or TP/PP/DP/EP > 1.
- Multi-node, or a GPU arch the L4 lacks (Hopper/Blackwell-only kernels, fp4).

Otherwise almost any change is testable with a **small model on 1 GPU** (default `Qwen/Qwen3-0.6B`) — the model is just a vehicle for the changed code path. Pick a model only as big as needed to exercise the change.

## Step 0 — Inputs

Confirm: **PR number** (repo defaults to `ai-dynamo/dynamo`), and anything the PR needs (a model, flag, or request shape — e.g. a tool-calling change needs a request with `tools` + `tool_choice`).

## Step 1 — Checkout the PR

Dynamo carries a Rust core, so reuse the canonical build tree rather than a throwaway clone (a clean clone would recompile Rust from scratch):

```bash
PR=<number>
cd /ephemeral/dynamo
# STOP and ask only on *tracked* modifications/staged changes (the user's work).
# Untracked files are fine — `gh pr checkout` ignores them.
git status --porcelain | grep -vE '^\?\?' && echo "tracked changes present -> STOP, ask the user" || echo "no tracked changes, safe to proceed"
git fetch origin && git checkout main && git pull --ff-only
ORIG_REF=$(git rev-parse --abbrev-ref HEAD)   # to restore later
gh pr checkout $PR
git log --oneline -1
```

Read the diff and plan:
```bash
gh pr diff $PR --repo ai-dynamo/dynamo | tee /tmp/dyn-pr-$PR.diff
gh pr diff $PR --repo ai-dynamo/dynamo --name-only
```
Note whether the diff touches **Rust** (`lib/**/*.rs`, `*/Cargo.toml`) or is **Python-only** — it decides the build in Step 2. Form concrete expectations (what should change in responses / logs / metrics / perf) and grep for any caller the diff might have missed.

## Step 2 — Build

The venv at `/ephemeral/dynamo/.venv` already has the Rust `_core` binding and the SGLang backend installed. Rebuild only what changed:

```bash
source /ephemeral/dynamo/.venv/bin/activate
# Rust touched? rebuild the binding (slow, incremental):
cd /ephemeral/dynamo/lib/bindings/python && maturin develop --uv
# Always refresh the Python package (fast):
cd /ephemeral/dynamo && uv pip install -e .
python -c "import dynamo.sglang, sglang; print('ok', sglang.__version__)"
```
Python-only PRs need only the `uv pip install -e .` (often the editable tree is already live — just relaunch the server). If `import sglang` fails, the backend isn't installed — install it (`uv pip install -e <sglang-checkout>/python` or `pip install "sglang[...]"`) before launching.

## Step 3 — Bring up etcd + NATS

Dynamo needs etcd (discovery) and NATS (transport). Reuse if present, else start them; handle a busy 2379 (a k8s etcd may hold it) by using an alternate port:

```bash
# NATS (default nats://localhost:4222)
pgrep -x nats-server >/dev/null || nats-server -p 4222 >/tmp/nats.log 2>&1 &

# etcd: prefer a usable 2379; else REUSE a healthy standalone etcd on 12379; else start one.
# (Check 12379 before starting -- otherwise you spawn a second etcd that dies with
#  "bind: address already in use" on the peer port and dumps a scary stacktrace.)
if curl -sf http://127.0.0.1:2379/health >/dev/null 2>&1; then
  : # default etcd on 2379 is reachable over plain http -- use it
elif curl -sf http://127.0.0.1:12379/health >/dev/null 2>&1; then
  export ETCD_ENDPOINTS=http://127.0.0.1:12379   # reuse already-running standalone etcd
else
  etcd --data-dir /tmp/dyn-etcd --name dyn \
    --listen-client-urls http://127.0.0.1:12379 --advertise-client-urls http://127.0.0.1:12379 \
    --listen-peer-urls http://127.0.0.1:12390 --initial-advertise-peer-urls http://127.0.0.1:12390 \
    --initial-cluster dyn=http://127.0.0.1:12390 >/tmp/dyn-etcd.log 2>&1 &
  sleep 3; export ETCD_ENDPOINTS=http://127.0.0.1:12379
fi
```
`ETCD_ENDPOINTS` redirects Dynamo's discovery backend; `NATS_SERVER` overrides NATS if needed. (Note: a k8s etcd on 2379 typically serves **https with client-cert auth**, so the plain-http health probe correctly fails and you fall through to 12379.)

## Step 4 — Launch agg.sh (background)

`agg.sh` starts `dynamo.frontend` (OpenAI API on :8000) + one `dynamo.sglang` worker (system metrics on :8081). It forwards unknown flags to the worker.

```bash
pkill -9 -f "dynamo.sglang" 2>/dev/null; pkill -9 -f "dynamo.frontend" 2>/dev/null; sleep 2
cd /ephemeral/dynamo
ETCD_ENDPOINTS=${ETCD_ENDPOINTS:-http://127.0.0.1:2379} DYN_LOG=debug \
  bash examples/backends/sglang/launch/agg.sh --model-path Qwen/Qwen3-0.6B \
  > /tmp/dyn-agg-$PR.log 2>&1 &
```
**Launch the `bash agg.sh …` line as its OWN detached background task** (the harness background-run, or `setsid`). `agg.sh` sets `trap 'kill 0' EXIT`, so if you chain it after `cd`/`source`/`export` inside a single `set -e` shell the trap can tear down the process group and you get exit 1 with no log file. Keep env vars on the same line as the `bash agg.sh` invocation, nothing chained after it. Then poll readiness and bail on failure signatures:
```bash
until curl -s http://localhost:8000/v1/models | grep -q Qwen; do
  grep -qiE "Traceback|exited with code|CUDA out of memory|Unable to create lease|Killed" /tmp/dyn-agg-$PR.log \
    && { tail -40 /tmp/dyn-agg-$PR.log; break; }
  sleep 3
done
```
- `/v1/models` returning the model = worker registered and ready (the frontend `/health` comes up first, before the worker).
- The frontend logs a stream of harmless `ERROR ... status=404 ... uri=/` (root-path polls) before/while the worker registers — **not** a failure; ignore them. Real failures match the grep above.
- DEBUG logs: `DYN_LOG=debug` surfaces both the Rust runtime and the SGLang Python loggers (a worker `--log-level debug` alone does not).
- Shape traffic to hit the changed path. E.g. a tool-template change → send `/v1/chat/completions` with `tools` + `tool_choice` (auto and a named choice); a cache change → repeated/shared-prefix prompts; a router change → multiple workers.

## Step 5 — Load test with aiperf

```bash
uvx aiperf profile \
  --model Qwen/Qwen3-0.6B \
  --url http://localhost:8000 \
  --endpoint-type chat --streaming \
  --concurrency 16 --num-requests 256 \
  --prompt-input-tokens-mean 512 --output-tokens-mean 128 \
  --num-warmup-requests 8
```
For a correctness/feature change, also hit `/v1/chat/completions` directly with `curl` to inspect the exact response (tool_calls, content, finish_reason) — aiperf is for throughput/latency, curl is for correctness. For a **correctness-only** PR, scale `--num-requests` down (e.g. 32) — the load run is just a concurrency/health smoke; save large runs for perf claims.

## Step 6 — Analyze

For each hypothesis from Step 1:
- **Responses** — `curl` the endpoint; check the field the PR affects (e.g. `choices[].message.tool_calls`, rendered prompt, `usage`).
- **Logs** — grep `/tmp/dyn-agg-$PR.log` for the changed code path and for any new WARN/ERROR.
- **Metrics** — `/metrics` on the frontend `:8000` and worker `:8081`.
- **Perf** — aiperf summary; A/B vs `main` (`git checkout main`, rebuild, relaunch) if the PR claims a perf delta. Control ordering, fresh server per phase.
Keep the concrete responses / log lines / numbers — they go in the review verbatim.

## Step 7 — Report, then post the review (on approval)

Summarize to the user first: what works (with evidence), what's broken/risky (`file:line` + evidence + severity), recommendation. **Do not post to GitHub until the user approves.**

Once approved, post one `COMMENT`-type review with inline comments at exact diff lines:
```bash
# /tmp/review-$PR.json: {commit_id, event:"COMMENT", body:<summary+evidence>,
#   comments:[{path,line,side:"RIGHT",body:<finding + proof snippet>}, ...]}
gh api --method POST repos/ai-dynamo/dynamo/pulls/$PR/reviews --input /tmp/review-$PR.json
```
- `commit_id` = `git rev-parse HEAD` of the PR branch; each `line` must be in the diff (RIGHT side).
- Default `event: "COMMENT"`; Approve / Request-changes only if the user asks. One inline comment per finding, with the captured evidence. Concrete and kind.

## Step 8 — Persist the review to memory

File it under the `dynamo-pr-reviews` umbrella project in `~/memory` (one subfolder per PR):
```bash
DIR=~/memory/dynamo-pr-reviews/$PR-<slug>; mkdir -p "$DIR"
# $DIR/review.md: PR + branch, test setup (agg.sh, model), evidence, findings, posted-review link, verdict
```
Register the row in `~/memory/dynamo-pr-reviews/INDEX.md` (create it if missing; frontmatter `type: project`, `last-updated`), then `python3 ~/memory/scripts/lint_memory.py` — it lints the **whole** repo and **exits 0 even with findings**, so only act on findings that name *your* new files.

Commit **only your files** — never `git add -A` in `~/memory` (the user may be committing concurrently; `-A` will sweep their unrelated changes into your commit):
```bash
cd ~/memory && git add dynamo-pr-reviews && git commit -m "dynamo-pr-reviews: add #$PR review" && git push
```

## Cleanup

```bash
pkill -9 -f "dynamo.sglang"; pkill -9 -f "dynamo.frontend"
cd /ephemeral/dynamo && git checkout "${ORIG_REF:-main}"   # restore the tree you found
```
If Rust was rebuilt for the PR, a `maturin develop --uv` on the restored branch puts the binding back. Leave etcd/NATS running (cheap) unless asked.
