# Background monitoring

Run babysitting in the current task unless the user explicitly requests a new user-owned task. Background work alone does not authorize creating sidebar tasks. Use available subagent/background primitives only when the host permits delegation; keep one owner for PR judgments and mutations.

A read-only monitor may watch head SHA, required checks, and unresolved non-outdated AI-review thread IDs, then return only meaningful changes. Do not hard-code model generations or create a new task for each poll. Use bounded waits and stay quiet while the state is unchanged.

The owner adjudicates new evidence and performs authorized fixes, replies, resolutions, and retries. Pass exact PR/head identity, changed checks/threads, and failed-run URLs. A monitor never independently changes GitHub or the worktree. When a separate user-owned task is explicitly requested, use the host's task tools and preserve the current task as coordinator only if that matches the request.
