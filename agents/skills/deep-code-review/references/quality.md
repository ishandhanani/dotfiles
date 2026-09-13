# Structural and performance review

Apply only to changed behavior and affected boundaries. A remedy must earn its complexity through a concrete benefit; a file-size threshold or preference alone does not justify blocking a change.

- Ownership and layering: does the owning component enforce the invariant, or do scattered callers patch symptoms? Can a redundant layer, helper, or state copy be removed without widening scope?
- Contracts: trace changed signatures, defaults, wire formats, failure behavior, and rollout assumptions through consumers. Look for cancellation, reconnect, partial publication, stale generation, and recovery failures.
- State model: inspect branches, modes, and nullable states that permit invalid combinations or obscure transitions. Prefer the existing canonical representation over introducing another abstraction.
- Boundaries and types: identify casts, fallback paths, or loosely typed data that hide a real invariant mismatch. Prefer a specific boundary correction to a speculative general validation layer.
- Concurrency: examine lock scope, blocking executor work, atomic publication, shutdown, and queue boundedness. Parallelizing independent operations is useful only if it preserves order and makes ownership clearer.
- Hot paths: compare per-request/token/item allocations, clones, boxing, trait dispatch, scans, formatting, serialization, syscalls, IPC, retries, and synchronization. Check whether batching, locality, backpressure, or short-circuiting regressed.
- Resources: bound tasks, queues, connections, memory, and descriptors under expected load. Separate hot-path costs from irrelevant cold-path micro-optimization.
- Validation: test the smallest representative failure or benchmark path; retain uncertainty when production-scale or hardware constraints prevent a direct measurement.

Structural feedback should explain what concrete reasoning, ownership, or runtime problem the proposed simplification removes. Preserve strictness about material defects without turning every alternative design into a finding.
