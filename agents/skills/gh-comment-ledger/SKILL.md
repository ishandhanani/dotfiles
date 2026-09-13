---
name: gh-comment-ledger
description: Triage GitHub PR feedback into an actionable ledger before editing or replying.
---

# GH Comment Ledger

Use this skill to classify GitHub PR feedback before editing. For triage-only requests, return the ledger. For requests to address feedback, fix demonstrated in-scope failures and validate them without requiring another row-selection turn. Respect any rows or scope the user selected.

Routing rule: this skill owns the first pass for PR comments. Use `github:gh-address-comments` only after the ledger exists or when the user explicitly names that curated skill.

This skill vendors the `gh-address-comments` GraphQL approach because flat PR comments do not preserve review-thread resolution state, outdated state, or inline anchors.

## Workflow

1. Resolve the PR.
   - Use a provided PR URL directly.
   - Use `--repo OWNER/REPO --pr N` when the user gives repo and number.
   - Run without arguments only when the current branch is associated with the PR.
2. Fetch thread-aware comments:
   ```bash
   python3 <installed-skill-directory>/scripts/fetch_comments.py --url https://github.com/OWNER/REPO/pull/123 > /tmp/gh-comment-ledger.json
   ```
3. Build the ledger from `conversation_comments`, `reviews`, and `review_threads`.
   - Put unresolved, non-outdated review threads first.
   - Include resolved/outdated rows only when useful or when the user asks for all comments.
   - Group duplicates, but keep every source thread/comment id in the row.
   - Triage the substance, not just the status. An actionable row must name an in-scope failure case: precondition/input, affected path, and concrete outcome. Prefer the reviewer's reproduction; otherwise trace it in code before recommending a change.
   - Mark speculative edge cases, style preferences, unsupported inputs, and alternative designs `not actionable` unless they show a concrete contract, safety, security, or measurable-performance failure. Do not invent defensive code to make every hypothetical valid.
4. Return the table before code changes.
5. Implement the authorized rows. If a row needs explanation rather than code, draft the reply instead of forcing a change.
6. When GitHub replies are explicitly authorized, reply to each addressed source thread: `Fixed in <commit>. <one-sentence summary>`. Otherwise return reply drafts locally.
7. Return an updated mini-ledger with `fixed`, `reply drafted`, `deferred`, or `not actionable`.

## Ledger Table

Use this simple table shape:

| # | State | Where | Comment | Failure case | Smallest response | Validation | Decision |
|---|---|---|---|---|---|---|---|
| 1 | unresolved review thread by `author` | `path:line` | One-sentence summary of the feedback. | `When <precondition>, <path> causes <outcome>`; `not demonstrated` if absent. | Concrete minimal code change, reply, or no change. | Smallest relevant check. | `todo`, `fix`, `reply`, `defer`, `info`, or `not actionable` |

Rules:
- Keep rows short; put long quoted comment text below the table only if needed.
- `State` should include source and status, e.g. `unresolved`, `resolved`, `outdated`, `top-level`, or `review body`.
- `Failure case` is required for `todo` or `fix`. State the trigger and outcome; if neither the reviewer nor the code supplies one, use `not demonstrated` and do not promote the row to a code change.
- `Smallest response` should be specific enough to implement without rereading the whole thread, and should preserve the existing scope rather than adding speculative branches.
- `Validation` should name a real check when possible; use `inspect only` for pure text replies.
- `Decision` is the recommended action, not permission to act.

## Write Safety

- A request to address feedback authorizes relevant code changes; a triage-only request does not.
- Do not post replies, resolve threads, or submit reviews unless the user explicitly authorized those GitHub actions. Permission to fix code alone does not authorize communication.
- If comments conflict, investigate against the contract and show any unresolved tradeoff; continue independent authorized rows.
- If a comment is ambiguous, mark it `reply` or `defer` and draft the question.
- Keep every code change traceable to a ledger row.
- Post a fixed reply only for rows actually addressed by a commit; keep the summary to one sentence.

## Fallback

If `gh auth status` fails, ask the user to run `gh auth login`.
If the script cannot resolve the PR from the current branch, ask for a PR URL or `OWNER/REPO#N`.
