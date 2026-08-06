---
name: phone-a-friend
description: Ask one or more fresh friend agents (claude, Cursor agent, or Devin) for parallel independent verification, design adjudication, or opt-in delegated action while the caller retains ownership. Use when the user asks for a second opinion, cross-model verification, parallel independent review, a fast sniff from another agent, or when a consequential code/design/benchmark decision benefits from an unprimed verifier.
---

# Phone a Friend

Dispatch one or more fresh friend processes. The caller owns synthesis and the final decision; never treat agreement as proof.

## Routing

Pick axes before launching:

1. **`--speed`** (primary): `fast` | `balanced` | `deep`
2. **`--capability`**: `verify` (default, read-only) | `act` (writes/shell; only when explicitly authorized)
3. **`--friend`**: `auto` (default from speed) | `claude` | `agent` | `devin`

| speed | default friend | default model | use when |
|-------|----------------|---------------|----------|
| `fast` | `devin` | `swe-1-7-lightning` | cheap parallel sniff, latency-sensitive |
| `balanced` | `claude` | CLI default | normal second opinion |
| `deep` | `claude` | `opus` | consequential adjudication |

Override with `--friend` / `--model` when needed. Prefer **claude** when independence matters more than latency: only Claude's verify profile strips ambient project memory (`--safe-mode`). `agent` / `devin` may still see workspace rules/skills.

### Capability flags (enforced by the runner)

| friend | `verify` | `act` |
|--------|----------|-------|
| `claude` | `--safe-mode --permission-mode plan` | `--permission-mode bypassPermissions` |
| `agent` | `--mode ask --trust` | `--yolo --trust` |
| `devin` | `--permission-mode auto` | `--permission-mode dangerous` |

### Backend-specific notes

- **claude**: Use when independence matters most. `--safe-mode` strips ambient project memory/skills, so the friend is least likely to be primed by your own context. Best for verify tasks that need exact file:line evidence.
- **agent** (Cursor): Requires `agent login` or `CURSOR_API_KEY`. Verify mode uses `--mode ask`, which is read-only Q&A. If you see a plan or outline instead of an answer, the prompt may be too broad; narrow it or switch to `claude`/`devin`. `agent` may still see global Cursor skills/context even with `--workspace` and `--add-dir`.
- **devin**: Cheapest/fastest for sniff tasks. No JSON output; response lands in `stdout`. Does not support `--add-dir`; name extra roots in the prompt.

## Workflow

1. Decide the question. Skip delegation when local evidence already answers it.
2. Choose `--speed` (and `--capability act` only if the user authorized edits/commands).
3. Create one to three narrow prompts. Give each friend the artifact or exact local paths, goal, constraints, and requested output.
4. Preserve independence. Do not include the caller's conclusion, suspected bug, preferred fix, or another friend's answer unless the task is explicitly adjudication.
5. Run fresh processes in parallel with `scripts/phone_a_friend.py`. Keep the current worktree as `--cwd`; add other required roots with `--add-dir` (claude/agent only).
6. Verify material claims against the artifact. Report consensus, disagreement, and any locally confirmed finding. Do not dump raw friend transcripts unless requested.
7. If a friend is unavailable, unauthenticated, times out, or errors, report that. Never silently substitute another backend.

## Invocation

```bash
uv run "${CODEX_HOME:-$HOME/.codex}/skills/phone-a-friend/scripts/phone_a_friend.py" \
  --cwd /absolute/worktree \
  --speed balanced \
  --capability verify \
  --prompt 'Review the current diff for correctness. Read only. Return APPROVE or REJECT, then material findings with file:line evidence.' \
  --prompt 'Independently inspect the same diff for hot-path regressions and unnecessary abstractions. Read only. Return material findings with file:line evidence.'
```

Fast sniff:

```bash
uv run "${CODEX_HOME:-$HOME/.codex}/skills/phone-a-friend/scripts/phone_a_friend.py" \
  --cwd /absolute/worktree \
  --speed fast \
  --prompt 'Read-only: does this diff obviously break the hot path in <file>? Verdict + file:line evidence only.'
```

Deep Claude adjudication (explicit friend):

```bash
uv run "${CODEX_HOME:-$HOME/.codex}/skills/phone-a-friend/scripts/phone_a_friend.py" \
  --cwd /absolute/worktree \
  --speed deep \
  --friend claude \
  --prompt 'Compare only options A and B against <constraints>. Do not edit. Approve one, reject the other, cite file:line evidence.'
```

Opt-in act (user must authorize):

```bash
uv run "${CODEX_HOME:-$HOME/.codex}/skills/phone-a-friend/scripts/phone_a_friend.py" \
  --cwd /absolute/worktree \
  --speed fast \
  --capability act \
  --prompt 'Apply the minimal fix described in <paths>. Do not broaden scope.'
```

Dry-run (print resolved profile + argv, no execution):

```bash
uv run .../phone_a_friend.py --dry-run --cwd /absolute/worktree --speed fast --prompt '...'
```

The runner is a self-contained `uv` script. One fresh process per `--prompt`; no session resume/cross-feed. Returns structured JSON. Devin has no JSON output mode — its payload lands in `stdout`. Devin also does not support `--add-dir`; name extra roots in the prompt or use `--friend claude|agent`.

## Prompt rules

- Give the minimum task-local context needed to inspect the raw artifact.
- Use separate prompts for genuinely distinct review surfaces; duplicate scopes only when independent agreement itself matters.
- For `verify`, state `Do not edit files, launch services, or change external state`.
- For `act`, require an explicit user authorization trail in the calling turn; keep the blast radius minimal.
- Ask for material findings only. Require exact evidence and a concise verdict.
- For backends that can fall back to planning mode (`agent`), explicitly demand the final answer: `Answer the question and return the result. Do not output a plan, outline, or meta-commentary.`
- Never send secrets, credentials, unrelated transcript history, or private data the task does not require.
- Do not weaken verify flags (`--safe-mode`, ask/auto modes) to chase a green run.
- Do not resume or cross-feed friend sessions. Fresh context is the point.

## Useful prompt shapes

Design adjudication:

```text
Inspect <paths>. Goal: <goal>. Compare only options A and B against <constraints>. Do not edit. Approve one, reject the other, identify hidden risks, and name the smallest safe next step with file:line evidence.
```

Patch review:

```text
Review only the current diff in <worktree>. Check <bounded concerns>. Validation already performed: <facts>. Do not edit or rerun destructive operations. Return APPROVE or REJECT first, then material blockers with file:line evidence.
```

Benchmark adjudication:

```text
Read <artifacts>. The predeclared guard is <guard>. Decide the minimum defensible next action among <choices>. Identify confounders and cite artifact evidence. Do not edit or launch workloads.
```

Fast sniff:

```text
Read-only skim of <paths or diff>. Question: <yes/no or A/B>. Return verdict first, then at most three file:line evidence bullets. No fixes.
```
