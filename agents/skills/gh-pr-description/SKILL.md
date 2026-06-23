---
name: gh-pr-description
description: Create or update GitHub pull request descriptions without deleting existing content or adding long narrative slop. Use when the user asks to write, refresh, clean up, standardize, or update a PR body/description for a current branch or GitHub PR.
---

# GH PR Description

Use this skill to keep PR descriptions concise and stable. Fetch the existing body first, update only the managed description block, and preserve all other content verbatim.

## Workflow

1. Resolve the PR.
   - Use a provided PR URL or `OWNER/REPO#N`.
   - Otherwise use the current branch: `gh pr view --json number,url,title,body,baseRefName,headRefName`.
2. Gather concise evidence.
   - Read the existing PR body.
   - Inspect changed files and commits with the smallest useful commands, usually `gh pr diff --name-only`, `git diff --stat`, and recent commit subjects.
   - Pull linked issue IDs from branch name, PR title/body, commit messages, or user context.
3. Compose the managed block.
   - Keep intro to exactly 2 sentences: what changed and why it matters.
   - Keep implementation to 3-6 bullets.
   - Keep walkthrough inside a markdown `<details>` block; choose the clearest format under [Walkthrough Format](#walkthrough-format).
   - Include validation, even if it is `Not run (reason)`.
   - If associated with a Linear ticket, include `CLOSES: <TICKET-ID>`; do not add the full Linear URL.
   - Add a benchmark section at the bottom only when benchmark results were actually collected.
4. Update the body.
   - If the body already has the managed markers, replace only that block.
   - If no managed block exists, put the managed block at the top and leave the old body below it.
   - Write with `gh pr edit --body-file <file>` after composing from the fetched existing body.
5. Report what changed and the PR URL.

No separate approval is required when the user asks to update the PR description. If the user asks for a draft only, do not write.

## Managed Block

Use exactly these hidden markers:

```md
<!-- codex-pr-description:start -->
Two-sentence intro. The second sentence should explain why the change matters.

CLOSES: DYN-123

### How This Was Implemented
- Short implementation bullet.
- Another bullet only if it adds signal.

<details>
<summary>Walkthrough</summary>

- Concise walkthrough content: file/function bullets, or one Mermaid diagram when it materially clarifies the change.

</details>

### Validation
- `command` or `Not run (reason)`.

### Benchmark Results
- Only include this section if benchmarks were run.
- Keep to the headline numbers and link artifacts/logs instead of pasting raw output.
<!-- codex-pr-description:end -->
```

## Walkthrough Format

Choose the smallest format that makes the implementation easier to understand:

- Use 1-12 file/function bullets for simple or independent edits.
- Use one compact Mermaid flowchart when the change connects three or more components or alters ownership/data flow.
- Use one compact Mermaid sequence diagram when request, event, or lifecycle ordering is the important part.
- Do not add a diagram merely because the PR changes multiple files. Keep labels short and omit implementation detail already covered above.

## Anti-Slop Rules

- Do not delete content outside the managed block.
- Do not paste long logs, benchmark dumps, or generated artifacts into the body; link or summarize them.
- Do not list every changed file; group boring mechanical changes.
- Do not claim validation that was not run.
- Do not add `Benchmark Results` without real benchmark data.
- Do not add speculative follow-up work.
- Do not repeat the same issue link in multiple sections.
- Do not use more than 6 implementation bullets, 12 walkthrough bullets, or one walkthrough diagram.

## Existing Body Safety

- Preserve unknown sections verbatim.
- Preserve checklists, reviewer instructions, release notes, and benchmark tables unless the user explicitly asks to rewrite them.
- If the existing body is empty, write only the managed block.
- If the existing body has a previous non-managed description, keep it below the managed block until the user asks to remove it.

## Fallback

If `gh` cannot resolve the PR, ask for a PR URL or `OWNER/REPO#N`.
If `gh auth status` fails, ask the user to run `gh auth login`.
