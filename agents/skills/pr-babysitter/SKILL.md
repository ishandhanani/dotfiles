---
name: pr-babysitter
description: "Babysit a PR through CI to green. Merge main into the PR branch, push, wait for CI, and ask the user before retrying on failure. Ping the user when CI is green. Use after a PR has been approved for merge."
user-invocable: true
---

# PR Babysitter

Drive a PR's CI to green via the user's Slack thread, then notify when ready to merge.

Companion to `dynamo-pr-reviews`. Only runs on PRs the user explicitly approved.

## Precondition

User must approve the PR for merge and confirm babysitter should start.

## Key Design: Triage First, Then Act

**Always investigate a CI failure before deciding what to do.** The babysitter flow:

1. Check current CI status
2. If CI is green → notify "ready to merge", done
3. If CI is still pending → wait, then check next cycle
4. If CI failed → **investigate why** (see "CI Failure Triage" section below)
5. Classify the failure and decide:
   - **PR-related bug** → report findings and recommended fix to user. Ask "merge main and retry after fix?" or "fix the PR code?" (babysitter never modifies PR code itself; stop and wait for author)
   - **Flake / infrastructure** → report to user, ask "retrigger CI by merging main?" (or "retry?" for fork PRs)
6. **WAIT for user response** — do not proceed until they say yes
7. User says yes → merge main (if no conflicts), post `/ok to test <sha>`, wait for CI
8. If merge has conflicts → report to user, ask them to resolve
9. If CI fails again after merge → go back to step 4 (investigate again)
10. User says no at any point → remove from active list

This keeps the user in control and avoids mindlessly merging main when the failure is a real PR bug.

### CI Failure Triage

When CI fails, run this diagnostic before asking the user anything:

1. Identify failed checks: `gh pr checks <PR> --repo ai-dynamo/dynamo` — look for `\tfail\t` lines
2. Get the PR diff and read the changed files: `gh pr diff <PR> --repo ai-dynamo/dynamo`
3. For runtime test failures (e.g., `sglang-runtime / Test`, `sglang Deploy Test`):
   - Check if the PR changes output-processing, token handling, or response formatting
   - Look for patterns like `dict.get("text", "")` returning `None` instead of `""`
   - Run the empirical test from `references/ci-failure-investigation.md` if a server is available
4. For build failures: check if the PR touches the failing build's component
5. For failures in unrelated components (e.g., trtllm tests failing on an sglang-only PR): likely a flake or infra issue

**Classification rules:**
- **PR-related**: Failed tests are in the component the PR modifies, AND the diff contains code that could cause the failure mode
- **Flake/infra**: Failed tests are in unrelated components, OR the failure is intermittent (passed on retry), OR the failure is a known infrastructure issue (K8s pod startup timeout, network error, etc.)

**What to report to the user:**
- Which checks failed
- Your classification (PR bug vs flake) with evidence
- Recommended action (merge main and retry vs fix PR code vs wait and retrigger)
- Then ask for confirmation

## Boundaries

- Only push merge commits — never modify PR code
- Only merge `origin/main` into the PR branch
- If merge has real conflicts with main → stop, ask user
- When CI is green, attempt to merge the PR with `gh pr merge --squash --delete-branch --auto`
- `/ok to test` comments are from the user's perspective (running as ishandanani)
- Fork PRs: we have admin access, so we CAN merge main into a fork branch and push. Use `gh pr checkout <PR>` or set the push remote to the fork's URL. This is equivalent to clicking "Update branch" on the PR page.

## Step 0 — Inputs

- PR number (repo defaults to `ai-dynamo/dynamo`)
- Worktree path for the PR
- Slack channel: `C0B7XL5D29K` (PR review channel)
- **Thread ID**: If the user asked to babysit from within a Slack thread, capture the thread_id and use it as the delivery target so CI updates land in the same thread. Format: `slack:<channel_id>:<thread_id>`. If not in a thread, use `slack:<channel_id>`.

## Step 1 — Setup Worktree

```bash
PR=<number>
MAIN=/ephemeral/dynamo
WT=/ephemeral/dynamo-wt/pr-$PR

cd $MAIN
git fetch origin
BRANCH=$(gh pr view $PR --repo ai-dynamo/dynamo --jq .headRefName -q)
git worktree add $WT origin/$BRANCH 2>/dev/null || git worktree add $WT $BRANCH
cd $WT
git log --oneline -1
```

## Step 2 — Check CI Status

Before doing anything, check the current CI status:

```bash
cd /ephemeral/dynamo
OUTPUT=$(gh pr checks $PR --repo ai-dynamo/dynamo 2>&1)
echo "$OUTPUT"

if echo "$OUTPUT" | grep -qP '\tfail\t'; then
    echo "CI_FAILED"
elif echo "$OUTPUT" | grep -qP '\tpending\t' | grep -v 'skipping'; then
    echo "CI_PENDING"
else
    echo "CI_GREEN"
fi
```

- **CI_GREEN** → Go to Step 5 (notify user, done)
- **CI_PENDING** → Report "CI still pending, will check next cycle", exit
- **CI_FAILED** → Go to Step 2a (CI Failure Triage)

## Step 2a — CI Failure Triage

Investigate the failure before deciding what to do. Follow the triage steps from the "CI Failure Triage" section above.

**Output a classification:**
- `PR_BUG`: The failure is caused by the PR's code changes. Report findings to user. **Stop and wait for PR author to fix** — the babysitter never modifies PR code. Ask the user: "This looks like a PR bug in <file>:<description>. Wait for the author to fix, or should I remove this PR from babysitting?"
- `FLAKE`: The failure is unrelated to the PR (infra issue, unrelated component flake, retry-passed). Decide based on scope:
  - **Small scope (2-3 failed tests)**: Re-run just the failed jobs via `gh run rerun <run_id> --failed` — no need to merge main. Ask user: "Looks like a flake — only <N> tests failed. Re-run them directly?"
  - **Large scope (many failures)**: Ask user: "CI failed on unrelated checks — looks like a flake. Merge main and retrigger CI?"
- `UNCLEAR`: You can't determine from logs alone. Report what you found and ask the user to investigate or decide.

## Step 3 — Merge Main (only after triage classified as FLAKE or UNCLEAR)

This step is only reached after Step 2a (CI Failure Triage) classified the failure as `FLAKE` or `UNCLEAR` and the user confirmed they want to proceed. Do NOT reach this step for `PR_BUG` classifications.

1. Proceed to Step 3a (fork check)

### Step 3a — Check if PR is from a fork

```bash
FORK_OWNER=$(gh pr view $PR --repo ai-dynamo/dynamo --json headRepositoryOwner --jq .headRepositoryOwner.login)
if [ "$FORK_OWNER" != "ai-dynamo" ]; then
    echo "FORK_PR: branch lives in $FORK_OWNER/dynamo"
fi
```

### Step 3b — Attempt merge

**For fork PRs** (branch lives in someone else's fork): We have admin access and CAN push to forks. Add the fork as a remote and push:

```bash
cd $WT
FORK_URL="https://github.com/$FORK_OWNER/dynamo.git"
git remote add fork-$FORK_OWNER $FORK_URL 2>/dev/null || git remote set-url fork-$FORK_OWNER $FORK_URL
git fetch fork-$FORK_OWNER
# The branch name is the PR's head ref
BRANCH=$(gh pr view $PR --repo ai-dynamo/dynamo --jq .headRefName -q)
git merge origin/main --no-edit
CONFLICTS=$(git diff --name-only --diff-filter=U)
if [ -n "$CONFLICTS" ]; then
    git merge --abort
    echo "CONFLICT: $CONFLICTS"
    # Report conflicts to user, ask them to resolve
    exit 1
fi
git push fork-$FORK_OWNER HEAD:$BRANCH
echo "Pushed merge commit to fork"
```

**For same-repo PRs** (branch lives on `origin`):

```bash
cd $WT
git fetch origin main
git merge origin/main --no-edit
CONFLICTS=$(git diff --name-only --diff-filter=U)
if [ -n "$CONFLICTS" ]; then
    git merge --abort
    echo "CONFLICT: $CONFLICTS"
    # Report conflicts to user, ask them to resolve
    exit 1
fi
git push origin HEAD:$(git branch --show-current)
echo "Pushed merge commit"
```

**Important:** Always use the explicit refspec `HEAD:<branch>` — bare `git push origin HEAD` fails with "not a full refname" on some git versions.

### Step 3c — Post `/ok to test <sha>` comment (REQUIRED)

**This step is REQUIRED after every merge.** Pushing alone does NOT trigger CI:

```bash
cd /ephemeral/dynamo
SHA=$(gh pr view $PR --repo ai-dynamo/dynamo --json commits --jq '.commits[-1].oid')
gh pr comment $PR --repo ai-dynamo/dynamo --body "/ok to test $SHA"
echo "Posted /ok to test $SHA"
```

**Do not skip this step.** Without `/ok to test`, CI will not run even after a successful push.

After posting, go to Step 4 to wait for CI.

## Step 4 — Wait for CI

CI triggers automatically on push. Poll status manually (the `--watch-interval` flag is NOT available in all `gh` versions):

```bash
# Poll every 60-90s until all non-skipping checks are done or failed
while true; do
    OUTPUT=$(gh pr checks $PR --repo ai-dynamo/dynamo 2>&1)
    echo "$OUTPUT"
    if echo "$OUTPUT" | grep -qP '\tfail\t'; then
        echo "CI FAILED"
        break
    fi
    PENDING=$(echo "$OUTPUT" | grep -P '\tpending\t' | grep -v 'skipping' | wc -l)
    if [ "$PENDING" -eq 0 ]; then
        echo "ALL CHECKS PASSED"
        break
    fi
    echo "Waiting 90s... ($PENDING checks still pending)"
    sleep 90
done
```

Up to 30 minute total timeout across all polls. **Exit code note:** `gh pr checks` returns exit code 1 when checks are still pending OR when all pass but some are skipping. Exit code 0 means all non-skipping checks passed. Do NOT rely on exit code alone — parse the output for `pending` and `fail` statuses.

## Step 5 — Result

**Green:**
1. Attempt merge:
   ```bash
   gh pr merge <number> --repo <repo> --squash --delete-branch --auto --subject "<title> (#<number>)"
   ```
   If `--auto` fails with "not mergeable", try `--admin` only if the user has admin access and approves.
2. Notify user in slack: "PR #<N> CI is green. Merged: <link>"
3. Remove from active list, clean up worktree

**Failed:**
1. Go to Step 2a (CI Failure Triage) — investigate the new failure
2. Classify as `PR_BUG`, `FLAKE`, or `UNCLEAR` and report to user with evidence
3. For `PR_BUG`: stop and wait for PR author to fix. Ask user whether to keep babysitting or remove.
4. For `FLAKE`: ask user "Merge main and retrigger CI? Reply yes or no."
5. For `UNCLEAR`: present findings and ask user to decide
6. **WAIT for user response** — do not proceed until they reply
7. User says yes (flake path) → go to Step 3 (merge main, post `/ok to test <sha>`, wait for CI)
8. User says no → remove from active list, report stopped

## Step 6 — Cleanup

```bash
cd /ephemeral/dynamo
git worktree remove /ephemeral/dynamo-wt/pr-$PR --force 2>/dev/null || true
```

## State File

`~/.hermes/state/pr-babysitter.json`:

```json
{
  "active": [
    {
      "number": 12345,
      "repo": "ai-dynamo/dynamo",
      "title": "fix(sglang): some fix",
      "url": "https://github.com/ai-dynamo/dynamo/pull/12345",
      "branch": "fix/some-branch",
      "worktree": "/ephemeral/dynamo-wt/pr-12345",
      "fork_remote": "fork-Muqi1029",
      "fork_url": "https://github.com/Muqi1029/dynamo.git",
      "iterations": 0,
      "max_iterations": 10,
      "last_sha": "abc123",
      "last_ci_status": "pending",
      "last_classification": "flake",
      "added_at": "2026-06-03T15:00:00Z"
    }
  ]
}
```

**Fields:**
- `fork_remote` / `fork_url`: only present for fork PRs. Use `fork_remote` as the push target.
- `iterations`: incremented each merge-push-CI cycle.
- `last_sha`: updated after each push.
- `last_ci_status`: one of `pending`, `green`, `failed`.
- `last_classification`: one of `pr_bug`, `flake`, `unclear` — set by Step 2a triage.

## References

- [Fork PR push pattern](references/fork-pr-push.md) — detecting fork PRs, push commands, refspec gotchas
- [Operational notes](references/operational-notes-2026-06-03.md) — lessons from PR #10258, cron config, delivery errors
- [CI failure investigation](references/ci-failure-investigation.md) — diagnostic workflow for "why is CI failing" requests

## Investigating CI Failures (Ad-hoc)

When the user asks you to **investigate why CI is failing** (outside the babysitter cron), use the same triage workflow from Step 2a and the diagnostic guide in [references/ci-failure-investigation.md](references/ci-failure-investigation.md). Key points:

1. Identify failed checks with `gh pr checks`
2. Trace the failure chain: failed check → workflow → shared workflow → action → test file → deployment profile → PR diff
3. For deploy test failures, check if the PR's code changes could produce empty/short responses (e.g., `None` vs `""` handling for sglang `text` field)
4. Classify as PR bug vs flake and report findings with evidence

The babysitter cron now uses this same triage internally (Step 2a) — this section is for ad-hoc manual investigation requests.

## Loop Guard

- Max 10 merge-push-CI cycles per PR
- After 10 failures, report to user and stop
- Each CI failure requires explicit user confirmation to retry
