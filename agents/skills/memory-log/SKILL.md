---
name: memory-log
description: Log a milestone, finding, or result to ~/memory/. Invoke explicitly with /memory-log or proactively when a session produces something worth remembering.
user-invocable: true
---

# Memory Log

Record meaningful session output to `~/memory/<project>/` so future sessions have context.

**When to invoke proactively** (without user asking):
- Benchmark results were collected
- A design decision was made or changed
- A bug was root-caused
- An implementation milestone was reached (feature working, PR merged, test passing)
- A significant finding or insight emerged

**When NOT to invoke**:
- Routine code edits, typo fixes, small refactors
- Work that's already captured in git commits
- Speculative ideas that weren't validated

---

## Step 1: Identify Project

Determine the active project:

1. Check cwd and git remote against `~/memory/INDEX.md` registry
2. If no match, check if the user's prompt or recent work maps to a known project
3. If still no match, ask the user

Read the project's `~/memory/<project>/INDEX.md` to understand the existing structure.

---

## Step 2: Classify the Entry

Determine what type of entry this is:

| Type | Where to write | Example |
|------|---------------|---------|
| **Chronology / progress** | Append to the project's existing worklog | Feature done, endpoint working, integration validated |
| **Project state update** | Update `INDEX.md` when the conclusion should be easy to recover later | Root cause, benchmark conclusion, validated constraint |
| **Evidence bundle** | `experiments/<date>-<topic>/` when multiple artifacts need to stay together | Configs, results, plots, repro scripts |
| **Bug/investigation note** | Existing worklog or focused project doc | Reproduction steps, partial understanding, debugging thread |

---

## Step 3: Write the Entry

Format rules:
- **Timestamp**: use `## YYYY-MM-DD: <short title>` as the section header
- **Keep it dense**: bullet points, numbers, code snippets. No narrative padding.
- **Include evidence**: actual numbers, command output, log snippets. Not "it was faster."
- **Link context**: reference file paths, git commits, or other memory docs where relevant.

Prefer these document roles:
- `INDEX.md`: live brief, current state, durable conclusions, and high-signal pointers
- `worklogs/` or existing worklog files: chronological evidence log
- `worklog-<topic>.md`: topic-specific chronology only when the project already uses that pattern
- `experiments/`: bundled evidence and reproducibility artifacts
- `maintenance/log.md`: repo operational changes, not project technical memory

If appending to an existing worklog, add the new section at the top. Worklogs are append-only and newest-first.

When a conclusion should be easy to recover later, update the project `INDEX.md` with a concise summary and links back to the supporting worklog or experiment.

Use this promotion test before expanding beyond the worklog:

- will a future session likely need this conclusion again?
- would rereading chronology be a bad way to recover it?
- does it influence future decisions or interpretation?

If the answer is mostly no, keep it in the worklog.

---

## Step 4: Update Frontmatter

Update the project INDEX.md frontmatter:

```yaml
last-updated: <today's date>
```

If the project status changed (e.g., work completed), update `status` too.

Also update `~/memory/INDEX.md` registry table to keep the "Last Active" column current.

If the project `INDEX.md` uses `worklog_refs` or `experiment_refs`, keep those pointers accurate when you materially change the project state.

---

## Step 5: Commit

```bash
cd ~/memory && git add -A && git commit -m "<project>: <short description>"
```

Do not push.

---

## New Project Bootstrap

If logging to a project that doesn't exist yet in `~/memory/`:

1. Create `~/memory/<project-name>/INDEX.md` with frontmatter:
   ```yaml
   ---
   type: project
   project: <project-name>
   repo: <path or null>
   branch: <branch or null>
   status: active
   last-updated: <today>
   tags: [relevant, tags]
   ---
   ```
2. Add a brief description and any initial content
3. Create `worklogs/` and start the first canonical worklog if the repo contract expects it
4. Add a row to `~/memory/INDEX.md` registry table
5. Commit as above
