---
name: t5t-gen
description: Generate a bi-weekly/monthly engineering status update ("T5T") for a date range by mining the ~/memory work-vault (the narrative + numbers + why) and cross-referencing GitHub PR activity via gh (state, merge dates, comment counts) across all repos. Fans out subagents over the period's active workstreams, then auto-clusters the findings into themes. Use when asked to "write my T5T", "status update", "what did I do from X to Y", "biweekly update".
user-invocable: true
---

# T5T Generator

Produce a status update in Ishan's voice for a date range, grounded in two sources:

- **`~/memory` (work-vault)** — the PRIMARY source. Per-project worklogs carry the narrative, hard numbers (throughput/latency/cache-hit/memory deltas), design decisions, collaborators, negative results, and project status. This is what makes the update read like a human wrote it, not a changelog.
- **`gh` (GitHub)** — the GROUNDING/confirmation layer. PR state (merged / open-in-review / closed-superseded), merge dates, review/comment counts ("after 204 interactions…"), and any numbers in PR bodies.

**Principle: memory tells the story, gh proves it shipped.** Neither alone is enough. Memory without gh misses merge state and review-marathon counts; gh without memory misses entire workstreams (uncommitted POCs, design pivots, benchmark results that never became a PR) and all the *why*.

## Inputs — confirm before running

1. **Date range** (`FROM`..`TO`, inclusive). If the user gives a single anchor ("last month", "since GTC"), resolve to absolute dates. Default if unspecified: **last 1 month** ending today.
2. **Optional**: specific repos to focus/exclude; PTO/travel/cross-team context to fold into a Misc section; whether to keep `(repo#num)` citations (default: keep for drafting, the user strips them for the final paste).

Resolve identity once: `gh api user --jq .login` (expect `ishandhanani`). Memory lives at `$HOME/memory` (registry: `$HOME/memory/INDEX.md`; one folder per project, each with an `INDEX.md` whose frontmatter has `status` + `last-updated`).

## Step 1 — Memory-first discovery (what was actually worked on)

The memory registry + a window-scoped git log are the authoritative "what did I do" list. Run from `$HOME/memory`:

```bash
cd "$HOME/memory"
# Projects with commit activity in the window, ranked by effort (commit volume is a rough proxy):
git log --since=$FROM --until=$TO --name-only --pretty=format: | grep -v '^$' \
  | sed 's#/.*##' | sort | uniq -c | sort -rn
```

Then read `$HOME/memory/INDEX.md` (the registry table: status, repo, last-active, one-line description per project) and intersect:
- Include projects with **in-window commits** AND/OR a `last-updated` inside the window.
- The registry's one-line descriptions are nearly status-ready bullets — use them to scope, then read each active project's own `INDEX.md` for the numbers and PR mappings.

**Dates gate inclusion.** A project last active before `FROM` does NOT belong in the update even if its PRs are famous (e.g. the async-openai migration was March work — memory's dates correctly exclude it from a May–June report). Trust memory's dates over your sense of "recent".

Do NOT crawl per-commit logs of high-volume projects (some have 1000+ commits in a window) — read the curated `INDEX.md` / summary files instead.

## Step 2 — gh augmentation (confirm state, catch repos memory didn't name)

Memory is organized by project, not repo, and misses pure-review activity. Sweep GitHub across ALL repos for the window:

```bash
# Authored — created, and updated (catches ongoing/open work):
gh search prs --author ishandhanani --created "$FROM..$TO" --limit 100 \
  --json number,title,repository,state,createdAt,closedAt \
  --jq '.[] | "\(.repository.nameWithOwner)#\(.number) [\(.state)] \(.title)"' | sort -u
gh search prs --author ishandhanani --updated "$FROM..$TO" --limit 100 \
  --json number,title,repository,state \
  --jq '.[] | "\(.repository.nameWithOwner)#\(.number) [\(.state)] \(.title)"' | sort -u
# Reviewed (the "reviewed ~N PRs" talking points — strong signal, easy to forget):
gh search prs --reviewed-by ishandhanani --updated "$FROM..$TO" --limit 100 \
  --json number,title,repository,state \
  --jq '.[] | "\(.repository.nameWithOwner)#\(.number) [\(.state)] \(.title)"' | sort -u
```

This auto-discovers repos memory won't name (in past runs: brev-cli, Aphoh/codex, warnold-tachometer, fork PRs). Per-PR detail when a bullet needs it:

```bash
gh pr view <repo>#<num> --json number,title,body,state,mergedAt,closedAt,author,reviews,comments \
  --jq '{num:.number,title:.title,state:.state,merged:.mergedAt,author:.author.login,
         nComments:(.comments|length),nReviews:(.reviews|length),body:.body}'
```

For a flagship "after N comments" line, also count review comments: `gh api repos/<owner>/<repo>/pulls/<num>/comments --jq 'length'` and add `nReviews`. Fork/private PRs may 404 — note and skip.

## Step 3 — Fan out subagents over the period's active workstreams

This is the core mechanism. Group the active memory projects (from Step 1) into **3–5 clusters** of related work, and spawn one `general-purpose` subagent per cluster. Each subagent:

- Reads the `INDEX.md` (+ obvious summary files) of its assigned memory projects — for what the work was, why it mattered, collaborators, and status.
- Pulls `gh pr view` detail for the PRs those projects map to — mainly for merge state.
- Returns tight first-person bullets describing **the work** (what was built/fixed/driven and why), each tagged `[shipped]/[in-review]/[POC]/[blocked]` and cited with markdown PR hyperlinks (see Citations below) plus an internal `mem: <project>` tag. Numbers are optional — at most one per bullet, only when the number IS the point.

Give each subagent (a) its project list, (b) the gh PR list from Step 2 relevant to it, and (c) the voice guide below. Tell it to focus on what's substantive and skip routine edits. Run all subagents in ONE message so they execute concurrently. Past effective clustering (adapt per period — clusters are emergent, not fixed):
`Dynamo+Agents` · `Dynamo+SGLang` · `Distributed/Shared-KV routing` · `Dynamo+Frontend/crates` · `Simulation/Infra/Misc`.

If memory surfaced a big workstream that gh under-covered (uncommitted POCs, design pivots, benchmark-only work), tell that cluster's agent explicitly to prioritize it — these are the highest-value, easiest-to-miss items.

## Step 4 — Synthesize: auto-cluster, dedupe, voice

Take the subagents' bullets and produce the final update yourself (or via one reducer agent):

- **Auto-cluster each run.** Infer this period's themes from the actual work; do not force last period's headers. A workstream that dominated one period (ModelExpress, L3 routing) may be absent the next. Order themes by significance/effort.
- **Dedupe across themes.** The same PR can surface in two clusters (e.g. a router PR is both "Agents" and "Routing"). Keep it in the single best-fitting theme; don't repeat it.
- **Summarize the long tail.** Many small sync/CI/review PRs → one bullet ("reviewed ~7 KV-router PRs covering …"; "stood up frontend-crates with hourly sync-check"). Lead with substantive work.
- **Append a `[add color]` line** for what the data can't infer: PTO/travel, cross-team rumors, forward-looking framing, named-but-not-in-PR collaborators. Fill from the user's Step-0 context if provided, else leave the marker.

## Citations — markdown PR hyperlinks

Cite PRs as clickable markdown links, not bare `repo#num`. Display text is the short repo name + number; the URL is the full GitHub path:

- `ai-dynamo/dynamo#10172` → `[dynamo#10172](https://github.com/ai-dynamo/dynamo/pull/10172)`
- `sgl-project/sglang#27058` → `[sglang#27058](https://github.com/sgl-project/sglang/pull/27058)`

Use `/pull/<num>` for PRs and `/issues/<num>` for issues (GitHub redirects between them, so `/pull/` is a safe default if unsure). Group multiple links in one trailing parenthetical: `([dynamo#10172](…), [dynamo#10182](…))`. The `mem: <project>` tag (when present) is internal verification scaffolding — keep it during drafting; drop it for the final paste.

## Output format

```
## <Month D> – <Month D>   [(PTO / travel notes if any)]

**<Theme 1>**
- <first-person bullet about the work + why>. ([dynamo#NNNN](https://github.com/ai-dynamo/dynamo/pull/NNNN))
- ...

**<Theme 2>**
- ...

[**Misc**]
- <PTO / travel / forward-looking — from user context or [add color]>
```

**Always write the final update to a tmp markdown file** in addition to printing it in the chat, so the user has a file to copy from. Use `/tmp/t5t-<FROM>_<TO>.md` (e.g. `/tmp/t5t-2026-05-11_2026-06-11.md`). Write the exact same content shown in chat (with the markdown PR hyperlinks). Tell the user the path at the end.

## Voice guide (match Ishan's T5T style)

- First person, conversational, status-update register: "Implemented…", "Worked with X to…", "Currently investigating…", "I am really hoping to merge this by this week…".
- **Describe the work, not the metrics.** Each bullet is about WHAT you built/fixed/drove and WHY it matters. Numbers are optional garnish, not the subject — include at most one per bullet, and only when the number itself is the headline (e.g. a review that took 200+ comments). Never lead with a metric and never stack benchmark figures. Prefer "fixed a request-cancellation memory leak in the SGLang disagg workers" over "cut decode-pod VmHWM 40.1→52.0 GB over a 7h test".
- Name collaborators when memory/PR shows them ("Working with Pei on…", "addressed hzh0425's review", "with alex + rainj").
- State status plainly: "merged this week", "in final stages of review", "still very much POC", "closed in favor of X", "blocked on <upstream thing>".
- No emojis. No filler. 3–5 bullets per theme.

## Boundaries

- **Read-only.** This skill reads memory and GitHub; it never opens/edits/comments on PRs and never pushes to memory. Output is text for the user to paste/edit.
- **Never invent.** Every factual claim traces to a memory entry or a PR. If memory and a PR conflict, prefer memory for the *why/numbers* and gh for *merge state*, and note the conflict. Soft context the data can't support goes in an explicit `[add color]` slot — never fabricated.
- **Dates are the gate.** When unsure whether something belongs in the window, check memory's `last-updated` / commit dates and the PR's merge/close date. Out-of-window work is excluded even if notable.
