---
name: scaffold-review
description: Analyze recent conversation history and propose targeted improvements to CLAUDE.md and skills
user-invocable: true
---

# Scaffold Review

Analyze recent Claude Code conversation history to find gaps in your current scaffolding (CLAUDE.md, skills, plugin) and propose targeted, incremental improvements.

## What This Skill Does

1. Reads recent conversation JSONL files from `~/.claude/projects/`
2. Extracts signals: user messages, tool usage, corrections, repeated patterns
3. Compares against current CLAUDE.md and skills
4. Proposes specific, small changes -- not rewrites

## Step 1: Determine Scope

Check when the last review was run:

!`cat ~/.claude/scaffold-review-last-run 2>/dev/null || echo "never"`

Find conversations modified since last run (or last 7 days if first run):

!`find ~/.claude/projects/ -name '*.jsonl' -mtime -7 -size +10k | sort | head -20`

## Step 2: Extract Signals

For each recent conversation JSONL file, parse records and extract:

### A. User Corrections and Redirections

Look for user messages that correct Claude's behavior. These indicate gaps in CLAUDE.md.

Patterns to detect:
- "no, I meant..." / "that's not what I asked" / "actually..."
- "don't do X" / "always do Y" / "I told you to..."
- Short frustrated messages after long Claude responses
- User interrupts (`[Request interrupted by user]`) followed by redirection

### B. Repeated Context Setting

Look for information the user provides at the start of multiple conversations. If the user keeps explaining the same thing, it should be in CLAUDE.md.

Extract the first 1-3 user messages from each conversation and look for recurring themes.

### C. Tool Usage Patterns

From assistant messages with `type: "tool_use"`, aggregate:

- **Bash commands**: Group by command prefix (git, cargo, python, etc.). Frequent multi-step command sequences are candidates for skills.
- **File reads**: Most-read files across conversations. If a file is read in >30% of sessions, it should be referenced in CLAUDE.md or a skill.
- **Skill invocations**: Which skills are actually used? Unused skills should be pruned.

### D. Workflow Patterns

Look for sequences of tool calls that repeat across conversations. For example:
- `Read file X` -> `Edit file X` -> `Bash: cargo check` (common edit-compile cycle)
- `Bash: git diff` -> `Bash: git add` -> `Bash: git commit` (commit pattern)
- `Read launch script` -> `Bash: launch server` -> `Bash: curl test` (test pattern)

### E. Files and Paths

Aggregate all file paths from Read and Edit tool calls. New paths that appear frequently but aren't in CLAUDE.md or skills indicate the scaffold is drifting from actual work.

## Step 3: Compare Against Current Scaffold

Read the current scaffold files:

- `~/.claude/CLAUDE.md`
- All `~/.claude/skills/*/SKILL.md`
- `~/dynamo-claude-plugin/skills/*/SKILL.md` (if in dynamo project)

For each signal found in Step 2, check if it's already covered. Only flag genuine gaps.

## Step 4: Propose Changes

Present findings as a categorized list. For each finding, include:
- **Evidence**: Which conversations/messages surfaced this
- **Current state**: What the scaffold says now (or doesn't)
- **Proposed change**: The specific edit (file, section, content)

Categories (in priority order):

### Corrections (highest priority)
Things the user explicitly corrected. These are definite gaps.

### Missing Context
Information repeatedly provided by the user that should be baked in.

### New Paths / Architecture Drift
Files and directories that are heavily accessed but not referenced anywhere.

### Skill Candidates
Repeated multi-step workflows that could become skills.

### Stale Content
References in CLAUDE.md or skills to files/paths/patterns that no longer appear in conversations.

### Skill Pruning
Skills that haven't been invoked in any recent conversation.

## Step 5: Apply (with approval)

For each proposed change:
1. Show the exact diff (old vs new)
2. Ask for approval before applying
3. Apply approved changes
4. Update the last-run timestamp:

```bash
date -Iseconds > ~/.claude/scaffold-review-last-run
```

## Guidelines

- **Be incremental.** Propose 3-7 changes per run, not 30. Small diffs are easier to review and less likely to break things.
- **Prefer additions over rewrites.** Add a line to CLAUDE.md rather than restructuring a section.
- **Evidence-based only.** Every proposal must cite specific conversations or usage data. No speculative improvements.
- **Respect scope.** Personal CLAUDE.md is about the user's preferences and environment. Project-specific knowledge goes in project CLAUDE.md or skills.
- **Don't over-index on one conversation.** A pattern needs to appear in 2+ conversations to be actionable.

## Conversation JSONL Format

Records have a `type` field: `user`, `assistant`, `system`, `progress`, `file-history-snapshot`.

**User records:**
```json
{"type": "user", "message": {"role": "user", "content": "..."}, "timestamp": "...", "uuid": "..."}
```

**Assistant records:**
```json
{"type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": "..."}, {"type": "tool_use", "name": "Bash", "input": {"command": "..."}}]}, "timestamp": "..."}
```

Content blocks in assistant messages can be: `text`, `tool_use`, `thinking`.
Tool use blocks have `name` (tool name) and `input` (tool parameters).
