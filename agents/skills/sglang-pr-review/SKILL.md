---
name: sglang-pr-review
description: Clone an SGLang PR into a throwaway checkout, build it in a fresh venv, run it with sglang.launch_server, drive load with uvx aiperf, verify the change empirically, then post a scoped evidence-backed GitHub review. Use when asked to test/try/review an sglang PR (e.g. "test sgl-project/sglang#12345", "review this sglang PR").
user-invocable: true
---

# SGLang PR Review

Empirical, end-to-end workflow for testing an SGLang PR and leaving a scoped, evidence-backed review.

**Principle: read the diff to form hypotheses, then prove or refute them by running the code.** Never review from the diff alone — launch the server, exercise the changed path, show the logs/metrics/numbers.

Main path is pure SGLang: `python -m sglang.launch_server`. Almost everything (kernels, schedulers, cache, sampling, metrics, the OpenAI API) can be exercised this way — no external serving layer needed.

## Hardware fit — check first

Default target: **2× L40S** (~46 GB each, 92 GB total; Ada sm_89; PCIe, no NVLink; no fp4).

After reading the PR, decide whether it can be tested here. **Stop and tell the user** if the change fundamentally needs hardware/scale beyond 2× L40S, e.g.:
- A model that won't fit in 92 GB even quantized (≳70B dense, large MoE).
- Hardware the L40S lacks: Blackwell fp4/nvfp4, Hopper-only fp8-groupwise / DeepGEMM / TMA paths, NVLink/NVLS collectives, multi-node EP.
- A TP/PP/EP topology needing >2 GPUs.

Otherwise you can almost always test the change with a **small model on 1 GPU** (default `Qwen/Qwen3-0.6B`) — the model is just a vehicle for hitting the changed code. Pick the smallest model that still exercises the path (an MoE-specific change needs a small MoE; only use it if it fits, else flag it).

## Step 0 — Inputs

Confirm: **PR number** (repo defaults to `sgl-project/sglang`), and anything the PR needs to be exercised (a specific model, flag, or traffic shape). If the PR description says how to enable/observe the feature, follow it.

## Step 1 — Throwaway checkout (never touch existing sglang trees)

Live sglang checkouts on the box may be someone's active work — don't reuse or branch-switch them. Clone fresh:

```bash
PR=<number>; WORK=/ephemeral/sglang-pr-$PR
git clone --quiet https://github.com/sgl-project/sglang.git $WORK
cd $WORK && gh pr checkout $PR && git log --oneline -1
```

PR branches are often based on an older `main` and show as CONFLICTING — that's fine, test the branch as the author has it.

Read the diff and plan:
```bash
gh pr diff $PR | tee /tmp/pr-$PR.diff
gh pr diff $PR --name-only
```
List changed files, write down concrete expectations (what should change in logs / metrics / output / perf), and **grep for consumers the diff may have missed** — e.g. if a function signature or a NamedTuple's fields changed, `git grep` every call/unpack site; an un-updated one is a real bug.

## Step 2 — Fresh venv + editable install

Per-PR isolated venv. uv pulls prebuilt wheels for torch / sgl-kernel / flashinfer (no compilation; the uv cache makes repeats fast):

```bash
cd $WORK
uv venv .venv && source .venv/bin/activate
uv pip install -e "python"
python -c "import sglang; print(sglang.__version__, sglang.__file__)"
```
If a native dep (`sgl-kernel`, flashinfer) won't resolve for the PR's base, tell the user rather than fighting the toolchain — the branch may target newer CUDA/kernels than the box has.

## Step 3 — Launch the server (background)

`launch_server` serves an OpenAI-compatible API (default port 30000) with `/v1/...`, `/health`, `/metrics`.

```bash
pkill -9 -f sglang 2>/dev/null; sleep 2
python -m sglang.launch_server \
  --model-path Qwen/Qwen3-0.6B --port 30000 --enable-metrics \
  <flags-the-PR-needs>          # e.g. --log-level debug, feature-specific flags
  > /tmp/sglang-pr-$PR.log 2>&1 &
```

Run it as a background task and poll readiness — bail on failure signatures instead of waiting blind:
```bash
until curl -sf localhost:30000/health >/dev/null; do
  grep -qiE "Traceback|CUDA out of memory|Error|Killed" /tmp/sglang-pr-$PR.log && { tail -30 /tmp/sglang-pr-$PR.log; break; }
  sleep 3
done
```
- DEBUG logs: just pass `--log-level debug` (read directly here).
- To force a specific path, shape the inputs: small `--max-total-tokens` to force cache eviction/load-back; a shared prefix to force prefix-cache hits; long prompts for chunked prefill; etc.

## Step 4 — Load test with aiperf

```bash
uvx aiperf profile \
  --model Qwen/Qwen3-0.6B \
  --url http://localhost:30000 \
  --endpoint-type chat --streaming \
  --concurrency 16 --num-requests 256 \
  --prompt-input-tokens-mean 512 --output-tokens-mean 128 \
  --num-warmup-requests 8
```
Useful knobs:
- Prefix/cache-hit testing: `--num-prefix-prompts` + `--prefix-prompt-length` (shared prefixes drive cache hits).
- A/B a perf claim: run the same load on the PR branch and on its merge-base (`git checkout HEAD~1`, reinstall, relaunch), compare aiperf throughput / TTFT / ITL. Control ordering (A/B and B/A), fresh server per phase.

## Step 5 — Analyze

For each hypothesis from Step 1, pull evidence:
- **Logs** — grep for the lines the PR adds/changes, and for any new WARN/ERROR (a feature that floods warnings under its own happy path is a finding).
- **Metrics** — `curl -s localhost:30000/metrics | grep <new-series>`; check values are sane and self-consistent (e.g. a separate counter vs a histogram's `_sum`/`_count`).
- **Perf** — compare aiperf summaries (branch vs base).
- **Correctness** — spot-check output; verify the invariants the PR claims *and the ones it doesn't* (off-by-one, double counting, unconditional cost hidden behind an "only when enabled" claim).

Keep the concrete numbers / log lines — they go into the review verbatim.

## Step 6 — Report, then post the review (on approval)

Summarize to the user first: what works (with evidence), what's broken/risky (`file:line` + evidence + severity), and a recommendation. **Do not post to GitHub until the user approves.**

Once approved, leave a **scoped, evidence-backed review** — one `COMMENT`-type review with inline comments at exact lines, not a wall of text. Build the payload and post via the API:

```bash
# /tmp/review-$PR.json:
# { "commit_id": "<git rev-parse HEAD of PR branch>", "event": "COMMENT",
#   "body": "<summary + evidence (server logs / /metrics / aiperf numbers)>",
#   "comments": [ {"path": "...", "line": <N>, "side": "RIGHT", "body": "<finding + proof snippet>"}, ... ] }
gh api --method POST repos/sgl-project/sglang/pulls/$PR/reviews --input /tmp/review-$PR.json
```
- Each `line` must be a line present in the diff (RIGHT side). One inline comment per finding, anchored at the line, with the captured log/metric snippet that proves it.
- Default to `event: "COMMENT"` — only Approve / Request-changes if the user asks for a verdict.
- Evidence in comments stays plain SGLang output. Be concrete and kind.

## Step 7 — Persist the review to memory

File the review under the `sglang-pr-reviews` umbrella project in `~/memory` (one subfolder per PR — keeps these out of the memory root):

```bash
DIR=~/memory/sglang-pr-reviews/$PR-<slug>      # e.g. 26976-tiered-cached-token
mkdir -p "$DIR"
# write $DIR/review.md: PR + branch, test setup, evidence (logs/metrics/aiperf), findings, posted-review link, verdict
```
Then register the row in `~/memory/sglang-pr-reviews/INDEX.md` (not the root `INDEX.md`), `python3 ~/memory/scripts/lint_memory.py` (lints the whole repo and exits 0 even with findings — only act on ones naming your files), and commit **only your files** (never `git add -A` in `~/memory` — it sweeps the user's concurrent work): `cd ~/memory && git add sglang-pr-reviews && git commit -m "sglang-pr-reviews: add #$PR review" && git push`.

## Cleanup

`pkill -9 -f sglang`. The throwaway `/ephemeral/sglang-pr-$PR` + its venv can be removed when done (ask before deleting if disk isn't tight).
