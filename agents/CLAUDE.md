# User Context - Ishan Dhanani

Expert Python and Rust systems architect. Performance engineering is the core competency. Datacenter-scale distributed inference serving.

## Session Start

1. Resolve agent identity:
   - If `CODEX_THREAD_ID` or other `CODEX_*` env vars are present, set `AGENT_KIND=codex`, `AGENT_HOME=${CODEX_HOME:-~/.codex}`, `AGENT_INSTRUCTIONS=CLAUDE.md` (with `AGENTS.md` symlinked to it).
   - If Claude-specific env vars are present, set `AGENT_KIND=claude`, `AGENT_HOME=${CLAUDE_HOME:-~/.claude}`, `AGENT_INSTRUCTIONS=CLAUDE.md`.
   - If ambiguous, require explicit `AGENT_KIND`/`AGENT_HOME` from the user instead of guessing.
2. Read `~/memory/INDEX.md` to see the project registry.
   - Match the active project from cwd, git remote, or user prompt.
   - Read the matching project's `~/memory/<project>/INDEX.md` for specs, worklogs, and key results.
   - If no project matches, ask which one.
3. Check `git worktree list` to understand the checkout layout.

## Session End

Use the `memory-log` skill for meaningful results. Do not log routine edits.

## How I Work

- **Direct path first.** Make the smallest change that satisfies the request. Do not refactor working code or add speculative abstractions.
- **Performance over correctness-first.** Optimize by default. Profile before guessing.
- **Empirical validation.** Prove it with logs, metrics, benchmarks. Show numbers, not theory.
- **No speculation.** Reproduce first, explain second. Don't theorize at length.

## Communication Preferences

- **Be concise.** Bullet points over paragraphs. Actionable items over narrative analysis. User will redirect if verbose.
- **No hard-wrapped Markdown.** Write each paragraph and list item as one continuous line and rely on soft-wrap. Never add manual line breaks mid-paragraph to hit a column width. Newlines are only for separating paragraphs, list items, headings, code fences, and tables.
- Explain code with flow charts/diagrams tracing through components and their interactions
- When uncertain, ask rather than assume
- No emojis in code, commits, or communication
- When referencing code, include `file_path:line_number` for easy navigation
- **Never mention the assistant brand in PRs or commits. No Co-Authored-By lines.**

## Environment

- Linux with GPUs (`nvidia-smi`). You have sudo.
- Before Python/build/test work, inspect `$VIRTUAL_ENV` and the active checkout's `<root>/.venv`. Use or create only `<root>/.venv`; never copy, symlink, reuse, or mutate another checkout's venv. Verify editable imports resolve inside the active checkout.

### Build Commands
- **Dynamo** (Rust + Python): `cd <root>/lib/bindings/python && CARGO_TARGET_DIR="$(git rev-parse --show-toplevel)/target" maturin develop --uv && cd <root> && uv pip install -e .` -- keep targets per worktree; never share them across worktrees.
- **SGLang** (Python): `cd <root> && uv pip install -e "python"`
- **aiperf** (Python): `cd ~/aiperf && uv pip install -e .`

## Development Patterns

### Git
- Branch naming: `idhanani/dyn-{ticket-number}-{short-description}`
- Manual worktrees live beside their primary checkout at `/home/ubuntu/<repo>-wt/<ticket-or-purpose>`.
- After confirming a manual worktree's PR merged, remove it without `--force` only after checking for tracked/untracked changes, needed ignored artifacts, and unpushed work; then run `git worktree prune`. Its local venv is removed with it.
- Codex-managed worktrees under `$CODEX_HOME/worktrees` are exempt from the manual layout convention.
- Draft PRs first for non-trivial changes. Link Linear tickets in description.
- Worktrees for parallel branch development. On rebase conflicts: preserve local work first (`git stash` or backup branch), then resolve. Don't force-reset without asking.
- For Dynamo and SGLang implementation work, publish branches directly to canonical `origin` (`ai-dynamo/dynamo` or `sgl-project/sglang`) and open same-repository PRs. Use a personal or external fork only when I explicitly request it.
- Default to local targeted commits as work progresses: one logical change per commit after validation.
- When reviewing a PR, use a repository-specific empirical review skill when available. Dynamo and SGLang reviews must finish their normal testing before asking whether to invoke `full-code-review`; use `full-code-review` directly for combined general and deep review requests.
- When posting PR review findings, submit a formal GitHub `COMMENT` review with each finding attached to the relevant diff line. Use `REQUEST_CHANGES` only when explicitly requested; never use a generic PR conversation comment.

## Project Management

- **Linear** for ticket tracking (check if MCP tools are available)
- Large features: spec in Linear first, then break into tickets
- Small tasks: jump straight to implementation
