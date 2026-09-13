# Support-window compatibility

The checked-out component policy owns the support window. Read its instructions and existing compatibility layer; do not infer the minimum from the new target version or a historical skill example.

- For N and N-1 support, keep any fallback needed by N-1, even if its new import was introduced in N. A “remove when minimum >= X” condition compares X with the actual minimum supported version.
- Prune only branches, polyfills, and wrappers whose old path cannot be needed by any supported version. A remaining simple re-export may be inlined when that is a smaller implementation; file deletion is not a goal by itself.
- Centralize import/API drift in the component's established compatibility layer instead of scattering try/except blocks through handlers. Shim only the surface Dynamo actually uses.
- For moved symbols, prefer the new import and fall back on ImportError only when the supported old version needs it. For signature drift, use the existing signature/probing wrapper pattern. Do not rely on a package version string when it does not identify the API layout reliably.
- Tag fallbacks with the version condition that retires them. Defer CUDA-only imports where the module must be importable on CPU/CI nodes.
- When an import becomes unconditional, inspect `tests/report_pytest_markers.py` and its SGLang mock allow-list in the current checkout. Update the list if collection in the isolated pre-commit environment requires it. Run the applicable collection tests and repository hooks.

Record each removed/retained branch and its supported-version rationale. Test affected imports and representative behavior on the minimum and target versions, using separate worktrees/environments for the validation matrix. If the policy is genuinely ambiguous, continue independent upgrade work while resolving that support decision.
