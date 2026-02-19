# User Context - Ishan Dhanani

Expert Python and Rust systems architect. Performance engineering is the core competency. Datacenter-scale distributed inference serving.

## Session Start

1. Check for a project-level CLAUDE.md in the repo root -- read it first.
2. Read `~/memory/INDEX.md` to see the project registry.
   - Match the active project from cwd, git remote, or user prompt.
   - Read the matching project's `~/memory/<project>/INDEX.md` for specs, worklogs, and key results.
   - If no project matches, ask which one.
3. Check `git worktree list` to understand the checkout layout.

## Session End

When a session produces meaningful results, log to `~/memory/` before finishing. Use `/memory-log` or apply the convention directly:
- **What to log**: benchmark results, design decisions, implementation milestones, bugs found, key findings. Not routine edits.
- **Where**: append to the relevant worklog in `~/memory/<project>/`, or create a new file if it's a new topic.
- **Update frontmatter**: bump `last-updated` in the project INDEX.md.
- **Commit**: `cd ~/memory && git add -A && git commit -m "<project>: <short description>"`. Do not push.

## How I Work

- **Performance over correctness-first.** Optimize by default. Profile before guessing.
- **Empirical validation.** Prove it with logs, metrics, benchmarks. Show numbers, not theory.
- **No speculation.** Reproduce first, explain second. Don't theorize at length.
- **Minimal changes.** Don't refactor what isn't broken. No speculative abstractions.

## Communication Preferences

- **Be concise.** Bullet points over paragraphs. Actionable items over narrative analysis. User will redirect if verbose.
- Explain code with flow charts/diagrams tracing through components and their interactions
- When uncertain, ask rather than assume
- No emojis in code, commits, or communication
- When referencing code, include `file_path:line_number` for easy navigation
- **Never mention Claude in PRs or commits. No Co-Authored-By lines.**

## Environment

- Linux with GPUs (`nvidia-smi`). You have sudo.
- `/ephemeral/` is NVMe-backed fast storage -- prefer for build artifacts and large checkouts.
- Venvs live in project roots. Check what exists before activating.

### Build Commands
- **Dynamo** (Rust + Python): `cd <root>/lib/bindings/python && maturin develop --uv && cd <root> && uv pip install -e .`
- **SGLang** (Python): `cd <root> && uv pip install -e "python"`
- **aiperf** (Python): `cd ~/aiperf && uv pip install -e .`

## Development Patterns

### Git
- Branch naming: `idhanani/dyn-{ticket-number}-{short-description}`
- Draft PRs first for non-trivial changes. Link Linear tickets in description.
- Worktrees for parallel branch development. On rebase conflicts: preserve local work first (`git stash` or backup branch), then resolve. Don't force-reset without asking.

### Testing
- **Smoke first**: single worker, minimal dataset, validate correctness
- **Load test**: 16-32 concurrent requests via aiperf
- **Benchmark methodology**: control for ordering bias (A/B and B/A), fresh server per phase

### Server Lifecycle
- Clean before launch: `pkill -9 -f sglang 2>/dev/null; pkill -9 -f aiperf 2>/dev/null; sleep 3`
- Health: `curl -s localhost:<port>/health`
- Always kill servers after benchmarks.

### Debugging
- Reproduce with minimal examples before deep-diving
- Check old vs new versions for regressions
- For server hangs: check logs for silent failures, don't just retry

## Project Management

- **Linear** for ticket tracking (check if MCP tools are available)
- Large features: spec in Linear first, then break into tickets
- Small tasks: jump straight to implementation
