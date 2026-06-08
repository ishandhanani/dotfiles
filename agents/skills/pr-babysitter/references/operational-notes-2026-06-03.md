# Babysitter Operational Notes

## Lessons from PR #10258

### What went wrong (2026-06-03)

1. **Skill not loaded**: Cron job had `skills: ["github"]` instead of `skills: ["pr-babysitter"]`. Agent ran without the skill and made autonomous decisions.
2. **Autonomous merge to fork**: Agent pushed a merge commit to someone else's fork without user consent. The skill explicitly prohibits this.
3. **Missing `/ok to test` comment**: After merging main, agent didn't post `/ok to test <sha>`. Pushing alone may not trigger CI for Dynamo.

### What we learned (2026-06-04)

4. **CI failures need triage, not blind merge-main**: PR #10258 had real bugs (`dict.get("text", "")` returning `None`). Merging main wouldn't fix them. The babysitter must investigate first, classify as PR_BUG vs FLAKE, then decide.
5. **Fork PRs CAN be pushed to**: We have admin access. Use `git remote add fork-<owner> <url>` + `git push fork-<owner> HEAD:<branch>`.
6. **Small-scope flakes**: For 2-3 failed tests, `gh run rerun <run_id> --failed` is faster than merging main.

### Correct workflow (enforced by skill now)

1. Check CI status first
2. Green → notify done
3. Pending → wait for next cycle
4. Failed → **investigate why** (triage: read diff, check failed logs, classify)
5. PR_BUG → report to user, wait for author to fix. Don't merge main.
6. FLAKE (small scope) → offer to `gh run rerun --failed`
7. FLAKE (large scope) → ask user "merge main and retrigger?"
8. User says yes → merge main (fork or same-repo), post `/ok to test <sha>`
9. Wait for CI, report result

### Cron configuration

- Schedule: `every 15m` (was `every 30m`, was `every 120m`) — tighter latency on catching CI changes
- Skills: `["pr-babysitter"]` (NOT `"github"`)
- Deliver: `slack:C0B7XL5D29K` (PR review channel fallback, was `C0B833HF4NM`). Actual per-PR updates go to each PR's `delivery_target` thread via `hermes send`; the agent returns SILENT so this static channel gets no duplicate.
- State file: `~/.hermes/state/pr-babysitter.json`
- **Each tick is non-blocking**: check current CI status, take one action, exit. Do NOT block in Step 4's 30-min wait loop under cron — the next tick re-checks. This keeps runs short so 15m ticks never overlap (there is no same-job re-entry lock).

### Delivery errors

- `not_in_channel` error: Bot must be added to the delivery channel. User added @hermes2 to C0B833HF4NM on 2026-06-03.
