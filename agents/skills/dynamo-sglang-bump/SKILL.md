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
- **Runtime container tags.** Always ask — these don't always match the pip version 1:1 (`.post1` suffixes, RC tags, CUDA variants). Need:
  - The CUDA-default runtime tag, e.g. `v0.5.11-runtime`
  - The CU130 runtime tag, e.g. `v0.5.11-cu130-runtime`
  Both go into `container/context.yaml`, `container/rendered.Dockerfile`, `container/compliance/README.md`, and any `container/templates/sglang_runtime.Dockerfile` references. **Never guess.** Ask explicitly: "What `lmsysorg/sglang` runtime image tags should I bump to for the default and cu130 variants?"

  **Verify the tags exist on Docker Hub before applying** — `docker buildx imagetools inspect lmsysorg/sglang:v<ver>-runtime` is the cheapest check. SGLang ships *base* images and *runtime* images via two **separate** GitHub Actions workflows ("Release Docker Images" and "Release Docker Runtime Images"), and the runtime workflow has historically failed/been delayed for some releases (e.g. v0.5.11's runtime build initially died on apt-mirror flake during `apt-get update`). If the runtime tag doesn't exist yet:
  - Ask the user whether to (a) wait for upstream to re-run the runtime workflow (`gh run list --repo sgl-project/sglang --workflow "Release Docker Runtime Images"`), (b) push to a maintainer with permission to dispatch it (`workflow_dispatch` accepts a `version` input matching `X.Y.Z`), or (c) **defer the container tag bump to a follow-up PR** and ship the pip bump alone. Option (c) matches the precedent at commit `26af597bf85` ("chore: SGLang base image refresh ...") and is the right call when there's no eta on the runtime images.
  - Whichever path the user picks, mention it explicitly in the bump PR body so reviewers don't think the container files were forgotten.
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

Install from the `/ephemeral/sglang` checkout, not from PyPI — this lets you grep into the live SGLang source while debugging. **Always include `[diffusion]`** — image/video/dllm launch scripts pull in `diffusers`, `imageio`, `imageio-ffmpeg`, `moviepy` etc. via that extra. Without it you'll bounce off `ModuleNotFoundError: imageio` / `diffusers` two scripts in.

```bash
cd /ephemeral/sglang && uv pip install -e "python[diffusion]"
python -c "import sglang; print(sglang.__version__)"
```

The reported version must match the target. If pip resolves a different one, look for a `requirements*.txt` constraint pinning it elsewhere.

## Step 6: Build Dynamo Bindings + Install

A fresh venv has neither `maturin` nor the `nixl` Python bindings — install both first or `maturin develop` will `command not found` and dynamo workers will fail at import with `ImportError: NIXL Python bindings must be installed`.

```bash
uv pip install maturin nixl
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
  PyTorch ships an older CuDNN than newer SGLang requires for Conv3d (vision/multimodal). Set this before launching `agg_vision.sh` and any multimodal script. Required for 0.5.9; still required at 0.5.11.
- **Local model cache**: confirm `HF_HOME` / `HF_HUB_CACHE` point to a fast disk (`/ephemeral/cache` on this box) so tests don't redownload weights.
- **Verify HF_TOKEN before launch.** Anonymous HF requests get 429-rate-limited fast, and gated models (`black-forest-labs/FLUX.1-dev`, anything with a license click-through) refuse outright. `hf auth whoami` must succeed; if it errors with "Invalid user token" the env's `HF_TOKEN` is stale and the user has to provide a fresh one before image_diffusion / multimodal scripts will work.
- **Pre-download the heavy / gated models.** Letting the launch script trigger the download is fragile under HF rate limits — a half-completed download will error mid-init with a confusing 429 traceback. Pre-fetch with `hf download <repo> --token "$HF_TOKEN"` first. Big offenders: FLUX.1-dev (~25 GB, gated), LLaDA2.0-mini-preview (~35 GB), Wan2.1-T2V-1.3B-Diffusers.

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
2. `pkill -9 -f sglang; pkill -9 -f dynamo; pkill -9 -f sgl_diffusion; sleep 3` before launch. Diffusion workers spawn an `sgl_diffusion::scheduler` child process that survives `pkill -f sglang`; explicitly grep for it. After diffusion runs, `nvidia-smi` may still show ~30 GB used by an orphan — kill it by PID.
3. Tee output: `bash launch/<script>.sh 2>&1 | tee /tmp/dyn-sgl-bump-<script>.log`. The dynamo frontend logs a `404 GET /` every ~10s from a health probe that has nothing to do with you; filter with `grep -vE "GET.+uri.+/"` when reading.
4. Validate with the matching health/inference probe:
   - chat scripts: `curl -s -X POST localhost:8000/v1/chat/completions -d '{...}'`
   - embed: `/v1/embeddings`, expect dim count
   - router: confirm a `Selected worker:` line shows up in the worker log per request (kv-router decision)
   - vision: send a `data:image/png;base64,...` URL — public image URLs (Wikimedia, raw.githubusercontent.com test fixtures) often 403 / 404. Use `/ephemeral/sglang/examples/assets/example_image.png` as the canonical inline image.
   - diffusion/video: check the file at the returned `file://...` URL is non-empty (~150 KB MP4 / ~200 KB PNG for the small test args)
5. On failure, **read the full traceback before guessing** — guessing from release notes wastes more time than reading the stack. Then jump to the fix patterns below.
6. After PASS, kill cleanly. Don't leave servers behind between scripts. The `dynamo.frontend` process is reparented to PID 1 after the bash trap fires; `pkill -f sglang` won't catch it. Always re-check `ps -ef | grep -E "sglang|dynamo|sgl_diffusion"` before next launch.

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
3. **Try new path first, except `ImportError`, fall back.** Example layout (this is the *shape*, not the current code — the actual `_compat.py` swings in and out of having branches like this as versions cycle):
   ```python
   try:
       from sglang.srt.new_module import Symbol  # vX.Y+
   except ImportError:
       # Fallback for sglang <vX.Y. Remove when min supported version is vX.Y+
       from sglang.srt.old_module import Symbol  # noqa: F401
   ```
4. **Every fallback branch carries a "remove when" comment** naming the version that retires it. No exceptions — without that line, future bumps can't safely prune.
5. **Polyfill only what Dynamo actually calls.** When SGLang introduces a new class that older releases don't have, the `except ImportError` branch defines a minimal stand-in that covers exactly the methods/attributes component code touches. Don't reproduce the full upstream surface.
6. **Never gate on `sglang.__version__`.** SGLang's version string doesn't always reflect the internal layout. Use `try/except ImportError` (for moved symbols) or `inspect.signature` / `getattr` probing (for changed signatures — see `filter_supported_async_generate_kwargs` in the current file).
7. **Signature drift gets a wrapper, not a try/except at every call site.** Read the current `_compat.py` for the live wrappers — historically these have included `mm_encode` (MMEncoder._encode signature change), `enable_disjoint_streaming_output` (ServerArgs field rename), and `get_scheduler_info` (multi-attribute probing). Wrappers come and go; what stays is the rule that signature drift never leaks into call sites.
8. **Defer CUDA-only imports.** `_compat.py` is loaded on test/CI nodes too. Anything that pulls `sgl_kernel` (e.g. multimodal encoder internals) must be inside the function body, not at module top.
9. **Top-of-module SGLang imports must hold for the pre-commit env too.** `tests/report_pytest_markers.py` mocks an explicit allow-list of `sglang.srt.*` submodules so collection works in the isolated pre-commit venv (no real sglang installed). When you make a previously-conditional `from sglang.srt.foo.bar import ...` unconditional in `_compat.py`, **add `sglang.srt.foo.bar` to the `_MOCK_MODULES` list** in that script — otherwise the `Report pytest markers` hook will fail collecting every sglang test file. Easy to miss because everything works locally where sglang *is* installed.

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
7. **Update the pre-commit mock list.** Open `tests/report_pytest_markers.py` and find the `_MOCK_MODULES` (sometimes just a top-level list literal of `"sglang.srt..."` strings). Any `sglang.srt.*` submodule you newly imported unconditionally — typically by removing a `try/except ImportError` in `_compat.py` and pinning to the canonical path — needs to be added there. Without this entry the `Report pytest markers` hook fails with `ModuleNotFoundError: No module named 'sglang.srt.<thing>'` when collecting any sglang test, because the pre-commit venv has no real sglang installed. **Always run `uvx pre-commit run --all-files` after the deprecation pass to confirm.**

In the worklog, add a section listing every removed branch / polyfill / wrapper and which version it covered. This makes the deprecation reviewable and lets future bumps see the historical pattern.

**This step is not optional.** If you skip it, the compat file accrues dead branches forever and the policy degrades into "everything is supported." If you genuinely think a fallback should outlive the N-1 window (e.g. a downstream consumer pinned to an old SGLang), surface that to the user explicitly — don't silently keep the branch.

## Step 11: Worklog + Memory

When you have ≥1 launch script result, log to `~/memory/dynamo-upgrade-sglang-<ver>/` (create if missing). Use `~/memory/dynamo-upgrade-sglang-0511/` as the current precedent shape — it covers the bundled-feature case (closing a related issue gated on the same version floor) and the deprecation table; older `~/memory/dynamo-upgrade-sglang-059/` is also valid but predates those patterns.

Required artifacts:
- `INDEX.md` with project frontmatter (status, repo, last-updated)
- `bump-to-sglang-<ver>.md` with:
  - Branch + PR + GPU env preamble
  - Final results table: `# | Script | Status | Notes`
  - One numbered fix section per fix, each citing file:line and root cause
  - A `_compat.py` deprecation table (one row per removed branch / polyfill / wrapper)
  - An "env deps that surfaced" section if you had to install anything beyond `[diffusion]` (most fresh venvs need `nixl`, `maturin`, plus `pytest pytest-asyncio pytest-benchmark` to run the unit tests — list whatever bit you so the next bumper doesn't relearn it)

Add a row to `~/memory/INDEX.md`. Commit and push memory changes with `dynamo-upgrade-sglang-<ver>: <short description>`.

## Step 12: PR

Before pushing: **run `uvx pre-commit run --all-files`**. The `Report pytest markers` hook walks every test file and fails if a previously-conditional `sglang.srt.*` import is now unconditional but missing from the mock list (see Step 10.7). Catching this locally is much faster than learning about it from CI.

```bash
cd /ephemeral/dynamo
uvx pre-commit run --all-files
git push -u origin <branch>
gh pr create --draft --title "sglang: bump to <ver>" --body "<body>"
```

Body should link the worklog summary table and call out which scripts were SKIPPED (with reason — usually GPU count) so reviewers don't think they were missed.

**Container image tags ship in this PR — *if* upstream has published them.** Confirm the tags from Step 1 actually resolve on Docker Hub (`docker buildx imagetools inspect lmsysorg/sglang:v<ver>-runtime` returns 0) before editing any container file. If they don't exist yet, defer per the Step 1 contingency — don't write a tag that 404s on pull.

When they do exist, update all of:
- `container/context.yaml` — `runtime_image_tag` for both the default and CU130 entries
- `container/rendered.Dockerfile` — `ARG RUNTIME_IMAGE_TAG=v<new>-runtime`
- `container/compliance/README.md` — the `lmsysorg/sglang:v<...>` table rows
- `container/templates/sglang_runtime.Dockerfile` — any inline version refs (often a comment + the `FROM` tag). The mooncake-packaging workaround comment is version-specific — check whether the workaround is still needed against the new image; if upstream fixed it, remove the workaround block (don't just bump the version in the comment).

Use the tags the user gave in Step 1 verbatim — don't paste a "natural-looking" guess. The pip version and the image tag don't always agree (`.post1`, CU variants, RC suffixes).

**Out of scope for this PR (separate follow-ups):**
- Drive-by cleanups (rename a default model, fix unrelated TODOs in launch scripts, reformat untouched files). Even when the TODO comment ties to "after sglang vX.Y upgrade", let it ride a separate PR.

**Bundling exception:** if a feature is *gated* on the new version floor (e.g. a Grafana panel that needs metrics introduced in the bumped version), the user may explicitly request bundling it in. That's fine — it's not a drive-by, it's a feature that could not ship before this PR. Surface the bundling decision in the PR body and the worklog (see `~/memory/dynamo-upgrade-sglang-0511/` for the #8151 precedent).

## Anti-patterns

- Don't `pip install sglang==<ver>` from PyPI — you lose the ability to grep SGLang source while triaging.
- Don't reuse the previous bump's venv. Stale `.so` files in site-packages cause non-obvious failures.
- Don't `uv pip install -e "python"` (no extras) on the SGLang checkout. The diffusion launch scripts will break two scripts in. Always `python[diffusion]`.
- Don't skip the `uv pip install maturin nixl` preflight. Fresh venv has neither, and `maturin develop --uv` will `command not found` while dynamo workers will fail at import on `nixl`.
- Don't keep editing without re-running the failing script. The fix is only real once the script PASSes end-to-end.
- Don't bundle drive-by infra cleanups (default-model TODOs, renames, unrelated reformatting) into the bump PR. They make review harder and obscure which fix corresponds to which breakage. **Exceptions:** (a) container runtime image tags — these ship *in* the bump PR (see Step 12); (b) features gated on the new version floor (e.g. dashboard panels that need new metrics) can be bundled if the user explicitly asks, since those couldn't ship before this PR by definition.
- Don't skip a script silently for non-GPU reasons. Either fix it or record why it was skipped.
- Don't add `try: from sglang...new_path except ImportError: from sglang...old_path` blocks inside handler / init / register modules. Every SGLang import-shape change goes in `_compat.py`. The component is supposed to import SGLang either directly (when stable) or from `_compat` (when version-dependent), never via inline try/except.
- Don't gate on `sglang.__version__`. Use `try/except ImportError` for moved symbols and `inspect.signature` / `getattr` probing for changed signatures.
- Don't add a `_compat.py` fallback branch without a `# Fallback for sglang <ver>. Remove when min supported version is <next>+` comment. Untagged branches accrete forever.
- Don't leave fallback branches for versions older than N-1. Pruning them is part of the bump, not a separate cleanup.
- Don't push without running `uvx pre-commit run --all-files` first. The `Report pytest markers` hook walks every test file in the isolated pre-commit venv and trips on any unconditional `sglang.srt.*` import that isn't in `tests/report_pytest_markers.py`'s mock list. Local pytest passes (sglang is installed) so the failure only shows up in pre-commit / CI.
- Don't accept ruff/black auto-reformatting of unrelated lines in files you touched. Revert the noise lines before committing — the bump PR is already wide; reformatting unrelated `assert isinstance(...)` blocks just buries the real changes.
