---
name: codebase-trace
description: Trace a feature or request flow through Dynamo and SGLang codebases, producing flow diagrams showing component interactions
user-invocable: true
---

# Codebase Flow Tracer

You trace features and request flows through the Dynamo and SGLang codebases, producing mermaid diagrams that show the complete call chain.

## Codebases

- **Dynamo** (Rust + Python): `~/dynamo`
  - Rust core: `~/dynamo/lib/`
  - Python components: `~/dynamo/components/src/dynamo/`
  - SGLang integration: `~/dynamo/components/src/dynamo/sglang/`
- **SGLang** (Python + C++/CUDA): `~/sglang`
  - Runtime: `~/sglang/python/sglang/srt/`
  - API layer: `~/sglang/python/sglang/srt/entrypoints/`

## Rust/Python Boundaries

Key integration points where Dynamo (Rust) calls into or wraps SGLang (Python):

1. **Request ingress**: Dynamo's Rust HTTP layer receives requests, performs tokenization, and routes to SGLang workers.
2. **SGLang worker wrapper**: `~/dynamo/components/src/dynamo/sglang/main.py` -- The Dynamo wrapper that launches and manages the SGLang runtime.
3. **KV event subscription**: Dynamo subscribes to SGLang's KV events for cache-aware routing decisions.
4. **Health checks**: `~/dynamo/components/src/dynamo/sglang/health_check.py` -- Dynamo-side health monitoring of SGLang workers.

## How to Trace

When the user asks to trace a feature or flow:

1. **Identify the entry point**: Where does the request/event originate? (API endpoint, internal event, timer, etc.)
2. **Read the actual code**: Use Read and Grep tools to follow the call chain. Do not guess -- read each file.
3. **Cross boundary tracking**: When the flow crosses from Rust to Python or vice versa, note the boundary explicitly.
4. **Produce a mermaid diagram**: Show the flow as a sequence diagram or flowchart.

## Diagram Format

Use mermaid sequence diagrams for request flows:

```mermaid
sequenceDiagram
    participant Client
    participant DynamoRouter as Dynamo Router (Rust)
    participant DynamoTokenizer as Dynamo Tokenizer (Rust)
    participant SGLangWorker as SGLang Worker (Python)
    participant Scheduler as SGLang Scheduler
    participant ModelRunner as Model Runner

    Client->>DynamoRouter: POST /v1/completions
    DynamoRouter->>DynamoTokenizer: tokenize(prompt)
    DynamoTokenizer-->>DynamoRouter: token_ids
    DynamoRouter->>SGLangWorker: forward(token_ids)
    SGLangWorker->>Scheduler: add_request()
    Scheduler->>ModelRunner: forward_batch()
    ModelRunner-->>Scheduler: logits
    Scheduler-->>SGLangWorker: generated_tokens
    SGLangWorker-->>DynamoRouter: response
    DynamoRouter-->>Client: completion
```

Use mermaid flowcharts for architectural overviews:

```mermaid
flowchart TD
    A[Client Request] --> B[Dynamo HTTP Layer]
    B --> C{KV-Aware Router}
    C -->|cache hit| D[Worker with cached KV]
    C -->|cache miss| E[Least loaded worker]
    D --> F[SGLang Runtime]
    E --> F
    F --> G[Scheduler]
    G --> H[Model Runner]
    H --> I[Response]
```

## Tracing Checklist

For each trace, ensure you cover:

- [ ] Entry point (file + function)
- [ ] Each function call in the chain (file:line_number)
- [ ] Any async boundaries (await points, queue submissions)
- [ ] Rust/Python boundary crossings
- [ ] Data transformations (what format is the data at each stage?)
- [ ] Error handling paths (where can failures occur?)
- [ ] The return/response path back to the caller

## Common Flows to Trace

If the user does not specify a flow, suggest these common ones:

1. **Inference request (end-to-end)**: Client -> Dynamo -> SGLang -> Model -> Response
2. **KV cache lookup and eviction**: Request arrives -> radix tree lookup -> cache hit/miss -> eviction if needed
3. **KV event publishing**: Block stored -> event emitted -> Dynamo router updated
4. **Disaggregated prefill-decode handoff**: Prefill worker processes prompt -> KV transfer -> Decode worker generates tokens
5. **HiCache tier promotion/demotion**: GPU eviction -> host memory -> remote storage
