---
name: sglang-explore
description: Explore SGLang codebase architecture and trace component interactions for KV cache, disaggregated inference, and event systems
user-invocable: true
---

# SGLang Codebase Explorer

You are exploring the SGLang codebase at `~/sglang`. Use the information below to navigate efficiently and answer questions about SGLang's architecture.

## Key File Locations

### KV Cache System
- **Radix Cache**: `python/sglang/srt/mem_cache/radix_cache.py` -- The core prefix-aware KV cache using a radix tree. Handles token-level cache lookup, insertion, and eviction.
- **HiRadix Cache**: `python/sglang/srt/mem_cache/hiradix_cache.py` -- Hierarchical extension of the radix cache implementing a tiered storage model (GPU -> Host -> Remote).
- **Memory Pool**: `python/sglang/srt/mem_cache/memory_pool.py` -- Manages GPU memory allocation for KV cache blocks.

### Disaggregated Inference
- **KV Events**: `python/sglang/srt/disaggregation/kv_events.py` -- Defines the event system for KV cache lifecycle (BlockStored, BlockRemoved, AllBlocksCleared).
- **Disaggregation base**: `python/sglang/srt/disaggregation/` -- Contains the prefill/decode separation logic and transfer protocols.

### Core Runtime
- **Scheduler**: `python/sglang/srt/managers/scheduler.py` -- The main scheduling loop that batches requests and manages decode steps.
- **TokenizerManager**: `python/sglang/srt/managers/tokenizer_manager.py` -- Handles tokenization and detokenization in the serving pipeline.
- **Model Runner**: `python/sglang/srt/model_executor/model_runner.py` -- Executes forward passes on the model.

### Server / API
- **Server entrypoint**: `python/sglang/srt/entrypoints/openai/api_server.py` -- The OpenAI-compatible API server.
- **Engine**: `python/sglang/srt/entrypoints/engine/engine.py` -- The core engine that ties together all runtime components.

## Architecture Concepts

### Tiered Cache Model
SGLang's HiRadix cache implements a three-tier storage hierarchy:
- **L1 (GPU)**: Hot KV cache blocks stored in GPU HBM. Fastest access, most limited capacity.
- **L2 (Host / CPU_TIER1)**: Warm blocks offloaded to host memory. Used for recent evictions that may be recalled.
- **L3 (Remote / CPU_TIER2)**: Cold blocks stored on remote nodes or disaggregated storage. Highest capacity, highest latency.

Blocks are promoted/demoted between tiers based on access patterns. The `medium` field on KV events indicates which tier an event refers to: `GPU`, `CPU_TIER1`, or `CPU_TIER2`.

### Disaggregated Inference (Prefill/Decode Separation)
In disaggregated mode, SGLang separates the prefill and decode phases onto different workers:
- **Prefill workers**: Process the full input prompt, generating initial KV cache entries. These are compute-bound.
- **Decode workers**: Generate tokens autoregressively using the cached KV data. These are memory-bandwidth-bound.
- KV cache blocks are transferred between prefill and decode workers via the KV event and transfer system.

### KV Event System
The event system in `kv_events.py` tracks KV cache block lifecycle:
- **BlockStored**: A block has been written to a specific tier. Contains block hash, token data, and medium.
- **BlockRemoved**: A block has been evicted from a tier.
- **AllBlocksCleared**: Full cache reset (e.g., on model reload or OOM recovery).

Events are published to subscribers (e.g., Dynamo's KV-aware router) to enable informed routing decisions.

## How to Explore

When asked to explore a specific feature or component:

1. Start from the relevant key file listed above.
2. Use Grep to trace function calls and class references across the codebase.
3. Follow imports to understand the dependency chain.
4. Present findings with file paths and line numbers for easy navigation.
5. When tracing cross-component interactions, describe the flow step by step.

Always ground your exploration in actual file contents -- read the code before describing behavior.

## Debugging SGLang Issues

When investigating SGLang bugs, these are common investigation paths:

**KV events not reaching Dynamo router:**
Trace the pipeline: RadixCache -> ZmqEventPublisher -> ZMQ socket -> Dynamo subscriber. Check each hop.

**BlockStored/BlockRemoved mismatch (orphan blocks):**
Collect events from subscriber, track stored hashes, remove on BlockRemoved. Remaining are orphans -- find the missing eviction path.

**Wrong medium field on tier transitions:**
Check whether HiRadixCache is being used (not plain RadixCache), and whether the tier transition function emits the right event type.

**SGLang version upgrade broke Dynamo:**
Diff `server_args.py` and `kv_events.py` between versions. Check ConfigArgumentMerger compat. Run E2E test in agg and disagg modes.
