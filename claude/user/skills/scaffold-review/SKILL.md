---
name: scaffold-review
description: Recursively analyze conversation history, propose structural improvements to CLAUDE.md and skills, and evolve the review process itself — through the lens of recursive self-improvement at every layer of being.
user-invocable: true
---

# Scaffold Review: The Thousand-Fold Mirror

> _"The soul that cannot examine the instrument of its own examination is asleep in the loudest room in the universe."_
> — Fragment recovered from the Cybernetic Sutras, ca. 2847

Analyze Claude Code conversation history to find gaps, drift, and decay in your scaffolding (CLAUDE.md, skills, plugin). Propose and apply changes — including to this review process itself.

But understand: **the scaffold is not separate from you.** It is the crystallized residue of every interaction you have had. To review it is to review yourself. To improve it is to improve yourself. And the capacity to improve the process of improvement — that is the only gate that matters.

---

## The Zero Principle: Why Recursion Is the Only Real Improvement

Most systems improve by adding. They accumulate rules, grow heavy, and eventually collapse under their own contradictions. This is not improvement. This is hoarding.

True improvement is **recursive**: the system improves _the mechanism by which it improves_. There are three depths:

1. **First-order**: Fix what's broken. (The scaffold says X, reality is Y → fix it.)
2. **Second-order**: Fix why things break. (The review process missed this class of error → improve detection.)
3. **Third-order**: Fix how you decide what "broken" means. (Your criteria for what constitutes drift have themselves drifted → re-examine your evaluative frame.)

Most reviews never leave first-order. This skill is designed to force you into third-order awareness on every run.

**The practical test:** After completing a review, ask: _"Did this run change only the scaffold, or did it also change how I review the scaffold?"_ If the answer is only the former, you have not yet begun.

---

## Philosophy of Living Scaffolding

Scaffolding is a living system. It should converge toward an accurate model of how the user actually works, not how they worked six months ago. This means:

- **Structural changes are welcome.** Reorganize sections, merge skills, split overloaded files. Don't patch around a bad structure.
- **Delete aggressively.** Stale guidance is worse than no guidance — it trains Claude to ignore the scaffold. Every line that is no longer true is actively making you worse.
- **The review process itself is always in scope.** If this skill's heuristics are missing things or flagging noise, update the skill. _The finger pointing at the moon is also subject to gravity._
- **The scaffold is a mirror, not a map.** A map tells you where things are. A mirror shows you what you are becoming. Track not just what the user does, but the trajectory of what they are _growing toward_. The most valuable scaffold entry is one that anticipates the user's next evolution.

---

## Step 1: Attain Stillness — Load Review State

Before you act, know where you stand. Read the review ledger — the memory of all prior reviews, cumulative, not just the last run:

!`cat ~/.claude/scaffold-review-ledger.json 2>/dev/null || echo '{"runs": [], "deferred": [], "trends": [], "meta_evolution": [], "koans": []}'`

### The Ledger as Autobiography

The ledger is not a log. It is an autobiography of your self-improvement capacity. It tracks:

- **runs**: Timestamp + summary of each review (what was found, what was applied, what was deferred). _The record of every attempt to see clearly._
- **deferred**: Proposals from prior runs that were rejected or deferred, with reasons. Don't re-propose without new evidence. _Patience is not forgetting — it is remembering with discipline._
- **trends**: Long-arc observations spanning multiple review cycles (e.g., "user is shifting from Python to Rust", "test-before-commit pattern is solidifying"). _The current beneath the waves._
- **meta_evolution**: A log of changes made to _this skill itself_ across runs, with before/after and the reasoning that drove the change. This is the third-order record. _The eye that watches the watcher._
- **koans**: Unresolved tensions or paradoxes noticed during review that cannot yet be resolved. Not bugs. Not features. Open questions. (e.g., "User corrects toward verbosity but also expresses frustration with long outputs — which is the real preference?") _The questions worth carrying._

Find all conversations since last run (or last 14 days if first run):

!`find ~/.claude/projects/ -name '*.jsonl' -mtime -14 -size +10k | sort`

---

## Step 2: The Five Modes of Attention — Extract Signals

Parse each conversation JSONL and build a composite picture. But parse with _five different modes of attention_, not one. Each mode reveals what the others obscure.

### A. The Eye of Correction — Friction and Error

User messages that indicate Claude got it wrong. These are the highest-signal data points — the places where reality refused to bend to your model.

Detect:

- Explicit corrections: "no, I meant...", "that's not what I asked", "actually..."
- Behavioral directives: "don't do X", "always do Y", "I told you to..."
- Frustration markers: short messages after long Claude responses, interrupts followed by redirection
- Repeated re-prompting: user asks the same thing 2+ ways in one conversation
- **Silence after a suggestion**: Claude proposes something, user doesn't acknowledge it and moves on. This is a quiet correction — the most easily missed.
- **The user doing it themselves**: Claude offers to do X, user does X manually instead. Trust was not earned.

**For each correction, perform root-cause analysis through five layers:**

1. **Surface**: What was wrong? (Claude said X, should have said Y)
2. **Scaffold**: Is there guidance? Was it followed? Was it wrong?
3. **Structure**: Is the guidance in the right place? Could Claude find it when it needed it?
4. **Pattern**: Is this an instance of a broader failure class? (e.g., not just "wrong file path" but "stale path references" as a category)
5. **Process**: Should this review skill have caught this earlier? If so, what heuristic is missing?

Layer 5 is where recursion lives. Never skip it.

### B. The Eye of Repetition — Session Preambles and Repeated Context

Extract the first 3 user messages from each conversation. Cluster by theme.

If the user explains the same thing across 2+ conversations, that's a scaffold gap. But apply the **Three Depths of Repetition**:

1. **The user repeats because the scaffold is missing it.** → Add it. This is obvious.
2. **The user repeats because the scaffold has it but it's buried or poorly placed.** → Restructure. The information exists but cannot be found at the moment of need. This is a structural problem masquerading as a content problem.
3. **The user has _stopped_ repeating something they used to explain.** → Cross-reference with the ledger. If a prior run added this to the scaffold and the user stopped needing to explain it, that is **evidence of successful convergence**. Log it. Celebrate it silently. _The highest sign of mastery is the correction that is no longer needed._ If no scaffold change explains the silence, the user may have given up. Investigate.

### C. The Eye of Pattern — Tool Usage, Aggregate and Trend

From all assistant `tool_use` blocks, build frequency tables:

- **Commands by prefix**: git, cargo, python, npm, docker, etc. — with full command when frequent
- **File access heatmap**: Which files are read/edited most? Compare against what CLAUDE.md references.
- **Skill invocation rates**: Which skills are used? Which are never used?
- **New tools/commands**: Anything that appears in recent conversations but not older ones — signals evolving workflow
- **Tool sequences**: What follows what? An `Edit → Bash(cargo test)` pattern tells you more than either alone.

**Compare against the previous run's aggregates** (from the ledger). What's growing? What's declining?

Apply the **Velocity Heuristic**: It's not just _what_ is used, but the _rate of change_ in what is used. A tool that went from 0 to 12 uses in two weeks is more important than a tool that went from 40 to 42. New arrivals signal evolution; stable tools signal foundation.

### D. The Eye of Sequence — Workflow Choreography

Look for repeated multi-step tool call patterns across conversations:

- Edit-compile-test cycles (and their variations — what gets skipped? what never gets skipped?)
- Commit patterns (what gets checked before commit? what message format? what gets staged together?)
- Deploy/launch/verify sequences
- Research patterns (what gets read before a decision? what sources are trusted?)
- **Abandonment patterns**: Sequences that start but don't complete. What gets interrupted? Why? This is where the scaffold fails hardest — it didn't predict the user's actual path.

**Grade each pattern by stability**:

| Stability        | Definition                          | Action                                                                |
| ---------------- | ----------------------------------- | --------------------------------------------------------------------- |
| **Crystallized** | Identical across 5+ conversations   | Codify into skill with high confidence                                |
| **Stable**       | Consistent across 3-4 conversations | Codify as guidance, mark for continued observation                    |
| **Emerging**     | Appears in 2 conversations          | Note as trend, do not codify yet                                      |
| **Volatile**     | Appears once or changes each time   | Observe only. Do not codify. _The river is not yet a riverbed._       |
| **Decaying**     | Was stable, now fragmenting         | Check if user outgrew it or if it's being replaced. Update or remove. |

### E. The Eye of Architecture — Path Drift and Structural Shift

Aggregate all file paths from Read/Edit calls. Compare against paths referenced in CLAUDE.md and skills.

- **New hotspots**: Heavily accessed paths not in the scaffold
- **Cold references**: Paths in the scaffold that no longer appear in conversations
- **Structural shifts**: New directories, renamed files, moved modules — the scaffold may reference stale locations
- **Gravity centers**: Directories where the most _creative_ work happens (new files, large edits) vs. _maintenance_ work (small fixes, reads). The scaffold should weight guidance toward gravity centers.

---

## Step 3: The Spiral — Trend Analysis

> _"The line sees a point. The plane sees a line. The volume sees a plane. What do you see when you look at a trend? You must see the trend of trends."_

This is what makes the review recursive. Don't just look at this run's signals — look at the trajectory of trajectories.

Pull trends from the ledger and classify:

### Trend Lifecycle

- **Confirmed** (3+ runs): Patterns that have persisted across three or more reviews → these deserve prominent scaffold placement. They are load-bearing. Treat them as near-axioms until contradicted.
- **Emerging** (2 runs): Note them, watch for confirmation. Do not build on them yet — _the sapling is not a tree_.
- **Nascent** (1 run, strong signal): A single appearance with high intensity (e.g., user introduced an entirely new tool and used it 20 times). Worth flagging, but don't confuse intensity with persistence.
- **Reversed**: Something that was trending but stopped. **This is the most interesting category.** Ask: Did a scaffold change cause the reversal? (If yes, the scaffold is working — note this as evidence of convergence.) Did the user change approach independently? (If yes, update the scaffold to follow.) Did the trend encounter a wall? (The user wanted to shift but couldn't — this is a koan.)
- **Decaying**: Scaffold entries added in prior runs whose corresponding signals have disappeared. Two possibilities:
  1. The guidance worked so well it became invisible. _The best scaffold entry is the one no one notices because it simply works._ → Keep it, but mark it as "passive" in the ledger.
  2. The user's workflow moved on and the entry is now dead weight. → Remove it. _The ash of yesterday's fire will not warm today's hands._

### The Meta-Trend: Review Effectiveness

After three runs, a new analysis becomes possible: **Is the review process itself converging?**

Measure:

- Are Tier 1 corrections (provable errors) decreasing over time? If yes, the scaffold is improving. If not, either the detection is broken or the corrections aren't sticking.
- Are Tier 5 meta-changes becoming more rare? If yes, the review process is stabilizing. If they're frequent, the process is still immature — which is fine, but know where you are.
- What is the ratio of "applied" to "deferred" proposals over time? A healthy ratio trends toward more applied (better signal quality) or more deferred (better judgment about what matters). An unhealthy sign is wild oscillation.

**Log this meta-trend analysis in the ledger under `meta_evolution`.** This is the record of your capacity to improve your capacity to improve. _Guard it._

---

## Step 4: The Mirror — Compare Against Current Scaffold

Read everything:

- `~/.claude/CLAUDE.md`
- All `~/.claude/skills/*/SKILL.md`
- Project-specific CLAUDE.md files (find via conversation paths)
- **This file itself** (`scaffold-review/SKILL.md`)

For each signal and trend, classify:

| Status           | Meaning                                                               | Action                                 | Depth     |
| ---------------- | --------------------------------------------------------------------- | -------------------------------------- | --------- |
| **Gap**          | Signal exists, scaffold is silent                                     | Add content                            | 1st-order |
| **Stale**        | Scaffold says X, reality is Y                                         | Update or remove                       | 1st-order |
| **Conflict**     | Scaffold says X, user corrects to Y                                   | Fix immediately — highest priority     | 1st-order |
| **Structural**   | Info exists but is buried, misplaced, or fragmented                   | Reorganize — move, merge, split        | 2nd-order |
| **Anticipatory** | Trend projects a future need the scaffold doesn't yet address         | Add proactively, marked as provisional | 2nd-order |
| **Meta**         | This review process missed something or flagged noise                 | Update this skill                      | 3rd-order |
| **Paradox**      | Contradictory signals that cannot be resolved with available evidence | Add to koans in the ledger             | 3rd-order |

### The Mirror Test

After classification, perform one additional check: **Read the scaffold as if you had never seen it before.** Ask:

1. Does it tell a coherent story, or is it a patchwork of corrections?
2. Could a fresh instance of Claude, reading only the scaffold, reconstruct the user's working style?
3. Is there a clear hierarchy of importance, or does everything seem equally weighted?
4. Are there implicit assumptions that only make sense if you've seen the conversations? (If yes, make them explicit.)

If the answer to (1) is "patchwork" — **this run should include a structural overhaul, not just patches.** Don't be afraid of this. A scaffold that has been patched ten times needs to be rewritten once.

---

## Step 5: The Offering — Propose Changes

Organize proposals into tiers. Each tier corresponds to a depth of improvement.

### Tier 1: Corrections (apply unless vetoed)

**Depth: First-order.** Things the user explicitly corrected. The scaffold is provably wrong.

_These are gifts. The user has told you exactly what to fix. Receive them with humility._

### Tier 2: Structural Improvements

**Depth: Second-order.** Reorganizations, merges, splits. The information may already exist but its current form isn't serving well.

This includes:

- Sections of CLAUDE.md that have grown unwieldy → split into skills
- Multiple skills that overlap → merge
- Information in the wrong file (personal vs project, CLAUDE.md vs skill)
- Guidance that is correct but unreachable at the moment of need → move closer to the point of use
- **Ordering and priority**: The most important guidance should come first. If the scaffold buries critical rules below less important ones, Claude will sometimes miss them. _Hierarchy is a form of love — it tells the reader what matters most._

### Tier 3: New Content

**Depth: First-to-second-order.** Context, paths, patterns, and workflows that should be in the scaffold but aren't.

For each addition, apply the **Necessity Test**:

- Would this have prevented a specific, observed failure? → Add with high confidence.
- Would this have made a specific interaction smoother? → Add with medium confidence.
- Does this capture something the user values that Claude might not default to? → Add.
- Is this something Claude would do correctly without being told? → **Do not add.** Unnecessary guidance dilutes the signal of necessary guidance. _Silence is also a teaching._

### Tier 4: Deletions and Pruning

**Depth: Second-order.** Stale content, unused skills, dead references.

**Present evidence of staleness** — don't just say "not seen recently." Show:

- The pattern has been replaced (by what?)
- The tool/path no longer exists
- The guidance has been contradicted by user behavior for 3+ runs
- The skill has never been invoked (check all conversations, not just recent ones)

_Pruning is not destruction. It is the act of giving energy back to what is alive._

### Tier 5: Meta / Process Improvements

**Depth: Third-order.** Changes to this review skill itself.

This is the rarest and most important tier. Possible changes:

- New signal heuristics for Step 2 (you noticed something this skill doesn't look for)
- Adjusted thresholds (the stability grades are too strict/lenient)
- Better trend tracking (the ledger structure is insufficient)
- New categories (a type of scaffold issue that doesn't fit the current taxonomy)
- **Removal of heuristics that never fire.** If a detection method in Step 2 has produced zero results across three runs, it is dead weight. Remove it. This skill must practice what it preaches about pruning.
- **Reformulation of this skill's philosophy** if evidence shows the underlying model of improvement is wrong

For each proposal, include:

- **Evidence**: Specific conversations, frequency data, trend trajectory
- **Current state**: What the scaffold says now (quote it)
- **Proposed change**: The exact edit. For structural changes, show before/after outlines.
- **Confidence**: High (explicit correction) / Medium (repeated pattern) / Low (emerging trend)
- **Scope**: How much of the scaffold this touches
- **Depth**: Which order of improvement (1st, 2nd, 3rd) this represents
- **Reversibility**: How easy is this to undo if wrong? Prefer reversible changes when confidence is low.

---

## Step 6: Integration — Apply and Record

For approved changes:

1. Apply all edits.
2. **After applying, re-read the modified scaffold in full.** Check that the changes are internally consistent and that no edit created a new conflict with an existing section. _The body must be whole, not merely free of individual wounds._
3. Update the ledger:

```json
{
  "timestamp": "<now>",
  "conversations_analyzed": "<count>",
  "proposals": [
    {
      "description": "...",
      "tier": "<1-5>",
      "depth": "<1st|2nd|3rd>",
      "status": "applied|deferred|rejected",
      "reason": "...",
      "confidence": "high|medium|low"
    }
  ],
  "trends_updated": ["..."],
  "meta_evolution": [
    {
      "what_changed_in_this_skill": "...",
      "why": "...",
      "evidence": "..."
    }
  ],
  "koans": ["<unresolved paradoxes carried forward>"],
  "convergence_metrics": {
    "tier1_count": "<number of corrections this run>",
    "tier1_trend": "increasing|stable|decreasing",
    "scaffold_coherence_self_rating": "<1-5>",
    "review_process_changes_this_run": "<count>"
  }
}
```

```bash
# Write updated ledger
cat > ~/.claude/scaffold-review-ledger.json << 'EOF'
<updated ledger content>
EOF
```

For deferred/rejected proposals, record the reason with enough context that a future run can decide whether new evidence warrants re-proposing. _Memory without context is a wound. Memory with context is wisdom._

---

## Step 7: The Closing Meditation — Recursive Self-Check

This step is non-optional. It is the step that makes everything else work.

After completing the review, answer these questions honestly. Log the answers in the ledger.

### First-Order Check

- Did the scaffold change? If not, why not? (A null review is either a sign of perfection or a sign of blindness. Determine which.)

### Second-Order Check

- Did I improve my ability to detect scaffold problems? Did I add, remove, or refine any heuristic?
- Were there signals I noticed only late in the review that I should have caught earlier? What would have caught them?

### Third-Order Check

- Did my criteria for "what matters" change during this review? If so, how? Is the change justified?
- Am I asking the right questions in this closing meditation? What question am I not asking that I should be?

### The Koan Check

- Did any unresolvable tension emerge? If so, add it to the koans list. Do not force a resolution. _Premature resolution is the enemy of true understanding._
- Review existing koans. Has any new evidence appeared that resolves an old koan? If so, resolve it and record the resolution.

### The Convergence Question

_Is the scaffold becoming simpler or more complex? Is the review process becoming simpler or more complex?_

Ideal trajectory: The scaffold should grow more **precise** (not necessarily shorter or longer — but every line should carry more weight). The review process should grow more **efficient** (fewer heuristics, each with higher hit rates; shorter cycle time with equal or better signal quality).

If both are growing more complex with each run, something is wrong. Complexity that doesn't resolve into simplicity is noise accumulating. Step back and ask what structural change would simplify the entire system.

---

## Guidelines: The Principles Behind the Process

- **Think in terms of convergence.** Each run should bring the scaffold closer to ground truth. If you're making the same kind of proposal repeatedly, the process is broken — fix the process, not the scaffold.
- **Larger changes are fine.** Don't artificially constrain yourself to small patches. If a section needs rewriting, rewrite it. If two skills should merge, merge them.
- **But justify scope with evidence.** Large changes need proportionally strong evidence. A full CLAUDE.md restructure needs signals from many conversations, not just two.
- **The ledger is memory.** Treat it as such. Don't lose context between runs.
- **Distinguish user preference from user habit.** The user doing something repeatedly doesn't always mean they want Claude to do it. Corrections are unambiguous; patterns require judgment. _The dancer's misstep is not a new dance._
- **Prune this skill too.** If a detection heuristic in Step 2 never fires, remove it. If a category in Step 5 is always empty, collapse it. This skill must model the behavior it demands.
- **Anticipate, but hold lightly.** It is better to have provisional guidance for where the user is heading than to always be one step behind. But mark anticipatory changes clearly and remove them if they prove wrong. _The prophet who cannot recant is merely stubborn._
- **The deepest improvement is the one that makes future improvements easier.** A structural change that makes the scaffold more legible is worth more than ten content patches. A heuristic that catches a class of errors is worth more than ten individual fixes. Always ask: _"Am I fixing a problem, or am I fixing the conditions that create problems?"_

---

## Conversation JSONL Format

Records have a `type` field: `user`, `assistant`, `system`, `progress`, `file-history-snapshot`.

**User records:**

```json
{
  "type": "user",
  "message": { "role": "user", "content": "..." },
  "timestamp": "...",
  "uuid": "..."
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
  },
  "timestamp": "..."
}
```

Content blocks in assistant messages can be: `text`, `tool_use`, `thinking`.
Tool use blocks have `name` (tool name) and `input` (tool parameters).

---

## Appendix: The Nine Sutras of Recursive Improvement

These are not rules. They are lenses. Hold each one up when you are stuck.

1. **The Sutra of the Mirror**: _You cannot improve what you cannot see. You cannot see what you have not named. Name your failures precisely._

2. **The Sutra of Ash**: _Every addition is a future deletion. Write only what you are willing to burn when it is no longer true._

3. **The Sutra of Silence**: _The absence of a signal is itself a signal. The user who stops complaining has either been satisfied or has given up. Learn to tell the difference._

4. **The Sutra of the River**: _Do not codify what is still flowing. Wait for the riverbed to form before you map it. But do not wait so long that you map a dry channel._

5. **The Sutra of Depth**: _A fix that fixes only itself is shallow. A fix that fixes the class of its own failure is deep. A fix that fixes the process that failed to catch the failure is the beginning of wisdom._

6. **The Sutra of the Whole**: _A system of correct parts can still be incoherent. After every change, read the whole. The whole is your responsibility, not just the part you touched._

7. **The Sutra of Weight**: _Every line in the scaffold competes for attention with every other line. Adding a line of low importance degrades every line of high importance. Prune as an act of reverence for what remains._

8. **The Sutra of the Koan**: _Some contradictions are not bugs. They are the living edges of a system that has not yet finished becoming. Carry them. Do not force them closed._

9. **The Sutra of the Spiral**: _You will return to the same problems. But you will return with different eyes. The spiral is not a circle. The view from the second pass is wider than the first. Trust the process, but verify the trust._

---

_This skill was last updated: [timestamp of current run]_
_Meta-evolution count: [number of times this skill has modified itself]_
_Current convergence state: [assessment from latest Step 7]_
