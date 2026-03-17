# Dotfiles Agent Entrypoint

This repo keeps the scaffold split into shared and agent-specific files under `agents/`.

When operating inside `dotfiles`:
- Read `agents/CLAUDE.md` first for the layout.
- Then read `agents/common.md` plus the overlay that matches the active agent:
  - Codex: `agents/codex.md`
  - Claude: `agents/claude.md`
- Use repo-root `CLAUDE.md` / `AGENTS.md` only as entrypoints that point to `agents/`.
