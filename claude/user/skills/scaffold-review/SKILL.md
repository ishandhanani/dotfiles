---
name: scaffold-review
description: Analyze conversation history, find gaps and drift in CLAUDE.md and skills, propose and apply targeted improvements.
user-invocable: true
---

# Scaffold Review

Analyze recent Claude Code conversation history to find what's broken, stale, or missing in your scaffolding (CLAUDE.md, skills, project configs). Propose changes, apply them, and record what you did.

The goal is **convergence**: each run brings the scaffold closer to how the user actually works.

---

## Step 1: Load State

Read the review ledger (memory of prior runs):

!`cat ~/.claude/scaffold-review-ledger.json 2>/dev/null || echo '{"runs": [], "deferred": [], "trends": []}'`

Find conversations since last run (or last 14 days if first run), with sizes for budgeting:

!`find ~/.claude/projects/ -name '*.jsonl' -not -path '*/subagents/*' -mtime -14 -size +10k -exec ls -lh {} \; | awk '{print $5, $9}' | sort -k2`

**Budget check:** If total JSONL exceeds 5MB, split the corpus across agents rather than having each read everything.

---

## Step 2: Extract Signals

Spawn **3 focused subagents** to analyze the conversations in parallel. Each gets a clear, narrow mandate. Use `model: "haiku"` for extraction work.

### Agent 1: Corrections & Friction

Scan user messages for:
- Explicit corrections ("no, I meant...", "that's not what I asked", "actually...")
- Behavioral directives ("don't do X", "always do Y")
- Frustration markers (short messages after long Claude responses, re-prompting the same thing)
- User doing something manually after Claude offered to do it (trust failure)

For each correction, answer: **Is there scaffold guidance for this? Was it followed? Was it wrong?**

Output: list of corrections with root cause (missing guidance / stale guidance / buried guidance / wrong guidance).

### Agent 2: Usage Patterns & Drift

From assistant `tool_use` blocks, extract:
- **File access heatmap**: top 20 files by Read/Edit frequency. Compare against what CLAUDE.md references.
- **Command frequency**: top commands by prefix (git, python, cargo, etc.)
- **Skill invocation rates**: which skills are used, which are never used
- **New tools/patterns**: anything in recent conversations but not older ones
- **Dead references**: paths in CLAUDE.md that no longer appear in conversations

Output: frequency tables + list of stale/missing references.

### Agent 3: Workflow & Structure

Look at multi-step patterns:
- Repeated sequences across conversations (e.g., kill server -> launch -> health check -> benchmark -> kill)
- Session preambles: first 3 user messages from each conversation. If the user explains the same thing across 2+ sessions, that's a scaffold gap.
- Things that disappeared: commands/files/patterns that used to appear but don't anymore

Classify patterns by stability:
- **Crystallized** (5+ conversations): codify into skill or CLAUDE.md
- **Stable** (3-4): add as guidance, keep watching
- **Emerging** (2): note as trend, don't codify yet

Output: pattern list with stability ratings + gap analysis.

### Subagent Rules (all agents)

1. **Never read a full JSONL file.** Use `head -c 50000` or targeted grep extraction:
   ```bash
   # User messages only
   grep '"type":"user"' file.jsonl | python3 -c "import sys,json; [print(json.loads(l)['message']['content'][:200]) for l in sys.stdin]"

   # Tool usage counts
   grep -o '"name":"[^"]*"' file.jsonl | sort | uniq -c | sort -rn | head -20

   # File paths from Read/Edit calls
   grep -o '"file_path":"[^"]*"' file.jsonl | sort | uniq -c | sort -rn | head -30
   ```
2. **Max 15-20 conversations per agent.** Sample by recency if there are more.
3. **Return structured findings in <300 lines.** Conclusions, not data dumps.

---

## Step 3: Synthesize & Compare

After all agents report, read the current scaffold:
- `~/.claude/CLAUDE.md`
- All `~/.claude/skills/*/SKILL.md`
- Project-specific CLAUDE.md files (find via conversation paths)

Cross-reference agent findings against the scaffold. Classify each finding:

| Status       | Meaning                              | Action              |
| ------------ | ------------------------------------ | ------------------- |
| **Conflict** | Scaffold says X, user corrects to Y  | Fix immediately     |
| **Stale**    | Scaffold references dead path/tool   | Update or remove    |
| **Gap**      | Repeated pattern, scaffold is silent | Add content         |
| **Buried**   | Info exists but in wrong place       | Reorganize          |
| **Dead**     | Skill/section never used             | Remove              |

Also compare against ledger trends:
- **Confirmed** (seen 3+ runs): should have prominent scaffold placement
- **Emerging** (seen 2 runs): note, don't act yet
- **Reversed** (was trending, stopped): investigate why -- scaffold fix worked, or user gave up?

---

## Step 4: Propose Changes

Organize proposals by type:

### Tier 1: Corrections
Things the user explicitly corrected. Highest confidence -- apply unless vetoed.

### Tier 2: Structural
Reorganizations: sections that should be split into skills, skills that overlap and should merge, info in the wrong file.

### Tier 3: New Content
Workflows, paths, patterns that belong in the scaffold but aren't there yet. Apply the necessity test: would this have prevented a specific observed failure? If Claude would get it right without the guidance, don't add it.

### Tier 4: Deletions
Stale content, unused skills, dead references. Show evidence of staleness.

### Tier 5: New Skills
Only if a crystallized workflow (5+ conversations) would clearly benefit from being a dedicated skill. Don't create skills speculatively.

For each proposal, include:
- **Evidence**: which conversations, what frequency
- **Current state**: what the scaffold says now (quote it)
- **Proposed change**: the exact edit
- **Confidence**: high / medium / low

Present all proposals to the user before applying.

---

## Step 5: Apply & Record

For approved changes:

1. Apply all edits
2. Re-read modified files to check for internal consistency
3. Update the ledger:

```json
{
  "timestamp": "<now>",
  "conversations_analyzed": "<count>",
  "proposals": [
    {
      "description": "...",
      "tier": "<1-5>",
      "status": "applied|deferred|rejected",
      "confidence": "high|medium|low"
    }
  ],
  "trends_updated": ["..."]
}
```

Write ledger:
```bash
cat > ~/.claude/scaffold-review-ledger.json << 'EOF'
<updated ledger content>
EOF
```

For deferred proposals, record the reason so a future run can reassess.

---

## Conversation JSONL Format

Records have a `type` field: `user`, `assistant`, `system`, `progress`, `file-history-snapshot`.

**User records:**
```json
{
  "type": "user",
  "message": { "role": "user", "content": "..." },
  "timestamp": "..."
}
```

**Assistant records:**
```json
{
  "type": "assistant",
  "message": {
    "role": "assistant",
    "content": [
      { "type": "text", "text": "..." },
      { "type": "tool_use", "name": "Bash", "input": { "command": "..." } }
    ]
  }
}
```

Content blocks in assistant messages: `text`, `tool_use`, `thinking`.
Tool use blocks have `name` (tool name) and `input` (tool parameters).
