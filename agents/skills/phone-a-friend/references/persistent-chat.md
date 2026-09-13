# Persistent ACP sessions

Resolve the runner relative to the loaded skill directory.

## Persistent multi-turn chat

Start the process and retain the executor's terminal handle returned out-of-band. When using Codex's terminal executor, set `tty: true` so stdin remains open for later writes:

```bash
"${SKILL_DIR:?set the loaded phone-a-friend directory}/scripts/phone_a_friend.py" \
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

The `ready.session_id` value is the ACP conversation ID, not the executor's terminal handle. Each prompt yields one `response` record with that same ACP ID; later turns retain the agent's session context. The runner does not impose deadlines. Invalid input yields an `error` record, and prompt failures yield an `ok:false` response without corrupting the stream. Closing stdin or sending `{"close":true}` tears down the ACP process.

When a Codex subagent owns this conversation, it must keep the terminal session identifier private to its branch, use subsequent stdin writes for follow-ups, and return only:

```text
Verdict: <one line>
Evidence: <file:line bullets or artifact facts>
Changes/tests: <only if act was authorized>
Unresolved: <remaining uncertainty or none>
```

Set a turn budget in the branch prompt, normally two or three friend turns. A persistent session is for refinement within one scope, not endless autonomous work.
