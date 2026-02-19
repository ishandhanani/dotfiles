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
| **Benchmark result** | `benchmarks/results/<date>_<description>/` | New perf numbers, comparison data |
| **Implementation progress** | Append to existing worklog in project folder | Feature done, endpoint working, integration validated |
| **Design decision** | Specs folder or relevant doc | Changed approach, chose between alternatives |
| **Bug/investigation** | New or existing doc in project folder | Root cause found, reproduction steps, fix applied |
| **Finding/insight** | Relevant existing doc, or new file | Discovered behavior, measured something unexpected |

---

## Step 3: Write the Entry

Format rules:
- **Timestamp**: use `## YYYY-MM-DD: <short title>` as the section header
- **Keep it dense**: bullet points, numbers, code snippets. No narrative padding.
- **Include evidence**: actual numbers, command output, log snippets. Not "it was faster."
- **Link context**: reference file paths, git commits, or other memory docs where relevant.

If appending to an existing worklog, add the new section at the end.

If creating a new file, use a descriptive name: `FEATURE_NAME_WORKLOG.md`, `BUG_DESCRIPTION.md`, etc.

---

## Step 4: Update Frontmatter

Update the project INDEX.md frontmatter:

```yaml
last-updated: <today's date>
```

If the project status changed (e.g., work completed), update `status` too.

Also update `~/memory/INDEX.md` registry table to keep the "Last Active" column current.

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
   project: <project-name>
   repo: <path or null>
   branch: <branch or null>
   status: active
   last-updated: <today>
   tags: [relevant, tags]
   ---
   ```
2. Add a brief description and any initial content
3. Add a row to `~/memory/INDEX.md` registry table
4. Commit as above
