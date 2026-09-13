# Risk surfaces

Select only the surfaces present in the requested target. These are hypotheses to inspect, not expected findings.

### Bucket A - Semantics, Contracts, and Tests

- logical regression or changed behavior at boundaries
- API, wire-format, schema, or contract drift
- unstated invariants, ambiguous ownership, or unclear rollout/migration assumptions
- implicit behavior changes that the plan or patch does not name
- fallback, error-handling, or guarantee changes that silently weaken behavior
- missing edge cases, mismatched tests, weak assertions, or tests that miss the risky path
- breaking changes without a migration path
- misleading documentation, examples, or configuration guidance

### Bucket B - Concurrency, Atomicity, and Lifecycle

- half-committed state from multi-step or multi-structure updates
- stale plan/publish windows without validation or retry
- data races, lost updates, ABA-style reuse, or inconsistent snapshots
- deadlocks, lock-order inversions, recursive lock hazards, or widened lock scope
- blocking operations in async contexts or locks held across `.await`
- tight loops, busy waits, or retries without yield, sleep, or backoff
- missing cancellation or shutdown paths
- resource lifecycle leaks involving tasks, handles, files, sockets, listeners, or subscriptions
- in-process queue boundedness, backpressure, and producer/consumer shutdown behavior

### Bucket C - Distributed Consistency and Recovery

- unclear atomicity boundaries across process, service, stream, or storage layers
- weak idempotency, replay, deduplication, or ordering guarantees
- recovery gaps after partial failure, restart, reconnect, compaction, or snapshot restore
- stale cursor, generation, lease, epoch, sequence, or version handling that can admit old state
- divergent source-of-truth assumptions between local state, durable logs, caches, and subscribers
- missing backpressure, boundedness, or failure propagation in queues, streams, and subscribers
- distributed invariant violations during rollout, failover, retry, or recovery

### Bucket D - Architecture, Patterns, and Dependencies

- duplicated logic or deviation from established repository patterns without a concrete reason
- stale or deprecated APIs/crates
- unnecessary hand-written replacements for standard facilities or maintained dependencies
- failure to follow existing workspace dependency and layering patterns
- naming or module structure that conflicts with nearby conventions
- dead code, unused imports, or hardcoded values that should be configuration
- additional indirection that obscures data flow, ownership, or invariants
- one-hop methods or trivial wrappers without validation, contract clarity, reuse value, or a meaningful abstraction boundary
- premature generalization that introduces complexity before it is needed
- needlessly complex direction when a simpler approach is likely available

### Bucket E - Performance and Resource Efficiency

- new dynamic dispatch where static dispatch was previously sufficient
- new boxing, heap allocation, trait objects, or avoidable `Arc`/`Mutex` churn
- unnecessary cloning, copying, collection materialization, formatting, or string building
- unnecessary intermediate `Vec`, `HashMap`, or similar collection construction
- extra scans, lookups, retries, branches, call depth, or synchronization in hot paths
- loss of locality, cache friendliness, batching, short-circuiting, or early returns
- avoidable CPU, memory, latency, throughput, file-descriptor, or network overhead
- resource growth that is bounded but operationally excessive under expected load
