# PR Review Pipeline — Operational Notes

## Cron Job Architecture

| Job | ID | Schedule | Channel | Purpose |
|-----|----|----------|---------|---------|
| pr-notifier-ishandhanani | — | every 30m | C0B833HF4NM | Track new/mentioned Dynamo + SGLang PRs & issues |
| issue-notifier-ishandhanani | — | every 30m | C0B833HF4NM | Track new/mentioned issues (same repos) |
| dynamo-sglang-pr-poller | 8e33097036d4 | every 1h | C0B833HF4NM | Find sglang PRs from external contributors |
| pr-babysitter | 5c13b47c5f79 | every 2h | C0B833HF4NM | Drive approved PRs to green CI |

**Delivery target:** `slack:C0B833HF4NM` (user's channel). Each PR gets its own thread.

## State Files

- `~/.hermes/state/reviewed-prs.json` — PRs already reported by poller (avoid duplicates)
- `~/.hermes/state/pr-babysitter.json` — Active PRs being babysat (format in SKILL.md)

## User Interaction Model

- **No buttons or special UI.** All approvals/denials are plain text in the Slack thread.
- Poller posts: "PR #N by author: title. Reply 'review' or 'skip'."
- Review posted to thread with findings. User replies "approve" or "reject" or "needs changes."
- Babysitter asks before each retry: "CI failed. Merge main and retry? Reply yes or no."

## CI Retriggering

- **Fork PRs:** Cannot push to someone else's fork. Use `/ok to test <sha>` comment on the PR, or ask the author/maintainer to click "Update branch" in the GitHub UI.
- **Same-repo PRs:** Can merge main and push directly.
- There is **no `gh` CLI command** to merge main into a PR branch without pushing.
- Always use `/ok to test <sha>` (with the latest commit SHA) rather than plain `/ok to test`.

## Dynamo Build Pitfalls

1. **Fork PRs:** `gh pr checkout` won't work for fork PRs directly. Must `git remote add fork-<owner> && git fetch`, then use worktrees.
2. **sglang version:** `uv pip install sglang` installs latest (0.5.9), but `pyproject.toml` pins `0.5.12.post1`. Always install from the pinned version: `uv pip install "sglang[diffusion]==0.5.12.post1" --prerelease=allow`.
3. **CARGO_TARGET_DIR:** Never share between worktrees — causes Cargo.toml parsing errors.
4. **Rust build time:** ~4-6 min for full build. Python-only PRs still need the Rust bindings compiled once.
5. **Venv location:** Worktree venvs live INSIDE the worktree. Deleting the worktree deletes the venv.

## Testing Philosophy

- **Load test != PR test.** aiperf proves the server works. It does NOT prove the PR's specific claim.
- For every PR: identify the claim, design a test that disproves it if wrong, run targeted test first.
- Streaming vs non-streaming comparison (temperature=0) proves field substitution equivalence.
- Cite evidence in reviews: "X works because Y", not "server didn't crash."

## Slack Threading

- Channel: `C0B7XL5D29K` (zhongshanslab PR review)
- Per-PR thread: first message about a PR should ideally start a thread
- Cron jobs deliver to channel; user replies in-thread
