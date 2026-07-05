---
name: phone-a-friend
description: Ask one or more fresh Claude Code processes for parallel, independent, read-only verification, design adjudication, or adversarial review while Codex retains ownership of the task. Use when the user explicitly asks for a Claude second opinion, cross-model verification, parallel independent review, or when a consequential code/design/benchmark decision benefits from an unprimed verifier.
---

# Phone a Friend

Use Claude as an independent verifier, not as an implementation owner.

## Workflow

1. Decide the verification question before launching anything. Skip delegation when local evidence already answers a routine question.
2. Create one to three narrow prompts. Give each friend the artifact or exact local paths, the goal, constraints, and requested output. Default to read-only inspection and ask for a verdict plus file-and-line evidence.
3. Preserve independence. Do not include Codex's conclusion, suspected bug, preferred fix, or another friend's answer unless the task is explicitly adjudication.
4. Run fresh Claude processes in parallel with `scripts/phone_a_friend.py`. Keep the current worktree as `--cwd`; add other required roots with `--add-dir`.
5. Verify material claims against the artifact. Codex owns synthesis and the final decision; never treat agreement as proof.
6. Report consensus, disagreement, and any locally confirmed finding. Do not dump raw friend transcripts unless requested.

## Invocation

```bash
uv run "${CODEX_HOME:-$HOME/.codex}/skills/phone-a-friend/scripts/phone_a_friend.py" \
  --cwd /absolute/worktree \
  --prompt 'Review the current diff for correctness. Read only. Return APPROVE or REJECT, then material findings with file:line evidence.' \
  --prompt 'Independently inspect the same diff for hot-path regressions and unnecessary abstractions. Read only. Return material findings with file:line evidence.'
```

The runner is a self-contained `uv` script with inline dependency metadata. It uses Claude's safe mode and plan permission mode, starts one fresh process per prompt, disables Claude session persistence, and returns structured JSON. Safe mode prevents project instructions, skills, hooks, plugins, and memory from silently priming the verifier; put every required constraint in the prompt. If `claude` is unavailable, unauthenticated, times out, or returns an error, report that instead of silently substituting another model.

## Prompt rules

- Give the minimum task-local context needed to inspect the raw artifact.
- Use separate prompts for genuinely distinct review surfaces; use duplicate scopes only when independent agreement itself matters.
- State `Do not edit files, launch services, or change external state` unless the user explicitly authorized those actions.
- Ask for material findings only. Require exact evidence and a concise verdict.
- Never send secrets, credentials, unrelated transcript history, or private data that the task does not require.
- Never add `--dangerously-skip-permissions`; the runner intentionally enforces read-only plan mode.
- Never remove `--safe-mode`; ambient project memory can manufacture false consensus.
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
