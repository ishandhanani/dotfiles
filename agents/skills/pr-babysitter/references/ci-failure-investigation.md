# CI Failure Investigation Guide

## When the user asks "why is CI failing" (not just "babysit until green")

This is a distinct task from the main babysitter loop. Use this diagnostic workflow:

### Step 1 — Identify the failed checks
```bash
gh pr checks <PR> --repo ai-dynamo/dynamo
```
Note: Look for `\tfail\t` status. Don't confuse with `pending` or `skipping`.

### Step 2 — Get the failed job details
```bash
# Get job URLs for failed checks
gh api repos/ai-dynamo/dynamo/commits/<SHA>/check-runs \
  --jq '.check_runs[] | select(.conclusion=="failure") | .name + " | " + (.html_url // .details_url)'
```

### Step 3 — Trace the failure chain
For deploy test failures (e.g., `sglang Deploy Test / agg`, `sglang Deploy Test / agg_router`):

1. **Check the workflow**: `.github/workflows/pr.yaml` → `deploy-test-sglang` job
2. **Check the shared workflow**: `.github/workflows/shared-deploy-test.yml` → runs `pytest tests/deploy/test_deploy.py`
3. **Check the test**: `tests/deploy/test_deploy.py` deploys a K8s pod, sends `stream: false` chat completion, validates `response.json()` has `choices[0].message.content` with `len >= 100` (`MIN_RESPONSE_CONTENT_LENGTH`)
4. **Check the deployment profile**: `examples/backends/sglang/deploy/agg.yaml` or `agg_router.yaml`
5. **Read the PR diff**: Look for changes that could produce empty/short responses

### Step 4 — Common failure patterns

**SGLang response `text` field can be `None`** (PR #10258 pattern):
- When a PR changes output processing to use `engine_response.get("text", "")` instead of decoding `token_ids`
- `dict.get("text", "")` returns `None` (not `""`) when the key exists with value `None`
- SGLang sets `"text": None` on non-incremental intermediate chunks
- `process_output` receiving `None` as `delta_text` may return `None` (no choice emitted)
- Result: empty final responses that fail `MIN_RESPONSE_CONTENT_LENGTH` checks
- Fix: Use `engine_response.get("text") or ""` to coerce `None` to `""`

**How to verify empirically**:
```bash
# Start the server with the PR code, then:
curl -s http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"Qwen/Qwen3-0.6B","messages":[{"role":"user","content":"Hello"}],"max_tokens":512,"stream":false}'
# Check if choices[0].message.content is non-empty and >= 100 chars
```

### Step 5 — Report findings
- Which checks failed and why (with evidence from the code path)
- Whether it's a PR issue or environment/infrastructure issue
- Recommended fix (describe it, don't apply it)

## Lessons from PR #10258

- **Fork PRs CAN be pushed to** — we have admin access. Add the fork as a remote (`git remote add fork-<owner> https://github.com/<owner>/dynamo.git`) and push with `git push fork-<owner> HEAD:<branch>`.
- **Deploy tests test the full K8s deployment** — they're sensitive to response format changes, not just build breaks.
- **`/ok to test <sha>` is REQUIRED** after every merge — push alone doesn't trigger CI.
- **`dict.get("key", "")` does NOT guard against `None` values** — if the key exists with value `None`, `.get()` returns `None`, not the default. Always use `.get("key") or ""` when the upstream can set `null`/`None`.
- **Empirical confirmation from PR #10258**: deploy test `test_deployment[sglang-agg]` failed with `TypeError: object of type 'NoneType' has no len()` at `test_deploy.py:95` — `content` was `None` because sglang returned `"text": None` on intermediate chunks.
- **Small-scope flake re-run**: For 2-3 failed tests, use `gh run rerun <run_id> --failed` to retrigger just the failed jobs. No need to merge main. Get the run ID from `gh pr checks` output or `gh api repos/ai-dynamo/dynamo/commits/<SHA>/check-runs`.
- **trtllm test failures on sglang-only PRs are usually flakes** — check if the trtllm job was actually SKIPPED (known nightly failure `DYN-2608`) rather than a real failure.
