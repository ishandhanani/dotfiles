# Historical SGLang 0.5.9 integration failures

Use these as symptom leads only. Confirm the current source, supported input contract, and actual failing path before applying a fix. API/import drift belongs to the checked-out compatibility policy; see [compatibility.md](compatibility.md).

### Pattern A — Result type changed from `dict` to dataclass

Symptom: `TypeError: 'GenerationResult' object is not subscriptable` or `AttributeError: 'dict' object has no attribute 'frames'`.

Where it hit in 0.5.9:
- `components/src/dynamo/sglang/request_handlers/video_generation/video_generation_handler.py`
- `components/src/dynamo/sglang/request_handlers/image_diffusion/image_diffusion_handler.py`

Fix shape: replace `result.get("frames", [])` / `result["frames"]` with `result.frames`, with `None`/empty-list guards. Apply the same to any sibling fields the new dataclass exposes.

### Pattern B — Required field defaulted to None

Symptom: `TypeError: unsupported operand type(s) for -: 'NoneType' and 'int'` deep in an SGLang scheduler mixin.

Where it hit in 0.5.9: `components/src/dynamo/sglang/args.py` — `max_running_requests` was None for DLLM workers because DLLM's mixin assumed normal-scheduler init had already run.

Fix shape: in `args.py`, after server-args construction, guard the relevant attribute and supply a sane default (8 for DLLM-style workers in 0.5.9). Use `getattr(args, ..., None)` so `SimpleNamespace` test stubs don't break.

### Pattern C — ModelType / output modality regression

Symptom: Rust frontend looks for a `config.json` that doesn't exist (diffusers checkpoints don't ship one), or an image worker registers as a chat model.

Where it hit in 0.5.9: `components/src/dynamo/sglang/init_diffusion.py`. The default `--output-modalities=["text"]` collapsed `ModelType.Images` back to `Chat|Completions`.

Fix shape: in the per-worker init module, override `output_modalities` to the correct value (`["image"]` for image, `["video"]` for video, etc.) before model registration.

### Pattern D — `engine is None` for non-LLM handlers

Symptom: `AttributeError: 'NoneType' object has no attribute 'tokenizer_manager'` when launching encode-only / mm-encode workers.

Where it hit in 0.5.9: `components/src/dynamo/sglang/request_handlers/handler_base.py` — `BaseWorkerHandler.__init__` unconditionally touched `engine.tokenizer_manager` and `engine.async_generate`, but `MultimodalEncodeWorkerHandler` constructs with `engine=None` (it owns an `MMEncoder` instead).

Fix shape: guard those attribute accesses behind `if engine is not None`. Don't push the guard further out — the call sites do legitimately pass `None`.
