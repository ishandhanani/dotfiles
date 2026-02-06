# Dynamo Directory Map

Navigation aid for the Dynamo codebase. Use `/dynamo:dynamo-explore` for deeper investigation.

## Rust Core (`lib/`)

| Crate | Path | Purpose |
|---|---|---|
| dynamo-llm | `lib/llm/` | Core inference serving: KV routing, block management, HTTP layer |
| dynamo-parsers | `lib/parsers/` | Tool call parsing (JSON, XML, Pythonic, Harmony, DSML) |
| dynamo-tokens | `lib/tokens/` | Tokenization, sequence hashing |
| dynamo-runtime | `lib/runtime/` | Runtime framework, component lifecycle |
| dynamo-config | `lib/config/` | Configuration management |
| dynamo-bindings | `lib/bindings/python/` | PyO3 bindings exposing Rust to Python |

### Key Directories in `lib/llm/src/`

| Directory | What's There |
|---|---|
| `kv_router/` | KV-aware request routing (scheduler, publisher, subscriber, prefill_router) |
| `block_manager/` | KV block lifecycle management |
| `block_manager/kv_consolidator/` | Event dedup and consolidation (tracker.rs is critical) |
| `block_manager/distributed/` | Multi-node block management and transfer |
| `http/service/` | Axum-based HTTP service |
| `discovery/` | Service discovery, worker monitoring, topology |
| `preprocessor/` | Request preprocessing, chat templates |

## Python Components (`components/src/dynamo/`)

| Directory | What's There |
|---|---|
| `sglang/` | SGLang backend wrapper (main.py, args.py, protocol.py, publisher.py) |
| `sglang/request_handlers/llm/` | Per-phase handlers (prefill_handler.py, decode_handler.py) |
| `frontend/` | OpenAI-compatible HTTP frontend |
| `global_router/` | Model/pool selection, cross-cluster load balancing |
| `planner/` | Disaggregated inference orchestration |

## Examples and Deployment

| Directory | What's There |
|---|---|
| `examples/backends/sglang/` | SGLang launch configs (agg.sh, disagg.sh) |
| `examples/backends/vllm/` | vLLM launch configs |
| `examples/backends/trtllm/` | TensorRT-LLM launch configs |
| `deploy/` | Kubernetes, Docker, Slurm deployment configs |
