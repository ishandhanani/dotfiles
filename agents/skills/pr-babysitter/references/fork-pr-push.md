# Fork PR Push Pattern

## Problem

PRs from forks (e.g., `Muqi1029/dynamo`) have their branch on the fork, not on `ai-dynamo/dynamo`. Pushing to `origin` fails because the branch doesn't exist there. However, we have **admin access** to the org, so we CAN push directly to the fork — we just need to add it as a remote first.

## Detection

```bash
FORK_OWNER=$(gh pr view $PR --repo ai-dynamo/dynamo \
  --json headRepositoryOwner --jq .headRepositoryOwner.login)
# If FORK_OWNER != "ai-dynamo", it's a fork PR
```

The worktree setup (Step 1 in SKILL.md) adds a remote like `fork-Muqi1029` pointing to the fork repo.

## Push Command

```bash
BRANCH=$(git branch --show-current)
git push fork-$FORK_OWNER HEAD:$BRANCH
```

Always use explicit `HEAD:<branch>` refspec — bare `git push origin HEAD` can fail with "not a full refname" on some git versions, especially in worktrees.

## Refspec Gotchas

- `git push origin HEAD` — fails in worktrees (ambiguous ref)
- `git push origin HEAD:branch-name` — works for same-repo PRs
- `git push fork-$OWNER HEAD:branch-name` — required for fork PRs
- `git push fork-$OWNER branch-name` — also works but be explicit with HEAD to avoid confusion

## Post-Push CI Polling

After pushing to the fork, CI on the PR triggers automatically (GitHub detects the push to the head branch regardless of which remote it's on). Then poll with:

**IMPORTANT:** The `--watch-interval` flag is NOT available in all versions of `gh`. Use manual polling instead:

```bash
# Poll every 60-90 seconds until all non-skipping checks are done
while true; do
    OUTPUT=$(gh pr checks $PR --repo ai-dynamo/dynamo 2>&1)
    echo "$OUTPUT"
    # Check for failures
    if echo "$OUTPUT" | grep -qP '\tfail\t'; then
        echo "CI FAILED"
        break
    fi
    # Check if any non-skipping checks are still pending
    PENDING=$(echo "$OUTPUT" | grep -P '\tpending\t' | grep -v 'skipping' | wc -l)
    if [ "$PENDING" -eq 0 ]; then
        echo "ALL CHECKS PASSED"
        break
    fi
    echo "Waiting 90s... ($PENDING checks still pending)"
    sleep 90
done
```

**Exit code note:** `gh pr checks` returns exit code 1 when checks are still pending OR when all pass but some are skipping. Exit code 0 means all non-skipping checks passed. Do NOT rely on exit code alone — parse the output for `pending` and `fail` statuses.

## State File Fields

For fork PRs, populate these additional fields in `pr-babysitter.json`:

```json
{
  "fork_remote": "fork-Muqi1029",
  "fork_url": "https://github.com/Muqi1029/dynamo.git"
}
```

Use `fork_remote` as the push target in all subsequent retry cycles.

## Re-running Failed Jobs (Small-Scope Flakes)

For 2-3 failed tests, it's faster to retrigger just the failed jobs than to merge main:

```bash
# Get the run ID from gh pr checks output or:
gh api repos/ai-dynamo/dynamo/commits/<SHA>/check-runs \
  -q '.check_runs[] | select(.conclusion=="failure") | .id'

# Re-run only failed jobs:
gh run rerun <run_id> --failed
```

This works for both same-repo and fork PRs since it's a GitHub API operation, not a git push.
