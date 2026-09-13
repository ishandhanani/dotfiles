# Audit ledger

When an agent home is known, preserve the existing `scaffold-review-ledger.json` and append a run with timestamp, sample count, report location, and proposals. Otherwise record the same information in the project's audit note; a missing host ledger does not block completion.

Each proposal records description, confidence, evidence, and status (`applied`, `deferred`, or `rejected`). For deferred work, state the actual reason and remaining decision. Keep prior runs and trends; do not overwrite them with the current summary. Distinguish observation from causal attribution and avoid declaring a trend confirmed solely from repeated generated reports.

After applying script changes, run its relevant fixture tests and one bounded real-sample extraction. Re-read changed skill roots and references for contradictions. Record significant results through `memory-log`, including measured root/transitive read sizes and actual validation limits.
