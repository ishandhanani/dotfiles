---
name: memory-log
description: Record significant results and decisions in ~/memory for future sessions.
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
| **Implementation progress** | New entry file in `worklogs/` | Feature done, endpoint working, integration validated |
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

Write each chronological entry as its own file, `<project>/worklogs/YYYY-MM-DD-<slug>.md`, starting with the `## YYYY-MM-DD: <title>` header. Do not append to a long running worklog file; the nightly dream splits those, and one entry per file lets `INDEX.md` link the exact evidence. Keep an entry under about 15 KB where you can; put bulky raw output in an `experiments/` or `benchmarks/results/` folder and link it.

For durable conclusions that are not chronological, use `findings/<slug>.md`.

---

## Step 4: Update INDEX.md

The project `INDEX.md` is what the next session reads first, so it must be accurate and small (about 4 KB).

- Update its `## Current state` section: 3-6 bullets on what is true now (status, open PRs and branches with heads, worktree paths, next step). Replace bullets your entry supersedes instead of adding beside them.
- End each bullet with the date it was true and a link to its source entry, e.g. `(as of 2026-11-02, [worklog](worklogs/2026-11-02-candidate-rows.md))`.
- Write PR refs fully qualified (`ai-dynamo/dynamo#17465`), and check a PR's state with `gh pr view` before you record it.
- Do not add dated history sections to `INDEX.md`; that history goes in the worklog entry.

Then update the frontmatter:

```yaml
last-updated: <today's date>
```

If the project status changed (e.g., work completed), update `status` too.

Also update `~/memory/INDEX.md` registry table to keep the "Last Active" column current.

---

## Step 5: Commit

Inspect `git status --short` and the staged diff first. Stage only this task's exact note, artifact, and index paths with `git add -- <paths>`. Commit only those paths; if unrelated changes are already staged, use `git commit --only -- <paths>` so they remain outside this commit and stay staged. Review the resulting commit before pushing. Do not stage an entire project directory when it contains concurrent work.

```bash
git -C "$HOME/memory" add -- <task-note> <changed-index>
git -C "$HOME/memory" commit --only -m "<project>: <short description>" -- <task-note> <changed-index>
git -C "$HOME/memory" push
```

Push every memory commit. Incremental memory pushes are encouraged.

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
2. Add a one-paragraph description and a `## Current state` section with dated, linked bullets as in Step 4
3. Add a row to `~/memory/INDEX.md` registry table
4. Commit as above
