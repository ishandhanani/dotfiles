---
name: gh-pr-description
description: Write or update a concise GitHub PR description without overwriting useful content.
---

# GH PR Description

Write or update the requested PR description from the current diff and validation evidence. A request to update the description authorizes that write; draft-only requests produce a local body. Fetch the existing body before any update.

Lead with the concrete problem and resulting behavior. Scale detail to complexity: a small change may need one or two sentences plus validation. For a multi-component implementation or an existing detailed walkthrough, read [walkthrough.md](references/walkthrough.md) and preserve its useful explanation while correcting stale claims.

## Body preservation

- Preserve unknown sections, checklists, reviewer instructions, release notes, and useful benchmark data unless the user asks to rewrite them.
- If managed markers exist, replace only `<!-- codex-pr-description:start -->` through `<!-- codex-pr-description:end -->`. If absent, add the managed description at the top and retain the old body below it; do not duplicate its content inside the new explanation.
- Include actual validation or a concise reason it was not run. Link the associated ticket once, following the repository convention.
- Keep `Before and After` opt-in: omit it unless already approved or explicitly requested. Update an existing approved section without another question. This preference need not block an otherwise complete description.
- Add benchmark sections only for collected data, with comparable units and methodology. Link large artifacts. A graph is optional when the table already suffices; publish to an external artifact service only when authorized.
- Do not claim unrun checks or add speculative follow-up scope. Use diagrams when component interactions need explanation, not a file inventory.

Write the complete composed body to a file and use `gh pr edit --body-file <file>`. Read back the body to verify content preservation and return the PR link. For new PRs, use the same composition rules with `gh pr create --draft --body-file <file>` when publication is requested.
