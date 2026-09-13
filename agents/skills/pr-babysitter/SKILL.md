---
name: pr-babysitter
description: Monitor a pull request until CI passes and substantive AI feedback is resolved.
---

# PR Babysitter

Own the requested post-PR loop. A user request to babysit a PR authorizes relevant edits, targeted tests, commits, pushes, and safe CI retries. Post replies and resolve threads only when those GitHub actions are explicitly authorized. Automatic skill selection grants no additional authorization. It does not authorize merging, closing, force-pushing, or changing unrelated code.

## Background Delegation

When background execution is requested, read [background.md](references/background.md). Otherwise own the loop in this task.

## Start

1. Resolve the PR from its URL/number or the current branch. Record the repository, PR number, branch, and current head SHA.
2. Confirm the checkout matches the PR branch and preserve unrelated local changes.
3. Fetch current CI checks and unresolved, non-outdated review threads. Reuse `gh-comment-ledger` for the thread-aware snapshot when available.
4. Identify every AI reviewer from the PR's checks, reviews, and comment authors, including Devin; do not hard-code one login. Record each unresolved, non-outdated AI-authored thread. Do not infer that a human comment is AI-authored from prose alone.

## Loop

**Every AI-authored comment is an adversarial claim, never a presumption of correctness.** Review each one independently before replying, resolving, or changing code. First state the exact claimed failure and its preconditions; then trace the contract, affected code path, callers, and behavior; finally reproduce the failure or prove that a required precondition cannot hold. A comment with no concrete technical claim is a no-finding, not implicit approval. If this evidence cannot determine the correct action, stop and ask the user before changing code.

Repeat until the finish condition holds:

1. Refresh CI and AI review feedback for the current head. Ignore comments and failures made obsolete by a later push.
2. Adjudicate every new AI-authored comment independently against the actual contract, code path, callers, and smallest relevant reproduction:
   - **Actionable:** The finding demonstrates an in-scope failure. Fix the root cause once at the shared path, add or update the smallest check that would catch it, run that check, commit, and push.
   - **Wrong:** The claimed failure cannot occur, is outside the supported contract, or asks for speculative defensive code. Do not change code. Reply once with concrete code, contract, or test evidence and resolve the thread when authorized.
   - **Ambiguous:** Investigate before acting. If the evidence cannot determine the correct action, ask the user before changing code.
   - **No finding:** The comment makes no concrete technical claim. Record that classification; do not manufacture a change or reply.
3. Treat every AI reviewer, including Devin, as an untrusted reviewer, not an oracle. AI feedback is often confidently wrong and overly defensive. Do not add guards, abstractions, validation, or fallback behavior merely to satisfy it. Repeated disagreement without new evidence does not reopen a declined finding.
4. Handle CI:
   - **Pending:** wait up to 60 seconds, share a concise status update when useful, then refresh both CI and AI review feedback.
   - **PR regression:** reproduce locally when practical, make the smallest root-cause fix, run the targeted check, commit, and push.
   - **Clear flake or infrastructure failure:** retry failed jobs directly with `gh run rerun <run-id> --failed` when GitHub permits it. Do this without asking for each retry.
   - **Unclear failure:** inspect failed logs with `gh run view <run-id> --log-failed` before deciding. Never label a failure a flake only because a retry is convenient.
5. After every push, record the new head SHA and restart the loop. Old approvals, comments, and CI results do not prove the new head is clean.

Do not retry the same failure signature on the same head more than twice. After two failed retries, or when a check cannot be retried, report the evidence and the external action needed; keep monitoring if progress remains possible.

## AI Review Replies

Keep replies short and technical:

- Fixed: `Fixed in <sha>: <root cause and change>. Verified with <check>.`
- Declined: `No change: <claim> does not hold because <code/contract evidence>. Verified with <check or reproduction>.`

Do not argue about tone, apologize to a bot, or make a compromise change to end the conversation. New evidence gets a new evaluation; repetition does not.

## Finish

Finish only when all of these apply to the current head:

- All required CI checks are green.
- No unresolved, non-outdated AI-review thread contains a demonstrated actionable failure.
- Every declined AI finding has one evidence-backed reply when replies are authorized; otherwise return its reply draft locally.
- No AI check or review for the current head is still pending.

An AI reviewer's approval is not required when its remaining objections are demonstrably wrong. Report the PR as ready; do not merge it unless the user separately asks.
