# Period evidence discovery

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
gh search prs --author ishandhanani --created "$FROM..$TO" --limit 1000 \
  --json number,title,repository,state,createdAt,closedAt,updatedAt,url \
  --jq '.[] | "\(.repository.nameWithOwner)#\(.number) [\(.state)] \(.title)"' | sort -u
gh search prs --author ishandhanani --updated "$FROM..$TO" --limit 1000 \
  --json number,title,repository,state,createdAt,closedAt,updatedAt,url \
  --jq '.[] | "\(.repository.nameWithOwner)#\(.number) [\(.state)] \(.title)"' | sort -u
# Reviewed (run only when the user asks for the optional detailed appendix):
gh search prs --reviewed-by ishandhanani --updated "$FROM..$TO" --limit 1000 \
  --json number,title,repository,state,createdAt,closedAt,updatedAt,url \
  --jq '.[] | "\(.repository.nameWithOwner)#\(.number) [\(.state)] \(.title)"' | sort -u
```

This auto-discovers repos memory won't name (in past runs: brev-cli, Aphoh/codex, warnold-tachometer, fork PRs). Per-PR detail when a bullet needs it:

```bash
gh pr view <num> -R <owner/repo> --json number,title,body,state,mergedAt,closedAt,author,reviews,comments \
  --jq '{num:.number,title:.title,state:.state,merged:.mergedAt,author:.author.login,
         nComments:(.comments|length),nReviews:(.reviews|length),body:.body}'
```

For a flagship "after N comments" line, also count review comments: `gh api repos/<owner>/<repo>/pulls/<num>/comments --jq 'length'` and add `nReviews`. Fork/private PRs may 404 — note and skip.

Before clustering, collect the canonical public PRs/issues/RFCs named by each active memory project. Do not limit candidates to PRs returned by the authored sweep: the best framing artifact may be a collaborator-owned RFC or a public follow-up linked only from memory.
