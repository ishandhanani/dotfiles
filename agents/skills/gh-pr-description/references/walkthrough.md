# Detailed PR walkthrough

Use when the implementation needs substantial reviewer explanation. Omit inapplicable sections; a small change does not require a large template.

## Managed Block

Use exactly these hidden markers:

```md
<!-- codex-pr-description:start -->
Explain the concrete problem, resulting behavior, and why the change matters. Scale detail to the change.

CLOSES: DYN-123

### How This Was Implemented
- Short implementation bullet.
- Another bullet only if it adds signal.

<details>
<summary>Walkthrough</summary>

#### Mental model

Explain the behavior in plain language, then include a Mermaid flow or sequence diagram when state, data, or ownership crosses three or more components.

#### State and ordering

Explain state, scores, precedence, tie-breaking, and a small concrete example when applicable.

#### Request lifecycle

Trace the relevant success and failure paths and explain why new helpers or indirection exist.

#### Boundaries and limitations

State material approximations, limitations, and known sharp edges.

</details>

### Validation
- `command` or `Not run (reason)`.

### Benchmark Results
- Only include this section if benchmarks were run.
- Present headline numbers as a compact Markdown table with units and baseline deltas where applicable; link artifacts/logs instead of pasting raw output.
- When one graph adds useful signal, create it from the summarized benchmark data, use an authorized artifact destination and embed or link the result below the table. A PR-description request alone does not authorize publishing a gist.
<!-- codex-pr-description:end -->
```

## Walkthrough Content

Treat the walkthrough as the durable explanation a reviewer needs to understand the implementation without reconstructing it from the diff. Include every applicable item:

- Start with the simplest mental model and the observable outcome.
- Use one compact Mermaid flowchart for multi-component state/data/ownership flow, or a sequence diagram when lifecycle ordering is central.
- Explain state ownership, scoring or ordering semantics, precedence, ties, and one small numeric/table example when useful.
- Explain why each non-obvious helper, adapter, or indirection exists and which existing machinery it reuses.
- Trace the request/event lifecycle, including when state is committed and how cancellation or failure behaves.
- State current approximations, limitations, and sharp edges. Never leave superseded design claims in place.
- Name relevant files/functions, but do not turn the walkthrough into a file inventory.

Omit inapplicable headings, not applicable information. Refresh the walkthrough every time the PR changes enough to affect any explanation, diagram edge, ordering rule, validation statement, or limitation.
