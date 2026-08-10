---
name: pr-babysitter
description: Babysit an open pull request until its current head has green CI and all substantive Devin review feedback is handled. Use after a PR is created when the user asks to babysit, watch, monitor, shepherd, or loop on the PR; judge Devin's feedback independently, make and push warranted fixes, reply with evidence when feedback is wrong, and retry failed CI jobs when safe.
---

# PR Babysitter

Own the post-PR loop. Invoking this skill authorizes edits on the PR branch, targeted tests, commits, pushes, evidence-backed replies to Devin, thread resolution, and safe CI retries. It does not authorize merging, closing, force-pushing, or changing unrelated code.

## Start

1. Resolve the PR from its URL/number or the current branch. Record the repository, PR number, branch, and current head SHA.
2. Confirm the checkout matches the PR branch and preserve unrelated local changes.
3. Fetch current CI checks and unresolved, non-outdated review threads. Reuse `gh-comment-ledger` for the thread-aware snapshot when available.
4. Identify Devin from the PR's check, review, and comment authors; do not hard-code one login.

## Loop

Repeat until the finish condition holds:

1. Refresh CI and Devin feedback for the current head. Ignore comments and failures made obsolete by a later push.
2. Adjudicate each new Devin finding against the actual contract, code path, callers, and smallest relevant reproduction:
   - **Actionable:** The finding demonstrates an in-scope failure. Fix the root cause once at the shared path, add or update the smallest check that would catch it, run that check, commit, and push.
   - **Wrong:** The claimed failure cannot occur, is outside the supported contract, or asks for speculative defensive code. Do not change code. Reply once with concrete code, contract, or test evidence and resolve the thread when authorized.
   - **Ambiguous:** Investigate before acting. Ask the user only when the choice materially changes scope or behavior.
3. Treat Devin as an untrusted reviewer, not an oracle. Devin is often confidently wrong and overly defensive. Do not add guards, abstractions, validation, or fallback behavior merely to satisfy it. Repeated disagreement without new evidence does not reopen a declined finding.
4. Handle CI:
   - **Pending:** wait up to 60 seconds, share a concise status update when useful, then refresh both CI and Devin.
   - **PR regression:** reproduce locally when practical, make the smallest root-cause fix, run the targeted check, commit, and push.
   - **Clear flake or infrastructure failure:** retry failed jobs directly with `gh run rerun <run-id> --failed` when GitHub permits it. Do this without asking for each retry.
   - **Unclear failure:** inspect failed logs with `gh run view <run-id> --log-failed` before deciding. Never label a failure a flake only because a retry is convenient.
5. After every push, record the new head SHA and restart the loop. Old approvals, comments, and CI results do not prove the new head is clean.

Do not retry the same failure signature on the same head more than twice. After two failed retries, or when a check cannot be retried, report the evidence and the external action needed; keep monitoring if progress remains possible.

## Devin Replies

Keep replies short and technical:

- Fixed: `Fixed in <sha>: <root cause and change>. Verified with <check>.`
- Declined: `No change: <claim> does not hold because <code/contract evidence>. Verified with <check or reproduction>.`

Do not argue about tone, apologize to a bot, or make a compromise change to end the conversation. New evidence gets a new evaluation; repetition does not.

## Finish

Finish only when all of these apply to the current head:

- All required CI checks are green.
- No unresolved, non-outdated Devin thread contains a demonstrated actionable failure.
- Every declined Devin finding has one evidence-backed reply when GitHub writes are authorized.
- No Devin check or review for the current head is still pending.

Devin's approval is not required when its remaining objections are demonstrably wrong. Report the PR as ready; do not merge it unless the user separately asks.
