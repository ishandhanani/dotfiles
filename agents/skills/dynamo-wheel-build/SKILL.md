---
name: dynamo-wheel-build
description: Build Dynamo Python wheels on Modal with a shared sccache and pre-baked NVMe target image instead of on the host. Use for rebuilding ai_dynamo_runtime wheels, offloading Rust compile CPU/disk from a constrained host, or building in a checkout that has no local Rust toolchain. Faster than local builds once warm and leaves zero build artifacts on the host.
---

# Dynamo Wheel Build

Offload `lib/bindings/python` maturin builds to Modal. All Rust caches (`CARGO_HOME`, `CARGO_TARGET_DIR`, baseline source tree) are baked into the Modal container image on local NVMe, and `sccache` persists on Modal volume `dynamo-build-cache` across branches/machines. The host keeps no `target/` dir, no `CARGO_HOME` growth, and no Rust toolchain.

## Prerequisites

- `modal` CLI (`uv tool install modal`) and `zstd` (`apt-get install -y zstd`), authenticated to the `nvidia` workspace (`modal token new --profile nvidia`; the browser session must be signed in to nvidia, not a personal account), environment `dynamo` (`modal config set-environment dynamo`).
- Build script: `dynamo_build.py` in this skill's directory (also symlinked at `~/modal/dynamo_build.py`). It defaults to `~/dynamo`; override with `DYNAMO_SRC`.

## Build and install

```bash
wheel_out="$(mktemp -d)"
DYNAMO_OUT_DIR="$wheel_out" DYNAMO_SRC=/path/to/worktree modal run <skill-dir>/dynamo_build.py
uv pip install --python <venv>/bin/python "$wheel_out"/ai_dynamo_runtime-*.whl
rm -rf "$wheel_out"                                 # reclaim host space
```

Additional modes:

```bash
modal run <skill-dir>/dynamo_build.py                       # builds ~/dynamo -> ./wheels/
DYNAMO_CGU=1 modal run <skill-dir>/dynamo_build.py          # max-perf build (codegen-units=1)
DYNAMO_SAVE_VOLUME=1 modal run <skill-dir>/dynamo_build.py  # also archive wheel to Modal volume 'dynamo-wheels'
modal run <skill-dir>/dynamo_build.py --seed-cache          # initialize/refresh /cache/base_src.tar.zst + warm_layer.tar.zst
```

For Dynamo venvs this replaces the `maturin develop --uv` step: install the wheel, then `uv pip install -e <root>` for the pure-Python layer.

If fetching a previously archived wheel from the `dynamo-wheels` volume (`DYNAMO_SAVE_VOLUME=1`):

```bash
wheel_out="$(mktemp -d)"
modal volume get dynamo-wheels <tag> "$wheel_out"
uv pip install --python <venv>/bin/python "$wheel_out"/**/ai_dynamo_runtime-*.whl
rm -rf "$wheel_out"
```

## Architecture

```text
host worktree (any state, including staged & untracked files)
  |  local SHA256 diff vs ~/.cache/dynamo-modal-build/base_hashes_*.json (~340ms)
  |  sends ONLY modified/added file bytes (~KB) + deleted paths over Modal RPC
  v
Modal function: 32 vCPU, 64 GiB, ubuntu:22.04 + rust 1.96.1 + maturin + sccache + mold
  |  /src/dynamo, /build/cargo, /build/target pre-baked on local container NVMe (0 FUSE reads)
  |  writes delta to /src/dynamo, runs `maturin build --release --compression-method stored --auditwheel skip`
  |  SCCACHE_DIR=/cache/sccache on volume dynamo-build-cache (shared across machines/branches)
  |  compresses .whl over wire with 32-core `zstd -1 -T0`
  v
host decompresses .whl into $DYNAMO_OUT_DIR (./wheels/ by default)
```

- Measured on cold Modal worker: **3.3s** `remote_build` (**13.9s** end-to-end wall clock including container start and wheel download).
- Base is `ubuntu:22.04` (glibc 2.35) and wheel is `cp311-abi3` (`linux_x86_64`): installs on glibc 2.35 devboxes and glibc 2.39 sglang runtime images across Python >= 3.11.

## Host-space rules

- Never run `cargo build` / `maturin` locally when the point is just to get a wheel; that creates multi-GB `target/` dirs.
- Delete fetched wheels (`rm -rf "$wheel_out"`) after `uv pip install` copies them into the venv.

## Gotchas

- Env `RUSTFLAGS` replaces `.cargo/config.toml` rustflags entirely — the image re-adds `target-cpu=x86-64-v3`, `force-frame-pointers`, `--cfg tokio_unstable`. Keep them in sync if the repo flags change.
- `protoc` must come from the upstream release zip (jammy's apt protoc 3.12 rejects proto3 optional), and both `bin/` and `include/` must be installed.
- `Environment 'X' not found`: set `modal config set-environment dynamo`.
- Missing `/cache/warm_layer.tar.zst` or `/cache/base_src.tar.zst` on a brand-new volume: run `modal run <skill-dir>/dynamo_build.py --seed-cache` once to populate the volume.
