---
name: dynamo-sglang-bump
description: Bump Dynamo's SGLang backend to a new SGLang version. Sets up a clean dynamo main checkout, target SGLang tag, fresh venv, then walks every launch script and fixes API breakage as it surfaces. Use when the user asks to upgrade/bump SGLang in Dynamo (e.g. "update dynamo for sglang 0.5.X").
user-invocable: true
---

# Dynamo SGLang Version Bump

End-to-end recipe for upgrading the `dynamo.sglang` backend to a new SGLang release.

The upgrade is **bottom-up empirical**: spin up the canonical environment, then run each launch script in `examples/backends/sglang/launch/` and fix breakage as it appears. Don't try to predict the diff from release notes — let the scripts surface real failures.

## Canonical Paths

| Path | Purpose |
|------|---------|
| `/ephemeral/dynamo` | Dynamo checkout. **Always start on `main` and pull.** |
| `/ephemeral/sglang` | SGLang upstream checkout. **Checkout the target tag (`vX.Y.Z`).** |
| `~/aiperf` | Benchmark client (rarely needed for a bump). |

If these paths don't exist on the box, ask the user before cloning to a new location — they may have a different layout.

## Step 1: Confirm Inputs

Before touching anything, confirm with the user:
- **Target SGLang version** (e.g. `0.5.9`, mapped to tag `v0.5.9`).
- **Branch name**. Default convention: `idhanani/sgl-to-<ver>-and-cleanups` (matches the `0.5.9` precedent on `ishan/sgl-to-0.5.9-and-cleanups`).
- **Linear ticket** if there is one, for the PR description.

## Step 2: Reset Dynamo to main

```bash
cd /ephemeral/dynamo
git status                         # must be clean; if not, ask the user
git checkout main
git pull --ff-only origin main
git checkout -b <branch-name>
```

Refuse to proceed if the working tree is dirty — those are the user's in-progress changes.

## Step 3: Checkout SGLang at Target Tag

```bash
cd /ephemeral/sglang
git fetch origin --tags
git checkout v<target-version>     # e.g. v0.5.9
git status                         # verify detached HEAD at the tag
```

If the tag is missing, run `git fetch origin --tags --force` and retry. Don't silently fall back to a different ref.

## Step 4: Fresh venv

A fresh venv is **not optional** for this skill — old SGLang artifacts in site-packages cause confusing import-time errors that look like Dynamo bugs.

```bash
cd /ephemeral/dynamo
deactivate 2>/dev/null || true
rm -rf .venv-sgl-<version>          # name it after the target version
uv venv .venv-sgl-<version> --python 3.12
source .venv-sgl-<version>/bin/activate
```

Verify isolation:
```bash
which python
python -c "import sglang" 2>&1 | head -1   # expected: ModuleNotFoundError
```

## Step 5: Install SGLang (Local Editable)

Install from the `/ephemeral/sglang` checkout, not from PyPI — this lets you grep into the live SGLang source while debugging.

```bash
cd /ephemeral/sglang && uv pip install -e "python"
python -c "import sglang; print(sglang.__version__)"
```

The reported version must match the target. If pip resolves a different one, look for a `requirements*.txt` constraint pinning it elsewhere.

## Step 6: Build Dynamo Bindings + Install

```bash
cd /ephemeral/dynamo/lib/bindings/python && maturin develop --uv
cd /ephemeral/dynamo && uv pip install -e .
```

Sanity check the rebuilt Rust exports — the `kvstats` symbol on `dynamo.prometheus_names` was missing during the 0.5.9 bump until the bindings were rebuilt:

```bash
python -c "from dynamo.prometheus_names import kvstats; print('ok')"
```

## Step 7: Known Environment Gotchas

Encode these as preflight env vars for the test session:

- **CuDNN mismatch** (`SGLANG_DISABLE_CUDNN_CHECK=1`)
  PyTorch ships an older CuDNN than newer SGLang requires for Conv3d (vision/multimodal). Set this before launching `agg_vision.sh` and any multimodal script. Required for 0.5.9.
- **Local model cache**: confirm `HF_HOME` / `HF_HUB_CACHE` point to a fast disk (`/ephemeral/cache` on this box) so tests don't redownload weights.

## Step 8: Walk Every Launch Script

**Read first** before launching anything:
- `components/src/dynamo/sglang/CLAUDE.md` — SGLang Backwards Compatibility policy and component layout.
- `components/src/dynamo/sglang/_compat.py` — current shim. The existing fallback comments tell you what N-1 is *today*; that's the version about to age out.

Path: `/ephemeral/dynamo/examples/backends/sglang/launch/`

Run them in roughly this order — simpler first, multi-modal/diffusion last:

```text
agg.sh
agg_embed.sh
agg_router.sh
agg_vision.sh
disagg.sh
disagg_router.sh                    # needs >=4 GPUs; SKIP otherwise
disagg_same_gpu.sh                  # ask the user; often skip
diffusion_llada.sh
image_diffusion.sh
text-to-video-diffusion.sh
multimodal_epd.sh
multimodal_disagg.sh                # needs >=3 GPUs; SKIP otherwise
```

For each script:

1. Note `nvidia-smi` GPU count vs. script's GPU need. Skip with a recorded reason if short.
2. `pkill -9 -f sglang; pkill -9 -f dynamo; sleep 3` before launch.
3. Tee output: `bash launch/<script>.sh 2>&1 | tee /tmp/dyn-sgl-bump-<script>.log`.
4. Validate with the matching health/inference probe:
   - chat scripts: `curl -s -X POST localhost:8000/v1/chat/completions -d '{...}'`
   - embed: `/v1/embeddings`, expect dim count
   - router: confirm `kv_hit_rate` field appears in a response
   - diffusion/video: check `result.frames` is non-empty
5. On failure, **read the full traceback before guessing** — guessing from release notes wastes more time than reading the stack. Then jump to the fix patterns below.
6. After PASS, kill cleanly. Don't leave servers behind between scripts.

## Step 9: Fix Patterns (from 0.5.9 bump — expect similar shapes)

When the same kind of breakage recurs across SGLang releases, it usually fits one of these molds. **Match the symptom, then read SGLang source to confirm before patching Dynamo.**

> **Before patching anywhere else, ask: "Is this an SGLang import / API surface change?"** If yes, the fix belongs in `components/src/dynamo/sglang/_compat.py` (Pattern E). Component code must not grow scattered try/except blocks for SGLang imports.

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

### Pattern E — SGLang API moved / renamed / signature changed (use `_compat.py`)

This is the **most common shape of breakage** across SGLang bumps. Always handle these in `components/src/dynamo/sglang/_compat.py` — never scatter try/except blocks across handler/init files.

Read `components/src/dynamo/sglang/CLAUDE.md` ("SGLang Backwards Compatibility" section) and the existing `_compat.py` before adding anything. The policy in force:

1. **Support window: N and N-1.** Whatever the new target version is, that becomes N. The previous release becomes N-1 and stays supported via a fallback. Anything older gets deleted in this same PR.
2. **Only symbols that have actually broken belong in `_compat.py`.** Don't preemptively shim every `sglang.*` import.
3. **Try new path first, except `ImportError`, fall back.** Example layout:
   ```python
   try:
       from sglang.srt.utils.network import NetworkAddress, get_local_ip_auto
   except ImportError:
       # Fallback for sglang 0.5.9. Remove when min supported version is 0.5.10+
       from sglang.srt.utils import get_local_ip_auto
       class NetworkAddress: ...   # minimal polyfill
   ```
4. **Every fallback branch carries a "remove when" comment** naming the version that retires it. No exceptions — without that line, future bumps can't safely prune.
5. **Polyfill only what Dynamo actually calls.** `NetworkAddress` in `_compat.py` only implements the surface area component code touches.
6. **Never gate on `sglang.__version__`.** SGLang's version string doesn't always reflect the internal layout. Use `try/except ImportError` (for moved symbols) or `inspect.signature` / `getattr` probing (for changed signatures — see `filter_supported_async_generate_kwargs` and `mm_encode` in the existing file).
7. **Signature drift gets a wrapper, not a try/except at every call site.** Examples already in `_compat.py`:
   - `mm_encode(encoder, mm_items, modality)` — wraps `MMEncoder._encode` whose 0.5.10 signature gained a `modality` arg and a 3rd return value.
   - `enable_disjoint_streaming_output(server_args)` — bridges the `stream_output` → `incremental_streaming_output` rename on `ServerArgs`.
   - `get_scheduler_info(engine)` — probes multiple known attribute paths instead of pinning one.
8. **Defer CUDA-only imports.** `_compat.py` is loaded on test/CI nodes too. Anything that pulls `sgl_kernel` (e.g. multimodal encoder internals) must be inside the function body, not at module top.

**Required cleanup as part of every bump PR**: prune branches that fall outside the new N / N-1 window. If pruning leaves `_compat.py` as trivial re-exports, inline the imports at call sites and delete the file. The compat shim is meant to be temporary; carrying dead branches forever defeats the policy.

In the worklog, list each `_compat.py` change as its own row — mark added, modified, or removed branches and the version each one targets.

### General rule

- **One fix = one commit** with a message like `sglang: fix <symptom> for <script>`.
- Reference the script that exposed it. This makes the worklog table self-documenting.
- Avoid drive-by cleanups in these commits — the PR is already wide; reviewers will want each fix readable in isolation.
- **`_compat.py` edits are an exception**: bundle related shim changes into one commit (`sglang: extend _compat for <ver>`) so the shim is reviewable as a coherent unit instead of being touched by every other commit.

## Step 10: Deprecate Out-of-Window Compat (REQUIRED)

After all launch scripts pass on the new version, **before opening the PR**, do the deprecation pass. The N / N-1 policy is only meaningful if the bump PR is also the moment we shed N-2 and older.

After bumping to version `<new>`:
- **N** = `<new>` (the new floor + ceiling target)
- **N-1** = the version that was current before this bump (still supported)
- **Anything older** = must be removed in this PR

Procedure:

1. Open `components/src/dynamo/sglang/_compat.py`. For every fallback branch and polyfill, read its `# Fallback for sglang <ver>. Remove when min supported version is <next>+` comment.
2. Decide its fate:
   | Branch's "Remove when ≥" | Action |
   |--------------------------|--------|
   | `<= new>` | **Remove.** New version is now the floor; the fallback is dead code. |
   | `> new` (still future) | Keep. |
   | Untagged | Treat as bug from a prior bump. Either tag it correctly now or remove it. |
3. After deletions, also remove:
   - Polyfill classes (e.g. the inline `NetworkAddress` polyfill once 0.5.10 is the floor).
   - Helper wrappers whose multi-version probing is no longer needed (`mm_encode`, `enable_disjoint_streaming_output`, `get_scheduler_info`) — if all probed paths collapse to one, inline the canonical call at the call sites and delete the wrapper.
   - `__all__` entries for symbols you removed.
4. If `_compat.py` collapses to trivial re-exports (no try/except, no polyfills, no signature probing), **delete the file** and rewrite the call sites to import directly from `sglang.srt....`. The shim is meant to be temporary.
5. Run the launch-script walk again on the targets you already passed for any handler that now imports differently. Don't trust that "it imported during step 8" means "it still imports after compat pruning" — call sites may have changed.
6. Update `components/src/dynamo/sglang/CLAUDE.md`'s SGLang Backwards Compatibility section if the policy text references a specific version range. Bump the example `# Fallback for sglang <ver>` snippet to the new N-1.

In the worklog, add a section listing every removed branch / polyfill / wrapper and which version it covered. This makes the deprecation reviewable and lets future bumps see the historical pattern.

**This step is not optional.** If you skip it, the compat file accrues dead branches forever and the policy degrades into "everything is supported." If you genuinely think a fallback should outlive the N-1 window (e.g. a downstream consumer pinned to an old SGLang), surface that to the user explicitly — don't silently keep the branch.

## Step 11: Worklog + Memory

When you have ≥1 launch script result, log to `~/memory/dynamo-upgrade-sglang-<ver>/` (create if missing — see `~/memory/dynamo-upgrade-sglang-059/` for the precedent shape).

Required artifacts:
- `INDEX.md` with project frontmatter (status, repo, last-updated)
- `bump-to-sglang-<ver>.md` with:
  - Branch + PR + GPU env preamble
  - Final results table: `# | Script | Status | Notes`
  - One numbered fix section per fix, each citing file:line and root cause

Add a row to `~/memory/INDEX.md`. Commit with `dynamo-upgrade-sglang-<ver>: <short description>` (do not push memory).

## Step 12: PR

```bash
cd /ephemeral/dynamo
git push -u origin <branch>
gh pr create --draft --title "sglang: bump to <ver>" --body "<body>"
```

Body should link the worklog summary table and call out which scripts were SKIPPED (with reason — usually GPU count) so reviewers don't think they were missed.

## Anti-patterns

- Don't `pip install sglang==<ver>` from PyPI — you lose the ability to grep SGLang source while triaging.
- Don't reuse the previous bump's venv. Stale `.so` files in site-packages cause non-obvious failures.
- Don't keep editing without re-running the failing script. The fix is only real once the script PASSes end-to-end.
- Don't bundle infra cleanups into the bump PR. They make review harder and obscure which fix corresponds to which breakage.
- Don't skip a script silently for non-GPU reasons. Either fix it or record why it was skipped.
- Don't add `try: from sglang...new_path except ImportError: from sglang...old_path` blocks inside handler / init / register modules. Every SGLang import-shape change goes in `_compat.py`. The component is supposed to import SGLang either directly (when stable) or from `_compat` (when version-dependent), never via inline try/except.
- Don't gate on `sglang.__version__`. Use `try/except ImportError` for moved symbols and `inspect.signature` / `getattr` probing for changed signatures.
- Don't add a `_compat.py` fallback branch without a `# Fallback for sglang <ver>. Remove when min supported version is <next>+` comment. Untagged branches accrete forever.
- Don't leave fallback branches for versions older than N-1. Pruning them is part of the bump, not a separate cleanup.
