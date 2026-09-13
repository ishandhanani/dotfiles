# Backend launch coverage

Discover the launch scripts in the checked-out `examples/backends/sglang/launch/` and read each before execution. Historical coverage included aggregated chat, embeddings, router, vision, disaggregated/router/same-GPU variants, DLLM, image/video diffusion, and multimodal encode/prefill/decode. Use the current scripts rather than assuming this list or GPU counts are fixed.

Run simpler paths first. Compare each path's actual GPU/model requirements with the selected compute allocation. Choose small representative models where the change permits. Record every applicable path as pass, fail, or skipped with a concrete reason. A hardware limitation is a coverage limitation, not a pass.

For each phase:

1. Record the exact command, model, task-owned process group/job, and log/artifact directory. Use a separate process group for launchers that trap `kill 0`.
2. Wait for model readiness with a timeout, then exercise the endpoint: chat response, embedding dimensions, routing behavior, vision request, or a decodable nonempty image/video artifact.
3. For vision, prefer a known local image encoded inline when remote example URLs fail. For gated/heavy models, inspect cache/authentication and download availability before launch. Never ask the user to paste a token; use the supported authentication flow.
4. On failure, inspect the traceback and the relevant current upstream API before patching. A CuDNN mismatch or rate limit is an environment lead; do not disable dependency checks globally because a prior release required it.
5. Stop only recorded phase-owned processes/jobs, verify GPU/process cleanup, and keep logs. Escalate TERM to KILL only for processes that fail to exit; do not affect shared services or unrelated jobs.

After a fix or compatibility pruning, rerun affected paths and required repository checks. For a complete backend version bump, account for every applicable current launch path in the final matrix. If an unavailable external resource blocks a path, retain the evidence and explain the remaining validation.
