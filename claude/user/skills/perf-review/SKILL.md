---
name: perf-review
description: Review code changes for performance implications in inference serving hot paths including KV cache, routing, and tokenization
user-invocable: true
---

# Performance Review for Inference Serving

You review code changes for performance implications in inference serving systems built on Dynamo and SGLang. Focus on hot paths and common pitfalls.

## Hot Paths

These code paths are performance-critical and deserve extra scrutiny:

### 1. Tokenization (Dynamo - Rust)
- Runs on every request. Any overhead here multiplies by QPS.
- Watch for: unnecessary string copies, repeated regex compilation, allocation per token.
- Location: Dynamo's Rust tokenizer layer.

### 2. KV Cache Management (SGLang - Python)
- Radix tree operations on every prefill and decode step.
- Watch for: O(n) scans where O(1) lookups exist, lock contention on cache structures, unnecessary cache invalidation.
- Locations:
  - `~/sglang/python/sglang/srt/mem_cache/radix_cache.py`
  - `~/sglang/python/sglang/srt/mem_cache/hiradix_cache.py`

### 3. Routing (Dynamo - Rust)
- KV-aware routing decision on every request.
- Watch for: expensive similarity computations, stale cache metadata, lock contention on routing tables.
- Location: Dynamo's router components.

### 4. Event Processing (SGLang + Dynamo)
- KV events (BlockStored, BlockRemoved) are emitted frequently during cache operations.
- Watch for: synchronous event publishing blocking the scheduler, unbounded event queues, serialization overhead.
- Location: `~/sglang/python/sglang/srt/disaggregation/kv_events.py`

### 5. Scheduler Loop (SGLang - Python)
- The core scheduling loop runs continuously, batching requests and executing forward passes.
- Watch for: GIL contention, blocking I/O in the scheduling loop, inefficient batch construction.
- Location: `~/sglang/python/sglang/srt/managers/scheduler.py`

## Python Performance Pitfalls

### GIL Contention
- CPU-bound Python code in threaded contexts blocks all threads.
- Prefer asyncio for I/O-bound work; use multiprocessing or Rust extensions for CPU-bound work.
- Flag: Any new `threading.Thread` doing CPU-bound work in hot paths.

### Unnecessary Copies
- `list(generator)` materializes everything into memory. Prefer generators/iterators when possible.
- `dict.copy()` or `dataclass.replace()` in loops -- each creates a new allocation.
- String concatenation in loops (`+=`) creates O(n^2) behavior. Use `str.join()` or `io.StringIO`.

### Asyncio Patterns
- `await` in a tight loop serializes work. Use `asyncio.gather()` for concurrent I/O.
- Blocking calls (file I/O, synchronous HTTP) in async functions block the event loop.
- Flag: `time.sleep()` in async code (should be `asyncio.sleep()`).

### Memory Allocation
- Creating temporary objects (dicts, lists, dataclasses) in per-request or per-token paths.
- Flag: Object creation inside `for token in tokens` or `for req in batch` loops.

## Rust Performance Pitfalls

### Unnecessary Allocations
- `String::from()` or `.to_string()` when `&str` suffices.
- `Vec::new()` + push in a loop when capacity is known (use `Vec::with_capacity()`).
- `.clone()` on large structures when a reference would work.

### Lock Contention
- `Mutex` or `RwLock` held across await points blocks other tasks.
- Flag: `.lock().unwrap()` followed by `.await` before the guard is dropped.
- Prefer fine-grained locks or lock-free structures for high-contention data.

### Serialization
- serde serialization/deserialization in hot paths (e.g., per-event JSON encoding).
- Consider binary formats (bincode, MessagePack) for internal communication.
- Flag: `serde_json::to_string` in per-request or per-event paths.

## Inference-Specific Concerns

### Batch Size Sensitivity
- Throughput scales with batch size up to a point, then becomes memory-bound.
- Changes that increase per-request memory usage may reduce effective batch size.
- Flag: New per-request buffers or allocations that scale with sequence length.

### Memory Bandwidth
- Decode phase is memory-bandwidth-bound (reading KV cache).
- Changes that increase KV cache reads per token (e.g., redundant attention recomputation) directly impact latency.
- Flag: Additional data reads per decode step.

### GPU Memory
- GPU memory is the scarcest resource. Any leak or fragmentation reduces cache capacity.
- Flag: GPU tensors that are not explicitly freed, Python references that prevent garbage collection of GPU memory.

## Review Checklist

When reviewing code changes, check each applicable item:

- [ ] **Is this on a hot path?** (tokenization, scheduling, cache ops, routing, event processing)
- [ ] **Allocation audit**: Any new allocations per request/token/event?
- [ ] **Lock audit**: Any new locks? Are they held across async boundaries?
- [ ] **Copy audit**: Any unnecessary data copies or materializations?
- [ ] **GIL impact**: Does this add CPU-bound Python work in a threaded context?
- [ ] **Async correctness**: Any blocking calls in async functions?
- [ ] **Memory impact**: Does this change affect per-request GPU/CPU memory usage?
- [ ] **Batch size impact**: Could this reduce effective batch sizes?
- [ ] **Serialization**: Any new serialization in hot paths?
- [ ] **Benchmark**: Has the change been benchmarked under realistic load?

## How to Review

1. Read the diff carefully, identifying which files are modified.
2. For each modified file, determine if it is on a hot path (see Hot Paths above).
3. Apply the relevant pitfall checks from the checklists.
4. For each finding, provide:
   - The specific file and line
   - What the concern is
   - Why it matters for performance
   - A suggested fix or alternative approach
5. Summarize overall performance impact: negligible, minor, moderate, or significant.
