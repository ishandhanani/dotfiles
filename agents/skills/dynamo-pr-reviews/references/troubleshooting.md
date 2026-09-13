# Symptom-specific troubleshooting

Historical observations are diagnostic leads, not universal environment requirements. Read the target revision's constraints and the selected compute note before changing dependencies.

- `nvcc fatal: Unsupported gpu architecture`: inspect `nvcc --version` and PATH against the GPU architecture. Some older hosts defaulted to CUDA 11.5 despite a newer toolkit being installed. Use the configured toolkit; do not edit shell startup files as a review side effect.
- SGLang, transformers, huggingface_hub, or kernel import failures: inspect the target's pinned versions and resolver result. A prior environment needed newer huggingface_hub for transformers imports; do not copy that pin to unrelated revisions. Establish whether the PR introduces the dependency mismatch before filing a regression.
- Worker registration: model readiness plus a small completion is stronger evidence than frontend liveness. Root-path 404 probes and optional-model import warnings can be harmless; trace the specific startup failure.
- Streaming client cancellation: let the stream complete. Piping curl to `head` can cause a disconnect and a misleading server cancellation error.
- Tool serialization: dataclass/model serialization can add default `strict: false` or optional fields. Verify the consuming API/template behavior with supported requests before flagging an extra field as a defect.
- First-run variability: keep warmup separate, retain every measured result, and investigate intermittent failures rather than suppressing them.
