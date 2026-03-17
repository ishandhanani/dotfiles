---
name: scaffold-review
description: Analyze conversation history, find gaps and drift in AGENTS/CLAUDE instructions and skills, propose and apply targeted improvements.
user-invocable: true
---

# Scaffold Review

Analyze recent agent conversation history to find what's broken, stale, or missing in your scaffolding (AGENTS/CLAUDE instructions, skills, project configs). Propose changes, apply them, and record what you did.

The goal is **convergence**: each run brings the scaffold closer to how the user actually works.

---

## Step 1: Load State

Resolve the active agent home:

```bash
if [ -n "${AGENT_HOME:-}" ]; then
  :
elif [ -n "${CODEX_HOME:-}" ] || [ -n "${CODEX_THREAD_ID:-}" ] || [ -n "${CODEX_CI:-}" ]; then
  AGENT_HOME="${CODEX_HOME:-$HOME/.codex}"
elif [ -n "${CLAUDE_HOME:-}" ] || [ -n "${CLAUDECODE:-}" ] || [ -n "${CLAUDE_CODE:-}" ]; then
  AGENT_HOME="${CLAUDE_HOME:-$HOME/.claude}"
elif [ -d "$HOME/.codex/sessions" ] && [ ! -d "$HOME/.claude/projects" ]; then
  AGENT_HOME="$HOME/.codex"
elif [ -d "$HOME/.claude/projects" ] && [ ! -d "$HOME/.codex/sessions" ]; then
  AGENT_HOME="$HOME/.claude"
else
  echo "Unable to infer AGENT_HOME. Set AGENT_HOME explicitly." >&2
  exit 1
fi
```

Read the review ledger (memory of prior runs):

!`cat "$AGENT_HOME/scaffold-review-ledger.json" 2>/dev/null || echo '{"runs": [], "deferred": [], "trends": []}'`

Find conversations since last run (or last 14 days if first run), with sizes for budgeting:

!`if [ -d "$AGENT_HOME/projects" ]; then find "$AGENT_HOME/projects" -name '*.jsonl' -not -path '*/subagents/*' -mtime -14 -size +10k -exec ls -lh {} \; ; elif [ -d "$AGENT_HOME/sessions" ]; then find "$AGENT_HOME/sessions" -name '*.jsonl' -mtime -14 -size +10k -exec ls -lh {} \; ; fi | awk '{print $5, $9}' | sort -k2`

**Budget check:** If total JSONL exceeds 5MB, split the corpus across agents rather than having each read everything.

---

## Step 2: Extract Signals

Use **3 focused analyzers** in parallel. For Codex, these are parallel shell/Python extraction passes over JSONL, not separate agent sessions.

### Agent 1: Corrections & Friction

Scan user messages for:
- Explicit corrections ("no, I meant...", "that's not what I asked", "actually...")
- Behavioral directives ("don't do X", "always do Y")
- Frustration markers (short messages after long assistant responses, re-prompting the same thing)
- User doing something manually after the assistant offered to do it (trust failure)

For each correction, answer: **Is there scaffold guidance for this? Was it followed? Was it wrong?**

Output: list of corrections with root cause (missing guidance / stale guidance / buried guidance / wrong guidance).

### Agent 2: Usage Patterns & Drift

From assistant tool-call records, extract:
- **File access heatmap**: top 20 files by Read/Edit frequency. Compare against what AGENTS/CLAUDE instructions reference.
- **Command frequency**: top commands by prefix (git, python, cargo, etc.)
- **Skill invocation rates**: which skills are used, which are never used
- **New tools/patterns**: anything in recent conversations but not older ones
- **Dead references**: paths in AGENTS/CLAUDE instructions that no longer appear in conversations

Output: frequency tables + list of stale/missing references.

### Agent 3: Workflow & Structure

Look at multi-step patterns:
- Repeated sequences across conversations (e.g., kill server -> launch -> health check -> benchmark -> kill)
- Session preambles: first 3 user messages from each conversation. If the user explains the same thing across 2+ sessions, that's a scaffold gap.
- Things that disappeared: commands/files/patterns that used to appear but don't anymore

Classify patterns by stability:
- **Crystallized** (5+ conversations): codify into skill or AGENTS/CLAUDE instructions
- **Stable** (3-4): add as guidance, keep watching
- **Emerging** (2): note as trend, don't codify yet

Output: pattern list with stability ratings + gap analysis.

### Analyzer Rules (all analyzers)

1. **Never read a full JSONL file.** Use `head -c 50000` or targeted grep extraction:
   ```bash
   # Codex user messages
   python3 - <<'PY'
   import json
   for line in open("file.jsonl", errors="ignore"):
       obj = json.loads(line)
       if obj.get("type") != "response_item":
           continue
       payload = obj.get("payload", {})
       if payload.get("type") != "message" or payload.get("role") != "user":
           continue
       parts = [block.get("text", "") for block in payload.get("content", []) if block.get("type") == "input_text"]
       text = " ".join(parts)
       if text:
           print(text[:200])
   PY

   # Codex tool usage counts
   grep '"type":"function_call"' file.jsonl | grep -o '"name":"[^"]*"' | sort | uniq -c | sort -rn | head -20

   # Command prefixes from exec_command calls
   python3 - <<'PY'
   import json
   from collections import Counter
   counts = Counter()
   for line in open("file.jsonl", errors="ignore"):
       obj = json.loads(line)
       if obj.get("type") != "response_item":
           continue
       payload = obj.get("payload", {})
       if payload.get("type") != "function_call" or payload.get("name") != "exec_command":
           continue
       args = json.loads(payload.get("arguments", "{}"))
       cmd = args.get("cmd", "").strip().splitlines()
       if cmd:
           counts[cmd[0].split()[0]] += 1
   for name, count in counts.most_common(20):
       print(count, name)
   PY
   ```
2. **Max 15-20 conversations per analyzer.** Sample by recency if there are more.
3. **Return structured findings in <300 lines.** Conclusions, not data dumps.

### Codex-Specific Notes

- Codex session logs usually store user, assistant, and tool activity under `response_item.payload`.
- Commentary and final answers are both assistant messages; use `payload.phase` when you need to separate progress updates from final responses.
- Tool calls appear as `payload.type == "function_call"` with JSON-encoded `arguments`.
- `write_stdin` polling loops are common in remote or long-running jobs; treat them as one workflow, not separate tasks.

---

## Step 3: Synthesize & Compare

After all agents report, read the current scaffold:
- `"$AGENT_HOME/CLAUDE.md"` (with `AGENTS.md` symlink for Codex)
- All `"$AGENT_HOME/skills/*/SKILL.md"`
- Project-specific `CLAUDE.md` (or `AGENTS.md` symlink) files (find via conversation paths)
- If the scaffold repo uses split sources such as `agents/common.md` plus `agents/codex.md` / `agents/claude.md`, read the matching overlay and compare against the rendered `"$AGENT_HOME/CLAUDE.md"` for drift.

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
Workflows, paths, patterns that belong in the scaffold but aren't there yet. Apply the necessity test: would this have prevented a specific observed failure? If the assistant would get it right without the guidance, don't add it.

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
cat > "$AGENT_HOME/scaffold-review-ledger.json" << 'EOF'
<updated ledger content>
EOF
```

For deferred proposals, record the reason so a future run can reassess.

---

## Conversation JSONL Format

Records differ by agent implementation.

For Codex, the common shape is:

**User / assistant messages:**
```json
{
  "type": "response_item",
  "payload": {
    "type": "message",
    "role": "user|assistant|developer",
    "content": [
      { "type": "input_text|output_text", "text": "..." }
    ],
    "phase": "commentary|final"
  }
}
```

**Tool calls:**
```json
{
  "type": "response_item",
  "payload": {
    "type": "function_call",
    "name": "exec_command",
    "arguments": "{\"cmd\":\"...\"}"
  }
}
```

Claude-style records may still appear in older logs or other agent homes. Prefer the Codex schema when `~/.codex/sessions` is the source.
