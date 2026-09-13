---
name: linear-issue-writer
description: Create, update, or draft concise Linear issues and requested comments. Do not use for routine reads.
---

# Linear Issue Writer

Use this skill to avoid issue sprawl and bloated ticket bodies when writing Linear content. Ordinary reads and lookups use the available Linear tools directly.

Default to one issue. A request to create or update an issue authorizes that write within the requested scope. A draft or review request produces a draft. Posting a comment requires an explicit request to communicate on the issue. Skill selection alone grants no write authorization.

## Workflow

1. Gather context.
   - Read the user request and the linked evidence needed for its scope.
   - If Linear tools are available, search/list nearby existing issues before proposing a new one.
   - If the target team/project/status is unclear, ask only for the missing field needed to write the issue.
2. Run the collapse pass.
   - Decide: `create new`, `update existing`, `comment on existing`, or `do nothing`.
   - Prefer `update existing` when the work shares the same deliverable, owner, validation path, or PR.
   - Create separate issues only for separate owners, separate repos/PRs, separate validation paths, or independently shippable deliverables.
3. Draft the issue or update.
   - Show the collapse decision and the draft body.
   - Keep one issue by default; use checkboxes inside `Done When` for subwork.
4. Complete the requested action.
   - For an authorized write, create or update the requested content and read back the result.
   - For a draft-only request, return the draft without writing.
   - Ask only for a missing required field or an unresolved scope decision. Reuse authorization already given.
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

- For `create new`, create one issue with the requested title/body and resolved team/project/status/labels.
- For `update existing`, update only the requested fields and preserve useful history. Do not substitute a posted comment for a body edit without authorization to communicate.
- For `comment on existing`, post the requested status or scope comment within its authorized content.
- If the user changes the scope, incorporate it within the new authorization. Ask only if a material decision remains unresolved.

## Fallback

If Linear tools are unavailable, produce the complete local draft and report that the requested external write remains blocked by the missing connection.
