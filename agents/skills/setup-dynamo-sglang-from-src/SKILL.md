---
name: setup-dynamo-sglang-from-src
description: Build and run NVIDIA Dynamo with an editable SGLang backend from exact source checkouts. Use after access-compute creates an isolated session, or when the user supplies dedicated Dynamo and SGLang roots on a GPU host.
---

# Set Up Dynamo and SGLang From Source

Build from two exact source checkouts. Do not clone into shared home paths or reuse another checkout's virtual environment.

## Required Inputs

Set both roots before the build:

```bash
export DYNAMO_ROOT=<session-root>/dynamo
export SGLANG_ROOT=<session-root>/sglang
```

The caller must also record the expected commit SHA for each repository.

## Inspect Before Changes

```bash
git -C "$DYNAMO_ROOT" status --short
git -C "$DYNAMO_ROOT" rev-parse HEAD
git -C "$SGLANG_ROOT" status --short
git -C "$SGLANG_ROOT" rev-parse HEAD
nvidia-smi
command -v uv
command -v cargo
command -v rustc
command -v protoc
command -v cmake
command -v nats-server
command -v etcd
command -v nvcc
```

Stop if a checkout is dirty or a commit does not match the requested SHA. Report missing host prerequisites. Do not install host packages, CUDA, NATS, or etcd without user approval.

## Prepare the Build Shell

Use the session note's limits when they exist. These defaults prevent known failures on high-core hosts.

```bash
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
ulimit -n "${BUILD_NOFILE_LIMIT:-65536}"
export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-32}"
```

Create one virtual environment owned by the Dynamo session checkout:

```bash
cd "$DYNAMO_ROOT"
uv venv .venv
source .venv/bin/activate
uv pip install "maturin[patchelf]"
```

Do not copy, link, or activate a virtual environment from another checkout.

## Build Dynamo

```bash
cd "$DYNAMO_ROOT/lib/bindings/python"
CARGO_TARGET_DIR="$DYNAMO_ROOT/target" maturin develop --uv
cd "$DYNAMO_ROOT"
uv pip install -e .
```

Keep `CARGO_TARGET_DIR` inside the session checkout.

## Install SGLang

Install SGLang into the Dynamo session runtime environment:

```bash
source "$DYNAMO_ROOT/.venv/bin/activate"
cd "$SGLANG_ROOT"
uv pip install -e "python"
```

This virtual environment belongs to the session. Do not create or mutate a shared SGLang virtual environment.

## Make Sure That the Build Works

```bash
source "$DYNAMO_ROOT/.venv/bin/activate"
python - <<'PY'
import pathlib
import torch
import dynamo._core
import dynamo.sglang
import sglang

print("dynamo:", pathlib.Path(dynamo._core.__file__).resolve())
print("dynamo.sglang:", pathlib.Path(dynamo.sglang.__file__).resolve())
print("sglang:", pathlib.Path(sglang.__file__).resolve())
print("torch:", torch.__version__)
print("cuda:", torch.cuda.is_available())
PY
git -C "$DYNAMO_ROOT" rev-parse HEAD
git -C "$SGLANG_ROOT" rev-parse HEAD
```

Both import paths must resolve inside the session root. CUDA must be available before a GPU run.

## Run

Use the closest launch script in the checked-out Dynamo revision. Use the source note for shared services, ports, caches, and CUDA paths.

Run the server inside the `tmux` session that `access-compute` owns. Write logs and artifacts inside the remote session root.

After launch, make sure that the health endpoint and one small inference request work. Record the exact commits, command, logs, and response.
