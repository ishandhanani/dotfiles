---
name: phone-a-friend
description: Ask Claude, Cursor, or Devin through ACP for parallel independent verification, design adjudication, or explicitly authorized delegated action. Use for second opinions, cross-model checks, fast parallel workers, persistent multi-turn friend sessions, or a subagent that must drive another agent across turns while the caller retains ownership.
---

# Phone a Friend

Use ACP sessions, not one-shot CLI prompts. The caller owns synthesis and the final decision; agreement is not proof.

## Choose the topology

- **Independent fanout (default):** Repeat `--prompt`. The runner creates one fresh ACP session per prompt and drives them concurrently over one agent connection. Use this for parallel reviews or disjoint work.
- **Persistent chat (`--chat`):** The runner creates one ACP session and accepts JSONL commands on stdin until closed. Use this when a friend needs context across multiple turns.
- **Nested branch:** Spawn one Codex subagent per independent branch. Each subagent owns its own `--chat` process and ACP session, drives it across turns, verifies its branch locally, then returns a compact report. Do not make the root agent relay every friend turn.

Do not use tmux, scrape interactive terminal output, call the backend's `-p` mode, or implement JSON-RPC manually. The runner uses the official Python ACP SDK.

## Route the work

Choose these axes before launch:

1. `--speed`: `fast` | `balanced` | `deep`
2. `--capability`: `verify` (default) | `act` (only after explicit user authorization)
3. `--friend`: `auto` | `claude` | `agent` (Cursor) | `devin`

| speed | default friend | model | use when |
|---|---|---|---|
| `fast` | Devin | `swe-1-7-lightning` | latency-sensitive parallel sniff or bounded worker |
| `balanced` | Claude | adapter default | normal independent opinion |
| `deep` | Claude | `opus[1m]` | consequential adjudication |

Backend transports:

- Devin: native `devin acp`
- Cursor: native `agent acp`
- Claude: pinned official `@agentclientprotocol/claude-agent-acp` adapter through `npx`

Override `--friend` or `--model` when appropriate. The model value must be one exposed by the agent's ACP session; stale or invalid values fail visibly. Never silently substitute another backend.

## Workflow

1. Skip delegation if local evidence already answers the question.
2. Give each branch exact paths/artifacts, one bounded goal, constraints, and a strict output shape. Do not prime it with the caller's conclusion or another friend's answer unless adjudication is the task.
3. For `verify`, require read-only inspection. The runner selects a read-only/planning ACP mode and rejects permission requests.
4. For `act`, confirm the user authorized writes or commands. The runner selects the backend's agent/bypass mode and accepts only one-time permission options when the backend still asks.
5. Check `ok` before consuming `response`. Verify material claims against the artifact and report disagreement or failures.
6. For parallel `act`, assign disjoint paths and forbid shared git/index, build directories, and services, then pass `--confirm-parallel-act`. Otherwise use separate invocations rooted in separate worktrees, or run sequentially. The runner rejects repeated `act` prompts without this second confirmation.

ACP does not erase backend-global instructions or configuration. Include enough task-local context for an independent answer and treat every answer as untrusted evidence.

## Independent fanout

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/phone-a-friend/scripts/phone_a_friend.py" \
  --cwd /absolute/worktree \
  --speed fast \
  --friend devin \
  --capability verify \
  --prompt 'Read-only correctness review of the current diff. Return APPROVE or REJECT, then material findings with file:line evidence.' \
  --prompt 'Read-only hot-path review of the current diff. Return PASS or CONCERN, then material findings with file:line evidence.'
```

The JSON array stays in prompt order. Each result includes `backend`, `session_id`, `mode`, `model`, `ok`, and either `response` or `error`. Repeating `--prompt` gives independent sessions, not a conversation.

Use `--add-dir /absolute/path` for extra ACP workspace roots. Fanout defaults to 180 seconds per fast verify prompt, 300 for fast act, and 900 for balanced/deep; override with `--timeout-seconds`.

## Persistent multi-turn chat

Start the process and retain the executor's terminal handle returned out-of-band. When using Codex's terminal executor, set `tty: true` so stdin remains open for later writes:

```bash
"${CODEX_HOME:-$HOME/.codex}/skills/phone-a-friend/scripts/phone_a_friend.py" \
  --chat \
  --cwd /absolute/worktree \
  --speed fast \
  --friend devin \
  --capability verify
```

Wait for one `ready` record, then write exactly one JSON object per line to the same process:

```json
{"prompt":"Inspect src/router.py. Identify the highest-risk invariant and cite file:line evidence."}
{"prompt":"Now test that hypothesis against the call sites. Return a final verdict only."}
{"close":true}
```

The `ready.session_id` value is the ACP conversation ID, not the executor's terminal handle. Each prompt yields one `response` record with that same ACP ID; later turns retain the agent's session context. Chat prompts have no deadline unless `--timeout-seconds` is supplied. Invalid input yields an `error` record, and prompt failures yield an `ok:false` response without corrupting the stream. Closing stdin or sending `{"close":true}` tears down the ACP process.

When a Codex subagent owns this conversation, it must keep the terminal session identifier private to its branch, use subsequent stdin writes for follow-ups, and return only:

```text
Verdict: <one line>
Evidence: <file:line bullets or artifact facts>
Changes/tests: <only if act was authorized>
Unresolved: <remaining uncertainty or none>
```

Set a turn budget in the branch prompt, normally two or three friend turns. A persistent session is for refinement within one scope, not endless autonomous work.

## Prompt shapes

Verification:

```text
Inspect <paths>. Question: <bounded question>. Do not edit files, launch services, or change external state. Return <verdict shape>, then only material findings with exact evidence. Answer the question; do not return a plan or meta-commentary.
```

Delegated action:

```text
Work only in <owned paths>. Apply <bounded change>. Do not touch git/index, shared services, or unowned files. Run <targeted check>. Return changed paths, test result, and unresolved risks.
```

Never send secrets, credentials, unrelated transcript history, or private data the task does not require. On timeout, inspect possible partial edits before retrying an `act` turn.

## Diagnostics

Resolve routing without starting an agent:

```bash
.../phone_a_friend.py --dry-run --cwd /absolute/worktree --speed fast --prompt '...'
```

Authentication, adapter startup, missing executables, unsupported modes/models, timeouts, and empty answers are explicit failures. Fix the actual backend or narrow the task; do not weaken `verify` or silently fall back.
