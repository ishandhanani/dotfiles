---
name: gh-comment-ledger
description: Pull GitHub PR comments and review threads into a simple actionable markdown table before deciding what to fix. Use when the user asks to triage, ledger, table, summarize, classify, or selectively address PR comments/review feedback by row number.
---

# GH Comment Ledger

Use this skill to inspect GitHub PR feedback before editing. Default to read-only triage: fetch comments, build the ledger table, and wait for the user to choose rows unless they explicitly ask to fix all actionable rows.

This skill vendors the `gh-address-comments` GraphQL approach because flat PR comments do not preserve review-thread resolution state, outdated state, or inline anchors.

## Workflow

1. Resolve the PR.
   - Use a provided PR URL directly.
   - Use `--repo OWNER/REPO --pr N` when the user gives repo and number.
   - Run without arguments only when the current branch is associated with the PR.
2. Fetch thread-aware comments:
   ```bash
   python3 agents/skills/gh-comment-ledger/scripts/fetch_comments.py --url https://github.com/OWNER/REPO/pull/123 > /tmp/gh-comment-ledger.json
   ```
3. Build the ledger from `conversation_comments`, `reviews`, and `review_threads`.
   - Put unresolved, non-outdated review threads first.
   - Include resolved/outdated rows only when useful or when the user asks for all comments.
   - Group duplicates, but keep every source thread/comment id in the row.
4. Return the table before code changes.
5. If the user selects rows, implement only those rows. If a row needs explanation rather than code, draft the reply instead of forcing a change.
6. After selected work, return an updated mini-ledger with `fixed`, `reply drafted`, `deferred`, or `not actionable`.

## Ledger Table

Use this simple table shape:

| # | State | Where | Comment | Suggested fix | Validation | Decision |
|---|---|---|---|---|---|---|
| 1 | unresolved review thread by `author` | `path:line` | One-sentence summary of the feedback. | Concrete code change or reply. | Smallest relevant check. | `todo`, `fix`, `reply`, `defer`, or `info` |

Rules:
- Keep rows short; put long quoted comment text below the table only if needed.
- `State` should include source and status, e.g. `unresolved`, `resolved`, `outdated`, `top-level`, or `review body`.
- `Suggested fix` should be specific enough to implement without rereading the whole thread.
- `Validation` should name a real check when possible; use `inspect only` for pure text replies.
- `Decision` is the recommended action, not permission to act.

## Write Safety

- Do not edit code until the user selects rows or explicitly says to fix all actionable rows.
- Do not post replies, resolve threads, or submit reviews unless the user explicitly asks for GitHub writes.
- If comments conflict, stop and show the tradeoff.
- If a comment is ambiguous, mark it `reply` or `defer` and draft the question.
- Keep every code change traceable to a ledger row.

## Fallback

If `gh auth status` fails, ask the user to run `gh auth login`.
If the script cannot resolve the PR from the current branch, ask for a PR URL or `OWNER/REPO#N`.
