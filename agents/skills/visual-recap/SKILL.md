---
name: visual-recap
description: Create a self-contained local HTML walkthrough of a pull request, branch, commit, or diff. Use when the user asks for a visual recap, HTML report, implementation walkthrough, architecture explainer, or an HTML document showing how a code change works. Ground every claim in the actual diff, code, tests, benchmark artifacts, and review evidence. Do not trigger for an ordinary PR review unless the user also wants the visual HTML artifact.
---

# Visual Recap

Turn an existing code change into a local, dependency-free HTML document that lets a systems engineer understand the architecture, runtime flow, minimal integration seams, performance evidence, risks, and validation before reading the raw diff.

## Deliverable

- Write one self-contained `.html` file with inline CSS and, only when materially useful, inline JavaScript.
- Prefer `/ephemeral/<repo>-pr-<number>-visual-recap.html` for a PR and `/ephemeral/<repo>-<short-head>-visual-recap.html` otherwise. Fall back to `/tmp` when `/ephemeral` is unavailable. Honor an explicit output path.
- Keep the artifact outside the checkout by default so a recap does not dirty the worktree.
- Use native HTML/CSS, semantic elements, inline SVG, and `<details>` before adding a dependency or JavaScript. Do not use a CDN, hosted font, external image, build step, or framework.
- Return a clickable absolute path to the HTML. Do not publish, upload, commit, or attach it to the PR unless the user asks.

## Scope The Work Unit

1. Resolve the exact base and head. For a GitHub PR, capture repository, PR number, base SHA, head SHA, title, author, status, and canonical URL. Use immutable head-SHA permalinks for code references.
2. Recap the whole requested work unit, including follow-up fixes and tests on the current head. Do not silently narrow the report to the latest commit.
3. Separate work-unit changes from unrelated pre-existing dirty files. State a concise scope assumption only when the boundary cannot be proven.
4. Skip the full artifact for a tiny, obvious change unless the user explicitly asked for HTML; then produce a compact version instead of padding it.

## Research Before Authoring

Read the actual change and its surrounding flow end to end.

- Collect `git diff --stat`, `git diff --numstat`, `git diff --name-status`, the commit list, and the focused base-to-head diff.
- Read every load-bearing changed file and enough unchanged callers/callees to explain ownership boundaries and default behavior. Use `rg` to trace callers before describing a shared seam.
- Read PR description, review threads, checks, tests, and benchmark artifacts when available. Use the matching `~/memory/<project>/` evidence for prior baselines and experiment context.
- Capture exact configuration, hardware, workload, concurrency, measurement window, sample counts, failures, and caveats for benchmark claims.
- Classify claims as measured, observed in code, or inferred. Omit unsupported facts. Never turn a directional comparison into a causal A/B claim.
- Redact tokens, keys, internal credentials, private endpoints, and secret-like literals from prose and code excerpts.

Build a short inventory before writing: objective, changed subsystems, request/data lifecycle, state transitions, hot paths, default/off path, compatibility boundary, key files, tests, benchmark evidence, live-found regressions, review findings, and unresolved risks. Omit empty or irrelevant categories from the final document.

## Compose For Systems Work

Use the smallest set of sections that explains the change. The normal order is:

1. **Hero** — PR/branch identity, one-sentence thesis, head SHA, status badges, and 3-5 meaningful headline numbers.
2. **Architecture** — a flow diagram of real components and ownership boundaries. Distinguish existing components, new isolated logic, and integration seams.
3. **Runtime lifecycle** — trace one request, event, or data item through the system with numbered steps and exact `path:line` anchors.
4. **Algorithm or state machine** — show control order, state transitions, invariants, capacity equations, or scheduling decisions when they matter.
5. **Isolation and compatibility** — compare disabled/default behavior with opt-in behavior. State what deliberately did not change.
6. **Key decision or live-found bug** — explain the highest-value design tradeoff or regression with a before/after flow when evidence exists.
7. **Diff footprint** — group changed files by responsibility, show additions/deletions, and explain why each shared seam exists. Do not dump a raw file list.
8. **Evidence** — present validation and performance numbers with exact methodology. Put the primary metric table first and add at most one chart when it makes a comparison clearer.
9. **Review risks** — include only grounded findings, caveats, and optional reductions. Label severity and link to the relevant immutable lines. Do not manufacture findings to fill the section.
10. **Validation** — list commands/checks actually run and their outcomes.

Move performance evidence earlier when it is the reason the change exists. Move compatibility earlier for public API or wire-format changes. For documentation-only changes, keep the recap compact.

## Visual Language

Match the established systems-report style:

- Use a dark technical palette: `--bg: #071018`, `--panel: #0d1923`, `--panel-2: #122431`, `--line: #264150`, `--text: #e7f1f5`, `--muted: #95aab5`, `--cyan: #46d7d1`, `--blue: #6ca8ff`, `--amber: #f2bd62`, `--green: #77d49d`, `--red: #ff8d85`, and `--violet: #b89cff`.
- Use system sans and monospace font stacks, a centered content width near 1240px, a restrained sticky section nav, responsive grids, and print styles.
- Use cyan for the new mechanism, blue for existing components, amber for seams/caveats, green for validated or unchanged behavior, and red only for failures or blockers.
- Prefer boxes, arrows, timelines, state machines, queues, comparison panels, metric cards, compact tables, and horizontal bars. Use visuals to explain relationships, not decorate headings.
- Keep prose short and technical. Use exact names, configuration keys, units, denominators, and `file:line` references. Do not use emojis.
- Make the document accessible: semantic headings in order, sufficient contrast, visible focus states, table headers, descriptive link text, and text labels that do not rely on color alone.

## Evidence Rules

- Ground architecture nodes, fields, routes, state transitions, and file counts in changed code or stable surrounding code.
- Link code references to immutable GitHub blob URLs when possible; otherwise render exact local `path:line` text.
- Show benchmark methodology beside results. Include negative evidence such as timeouts, retries, forced resumes, errors, counter resets, verification disabled, or non-equivalent baselines.
- Prefer tables for several exact values. Add one simple chart only when it reveals a ranking, before/after delta, or trend more quickly than the table.
- Keep code excerpts focused and rare. Use them only when the literal condition or data shape is clearer than a diagram; never reproduce large diffs.
- Preserve uncertainty. Say `inferred`, `directional`, `not tested`, or `no causal claim` where appropriate.

## Quality Gate

Before handoff:

1. Confirm the title, PR metadata, SHAs, file counts, links, metrics, units, and validation outcomes against source evidence.
2. Confirm the default/off path and cleanup/error paths for opt-in systems changes.
3. Search the artifact for secrets and accidental local-only identifiers that should be redacted.
4. Confirm there are no remote assets or runtime dependencies. Ordinary GitHub and PR hyperlinks are allowed.
5. Serve the output locally and open it in a real browser. When browser tooling is available, use the `browser-snapshot` skill, capture the full page or representative sections, and visually inspect the image for overflow, overlap, unreadable text, broken anchors, and mobile-width failures. Fix issues before handoff.
6. Stop the temporary HTTP server and remove temporary screenshots unless the user asked to keep them.

## Avoid

- Hosted recap services, MDX block protocols, or a required connector.
- Generic boilerplate explaining what a recap is.
- Giant diff dumps, one card per file, decorative charts, fabricated architecture, or unverified benchmark conclusions.
- Repeating the PR description without tracing how the implementation works.
- Turning the recap into a replacement for a formal code review. Include existing review evidence, but use the appropriate review skill when the user asks for a review.
