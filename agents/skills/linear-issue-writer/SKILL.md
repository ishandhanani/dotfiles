---
name: linear-issue-writer
description: Structure and draft Linear issue bodies, updates, and comments with strict anti-slop rules. Use when the user wants to write a Linear issue/update/comment or decide the shape of one; do not use for general Linear lookup, status checks, project browsing, or routine reads.
---

# Linear Issue Writer

Use this skill to avoid issue sprawl and bloated ticket bodies when writing Linear content. It does not replace `linear:linear` for ordinary Linear reads, lookup, status checks, or project management.

Default to one issue, draft first, and write to Linear only after explicit user approval.

## Workflow

1. Gather context.
   - Read the user request and any linked issue, PR, doc, memory note, or code reference.
   - If Linear tools are available, search/list nearby existing issues before proposing a new one.
   - If the target team/project/status is unclear, ask only for the missing field needed to write the issue.
2. Run the collapse pass.
   - Decide: `create new`, `update existing`, `comment on existing`, or `do nothing`.
   - Prefer `update existing` when the work shares the same deliverable, owner, validation path, or PR.
   - Create separate issues only for separate owners, separate repos/PRs, separate validation paths, or independently shippable deliverables.
3. Draft the issue or update.
   - Show the collapse decision and the draft body.
   - Keep one issue by default; use checkboxes inside `Done When` for subwork.
4. Ask for approval.
   - Do not call Linear create/update/comment tools until the user approves the draft.
   - After approval, create/update/comment exactly what was approved.
5. Report the result.
   - Return the issue key/link, what changed, and any fields left unset.

## Issue Body

Use this structure unless the user asks for a different template:

```md
## Goal
One sentence: what outcome this issue should produce.

## Context
- 2-4 bullets max.
- Link the existing issue/PR/doc/memory note instead of copying long background.

## Scope
- What will change.

## Non-goals
- What this issue will not do.

## Done When
- [ ] Observable completion criterion.
- [ ] Another criterion only if needed.

## Validation
- Smallest check, test, benchmark, log, or review evidence needed.
```

## Anti-Slop Rules

- Title names an action or result, not a theme.
- No speculative follow-up work.
- No duplicated context from linked artifacts.
- No essay paragraphs; bullets should be short.
- No “investigate everything” issue unless the output artifact is named.
- No issue split just because there are multiple steps.
- No Linear write without saying whether it is create, update, or comment.

## Collapse Output

Before drafting, show this tiny decision block:

```md
Decision: create new | update existing | comment on existing | do nothing
Target: <new issue or existing issue key>
Why: <one sentence>
Split avoided: <what would have become extra issues, if any>
```

## Linear Writes

- For `create new`, create one issue with the approved title/body/team/project/status/labels.
- For `update existing`, update only the approved fields; prefer appending a concise comment when changing the body would obscure history.
- For `comment on existing`, write a status or scope comment using the approved draft.
- If approval changes the scope, revise the draft and ask again.

## Fallback

If Linear tools are unavailable, produce the approved draft only and say that Linear write tools are not connected.
