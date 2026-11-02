---
name: dynamo-wheel-build
description: Build Dynamo Python wheels on Modal with a shared sccache instead of on the host. Use for rebuilding ai_dynamo_runtime wheels, offloading Rust compile CPU/disk from a constrained host, or building in a checkout that has no local Rust toolchain. Faster than local builds once warm and leaves zero build artifacts on the host.
---

# Dynamo Wheel Build

Offload `lib/bindings/python` maturin builds to Modal. All caches (cargo registry, cargo target, sccache) live on remote Modal volumes, so the host keeps no `target/` dir, no `CARGO_HOME` growth, and no toolchain. The only host artifact is the wheel itself (~68 MB), which can be deleted after install.

## Prerequisites

- `modal` CLI (`uv tool install modal`), authenticated to the `nvidia` workspace (`modal token new --profile nvidia`; the browser session must be signed in to nvidia, not a personal account), environment `dynamo` (`modal config set-environment dynamo`).
- Build script: `dynamo_build.py` in this skill's directory (copy or invoke by absolute path). It defaults to `~/dynamo`; override with `DYNAMO_SRC`.

## Build

```bash
modal run <skill-dir>/dynamo_build.py                      # builds ~/dynamo (dirty worktree OK)
DYNAMO_SRC=/path/to/worktree modal run <skill-dir>/dynamo_build.py
DYNAMO_CGU=1 modal run <skill-dir>/dynamo_build.py         # max-perf build (codegen-units=1, slower)
```

Output goes to Modal volume `dynamo-wheels` under `<sha>-d<diffhash>/`. The script prints the exact fetch command. Measured on devbox: ~4 s warm no-change, ~1-2 min typical rebuild, ~8 min cold; ~$0.04/min on 32 vCPU + 64 GiB.

## Fetch and install

```bash
modal volume get dynamo-wheels <tag> ./wheel-out     # downloads the .whl
uv pip install --python <venv>/bin/python ./wheel-out/**/ai_dynamo_runtime-*.whl
rm -rf ./wheel-out                                  # reclaim host space
```

For Dynamo venvs this replaces the `maturin develop --uv` step: install the wheel, then `uv pip install -e <root>` for the pure-Python layer.

## Architecture

```text
host worktree (any state)
  |  add_local_dir -> /src/dynamo   (content-hashed blobs; only diffs upload)
  v
Modal function: 32 vCPU, 64 GiB, ubuntu:22.04 + rust 1.96.1 + maturin + sccache + mold
  |  maturin build --release
  |     SCCACHE_DIR=/cache/sccache      <- volume dynamo-build-cache (shared across machines)
  |     CARGO_HOME=/cache/cargo         <- same volume (shared registry/git cache)
  |     CARGO_TARGET_DIR=/cache/target  <- same volume (warm builds skip unchanged crates)
  |     RUSTFLAGS=-C link-arg=-fuse-ld=mold + repo flags (see Gotchas)
  |     CARGO_PROFILE_RELEASE_CODEGEN_UNITS=16 (workspace default is 1)
  v
volume dynamo-wheels -> modal volume get -> host
```

- Base is `ubuntu:22.04` so wheels are `manylinux_2_35`: they install on glibc 2.35 hosts AND on the sglang runtime image (glibc 2.39). Do not raise the base image.
- Wheel is `cp311-abi3` — works on Python >= 3.11.
- Volumes are shared across all machines running this script; avoid two concurrent `maturin` builds (cargo file locks on the shared target dir will contend).

## Host-space rules

- Never run `cargo build` / `maturin` locally when the point is just to get a wheel; that creates multi-GB `target/` dirs.
- If a local `target/` exists in the worktree, `IGNORE` already excludes it from upload — do not delete it without asking.
- Delete fetched wheels after `uv pip install` copies them into the venv.

## Gotchas

- Env `RUSTFLAGS` replaces `.cargo/config.toml` rustflags entirely — the image re-adds `target-cpu=x86-64-v3`, `force-frame-pointers`, `--cfg tokio_unstable`. Keep them in sync if the repo flags change.
- `protoc` must come from the upstream release zip (jammy's apt protoc 3.12 rejects proto3 optional), and both `bin/` and `include/` must be installed.
- `Environment 'X' not found`: set `modal config set-environment dynamo`.
- Wheel won't install (`platform incompatible`): compare host `platform.libc_ver()` vs the wheel's `manylinux_X_YY` tag.
- Full remote logs: `modal app logs dynamo-wheel-build` or the `https://modal.com/apps/nvidia/dynamo/ap-...` URL printed at run start.
