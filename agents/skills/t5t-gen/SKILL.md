---
name: t5t-gen
description: Create an evidence-backed engineering status update from ~/memory and GitHub activity.
---

# T5T Generator

Produce a status update in Ishan's voice for a date range, grounded in two sources:

- **`~/memory` (work-vault)** — the PRIMARY source. Per-project worklogs carry the narrative, hard numbers (throughput/latency/cache-hit/memory deltas), design decisions, collaborators, negative results, and project status. This is what makes the update read like a human wrote it, not a changelog.
- **`gh` (GitHub)** — the GROUNDING/confirmation layer. PR state (merged / open-in-review / closed-superseded), merge dates, review/comment counts ("after 204 interactions…"), and any numbers in PR bodies.

**Principle: memory tells the story, gh proves it shipped.** Neither alone is enough. Memory without gh misses merge state and review-marathon counts; gh without memory misses entire workstreams (uncommitted POCs, design pivots, benchmark results that never became a PR) and all the *why*.

## Inputs

1. **Date range** (`FROM`..`TO`, inclusive). If the user gives a single anchor ("last month", "since GTC"), resolve to absolute dates. Default if unspecified: **last 1 month** ending today.
2. **Optional**: specific repos to focus/exclude; PTO/travel/cross-team context to fold into a Misc section; whether to keep `(repo#num)` citations (default: keep for drafting, the user strips them for the final paste); whether to include a full reviewed-PR appendix (default: no).
3. **Optional running T5T doc**: if the user supplies one, read the prior tabs before drafting. An unambiguous empty final-tab title such as `May18 - June 23` can establish the date range without another question.

Resolve identity once: `gh api user --jq .login` (expect `ishandhanani`). Memory lives at `$HOME/memory` (registry: `$HOME/memory/INDEX.md`; one folder per project, each with an `INDEX.md` whose frontmatter has `status` + `last-updated`).

## Evidence discovery

Read [discovery.md](references/discovery.md) for the date-scoped memory and GitHub sweep.

## Step 3 — Fan out subagents over the period's active workstreams

This is the core mechanism. Group the active memory projects (from Step 1) into **3–5 clusters** of related work, and spawn one `general-purpose` subagent per cluster. Each subagent:

- Reads the `INDEX.md` (+ obvious summary files) of its assigned memory projects — for what the work was, why it mattered, collaborators, and status.
- Pulls `gh pr view` detail for the PRs those projects map to — mainly for merge state.
- Returns tight first-person bullets describing **the work** (what was built/fixed/driven and why), each tagged `[shipped]/[in-review]/[POC]/[blocked]` and cited with markdown PR hyperlinks (see Citations below) plus an internal `mem: <project>` tag. Numbers are optional — at most one per bullet, only when the number IS the point.

Give each subagent (a) its project list, (b) the gh PR list from Step 2 relevant to it, and (c) the voice guide below. Tell it to focus on what's substantive and skip routine edits. Run all subagents in ONE message so they execute concurrently. Past effective clustering (adapt per period — clusters are emergent, not fixed):
`Dynamo+Agents` · `Dynamo+SGLang` · `Distributed/Shared-KV routing` · `Dynamo+Frontend/crates` · `Simulation/Infra/Misc`.

If memory surfaced a big workstream that gh under-covered (uncommitted POCs, design pivots, benchmark-only work), tell that cluster's agent explicitly to prioritize it — these are the highest-value, easiest-to-miss items.

## Step 4 — Produce the mega dump before selecting

Take the subagents' bullets and GitHub sweep, then write a **Mega dump** before selecting the final update:

- Include every substantive in-window memory workstream and every substantive authored or reviewed GitHub PR discovered in Step 2. Group related items under inferred themes, but do not drop a whole theme because it will not fit the recommended update.
- Give each item a short first-person bullet, status tag, PR/issue links, and `mem: <project>` provenance. Combine only genuine duplicates; a merged upstream result and its related draft/POC may be one item when they are the same outcome.
- Keep routine one-line maintenance in a compact long-tail bullet, but do not hide shipped SGLang, Dynamo, review, benchmark, or infrastructure work merely because another theme is more narrative-friendly.
- Include a final `GitHub sweep not otherwise expanded` section for in-window PRs that were intentionally summarized, with a one-line reason for summarizing them.
- Add a mandatory `Complete authored GitHub inventory` appendix. Deduplicate the union of authored-created and authored-updated PRs by canonical repository and number. Put every authored PR in current-state order: **Merged PRs by repository**, then **Open PRs by repository**, then **Closed without merge by repository**. Each row has repository, number, current state, title, direct GitHub link, and created/updated dates. Include every authored issue updated in the window after these PR lists.
- Add the full `reviewed-by` PR list only when the user explicitly asks for reviewed PRs. Place this optional appendix after the complete authored inventory. Label it as a changed-in-window activity set, not a review-count metric.
- Save it to `/tmp/t5t-mega-<FROM>_<TO>.md`. The mega dump is the audit surface; do not optimize it for brevity.

## Step 5 — Recommend a T5T from the mega dump

Only after the mega dump is complete, make a separately labeled recommendation:

- Select the top-line story from the mega dump. Target **6–9 bullets total** across **2–3 themes**, unless the user explicitly requests a different count such as Top 5.
- Auto-cluster each run and dedupe only across genuinely overlapping outcomes. Prefer shipped user-visible contracts, canonical RFCs, meaningful empirical results, and clear architecture pivots.
- State the consequence plainly and keep metrics contextual. Append `[add color]` only for information the sources cannot support.
- Put a short `Why these made the cut` line after each recommended theme, and list the strongest omitted alternatives so the user can approve swaps without re-running discovery.
- Never present the recommendation as the complete period record. It is a proposal derived from the mega dump.

## Citations — markdown PR hyperlinks

Cite PRs as clickable markdown links, not bare `repo#num`. Display text is the short repo name + number; the URL is the full GitHub path:

- `ai-dynamo/dynamo#10172` → `[dynamo#10172](https://github.com/ai-dynamo/dynamo/pull/10172)`
- `sgl-project/sglang#27058` → `[sglang#27058](https://github.com/sgl-project/sglang/pull/27058)`

Use `/pull/<num>` for PRs and `/issues/<num>` for issues (GitHub redirects between them, so `/pull/` is a safe default if unsure). Group multiple links in one trailing parenthetical: `([dynamo#10172](…), [dynamo#10182](…))`. The `mem: <project>` tag (when present) is internal verification scaffolding — keep it during drafting; drop it for the final paste.

## Output format

```
## Mega dump: <Month D> – <Month D>

**<Theme 1>**
- [shipped] <first-person bullet about the work + why>. ([dynamo#NNNN](https://github.com/ai-dynamo/dynamo/pull/NNNN)) `mem: <project>`
- ...

**GitHub sweep not otherwise expanded**
- <PR or compact grouped list> — <why summarized>

## Recommended T5T: <Month D> – <Month D>

**<Theme 1>**
- <first-person bullet about the work + why>. ([dynamo#NNNN](https://github.com/ai-dynamo/dynamo/pull/NNNN))

Why these made the cut: <one short line>

Strongest alternatives: <one short linked line>

[**Misc**]
- <PTO / travel / forward-looking — from user context or [add color]>
```

Always write both artifacts: `/tmp/t5t-mega-<FROM>_<TO>.md` and `/tmp/t5t-<FROM>_<TO>.md`. Print the mega dump first, then the recommended T5T. The recommended file contains only the recommended T5T and its cut/alternative notes.

### Running-document mode

When the user supplies a running Google Doc, read [running-document.md](references/running-document.md) and the relevant document skill. Otherwise produce the local artifacts.

## Voice guide (match Ishan's T5T style)

- First person, conversational, status-update register: "Implemented…", "Worked with X to…", "Currently investigating…", "I am really hoping to merge this by this week…".
- Prefer short, direct architecture explanations over polished release-note prose. Sentence fragments and blunt consequences are fine when they match the live document.
- **Describe the work, not the metrics.** Each bullet is about WHAT you built/fixed/drove and WHY it matters. Numbers are optional garnish, not the subject — include at most one per bullet, and only when the number itself is the headline (e.g. a review that took 200+ comments). Never lead with a metric and never stack benchmark figures. Prefer "fixed a request-cancellation memory leak in the SGLang disagg workers" over "cut decode-pod VmHWM 40.1→52.0 GB over a 7h test".
- Name collaborators when memory/PR shows them ("Working with Pei on…", "addressed hzh0425's review", "with alex + rainj").
- State status plainly: "merged this week", "in final stages of review", "still very much POC", "closed in favor of X", "blocked on <upstream thing>".
- No emojis. No filler. Usually 2–3 bullets per theme and 6–9 bullets total.

## Boundaries

- **No source-system writes.** This skill never opens/edits/comments on PRs and never pushes to memory. It may write an explicitly supplied running T5T document when the user asks, using the Google Docs workflow above.
- **Never invent.** Every factual claim traces to a memory entry or a PR. If memory and a PR conflict, prefer memory for the *why/numbers* and gh for *merge state*, and note the conflict. Soft context the data can't support goes in an explicit `[add color]` slot — never fabricated.
- **Dates are the gate.** When unsure whether something belongs in the window, check memory's `last-updated` / commit dates and the PR's merge/close date. Out-of-window work is excluded even if notable.
