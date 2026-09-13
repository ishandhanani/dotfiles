# Large-period synthesis

## Step 3 — Fan out subagents over the period's active workstreams

For a large period with independent workstreams, group related projects and use a bounded subagent per cluster when delegation is permitted. Handle small periods locally; there is no required cluster count. Each subagent:

- Reads the `INDEX.md` (+ obvious summary files) of its assigned memory projects — for what the work was, why it mattered, collaborators, and status.
- Pulls `gh pr view` detail for the PRs those projects map to — mainly for merge state.
- Returns tight first-person bullets describing **the work** (what was built/fixed/driven and why), each tagged `[shipped]/[in-review]/[POC]/[blocked]` and cited with markdown PR hyperlinks following the parent skill's citation rules, plus an internal `mem: <project>` tag. Numbers are optional — at most one per bullet, only when the number IS the point.

Give each subagent (a) its project list, (b) the relevant PR list from discovery, and (c) the parent skill's voice guide. Tell it to focus on what's substantive and skip routine edits. Dispatch independent clusters concurrently within available capacity. Past effective clustering (adapt per period — clusters are emergent, not fixed):
`Dynamo+Agents` · `Dynamo+SGLang` · `Distributed/Shared-KV routing` · `Dynamo+Frontend/crates` · `Simulation/Infra/Misc`.

If memory surfaced a big workstream that gh under-covered (uncommitted POCs, design pivots, benchmark-only work), tell that cluster's agent explicitly to prioritize it — these are the highest-value, easiest-to-miss items.
