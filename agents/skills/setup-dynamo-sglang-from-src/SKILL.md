---
name: setup-dynamo-sglang-from-src
description: "Build and run NVIDIA Dynamo with SGLang backend from source on a fresh Ubuntu VM — includes all dependency troubleshooting."
version: 1.0.0
author: OWL (via ishandhanani session)
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [dynamo, sglang, nvidia, inference, llm, backend, devops, setup]
    related_skills: [hermes-agent]
---

# Setup Dynamo + SGLang from Source

Build and run [NVIDIA Dynamo](https://github.com/ai-dynamo/dynamo) with the SGLang backend from source on a fresh Ubuntu VM. This skill captures every dependency, pitfall, and fix discovered during a real setup on an L4 GPU VM.

## When to use

- Setting up Dynamo for the first time on a fresh Ubuntu VM
- Installing SGLang as a Dynamo backend
- Running the `agg.sh` launch script for aggregated serving
- Troubleshooting Dynamo/SGLang build or runtime failures

## Prerequisites

- Ubuntu 22.04 VM with an NVIDIA GPU (tested on L4 24GB)
- `sudo` access
- Python 3.11+
- Internet access (to clone repos and download models)

## Step 1: Clone Dynamo

```bash
git clone https://github.com/ai-dynamo/dynamo.git
cd dynamo
```

> **Note:** SSH clone (`git@github.com:...`) requires an SSH key on the VM. Use HTTPS if no key is configured.

## Step 2: Install uv and create venv

```bash
# Install uv if not present
pip3 install uv

# Create virtual environment
uv venv
```

## Step 3: Install nixl and maturin

```bash
source .venv/bin/activate
uv pip install nixl maturin
```

> **Important:** Always `source .venv/bin/activate` first, or `uv pip install` resolves to the currently-active Python (Hermes' own venv or system Python), NOT the project `.venv`.
>
> ```bash
> uv pip install nixl maturin                                # WRONG — may hit Hermes venv
> source .venv/bin/activate && uv pip install nixl maturin   # RIGHT
> ```

## Step 4: Build the Rust Python bindings

```bash
cd lib/bindings/python
source /home/ubuntu/dynamo/.venv/bin/activate
source "$HOME/.cargo/env"   # if Rust was just installed
maturin develop --uv
cd ../..
```

### Dependencies that may be missing:

**Rust (rustc/cargo):**
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source "$HOME/.cargo/env"
```

**protobuf-compiler (protoc):**
```bash
sudo apt-get install -y protobuf-compiler
```

**libclang (for bindgen):**
```bash
sudo apt-get install -y libclang-dev
export LIBCLANG_PATH=/usr/lib/llvm-14/lib   # adjust path as needed
```

**cmake (if a C dep needs it):**
```bash
sudo apt-get install -y cmake
```

> **patchelf warning is non-fatal.** `Warning: Failed to set rpath ... Failed to execute 'patchelf'` does not block the build — the wheel installs fine. Only if it actually fails: `uv pip install maturin[patchelf]`.

## Step 5: Install Dynamo in editable mode

```bash
source .venv/bin/activate
uv pip install -e .
```

## Step 6: Clone and install SGLang

```bash
cd /home/ubuntu
git clone https://github.com/sgl-project/sglang.git
cd sglang/python
source /home/ubuntu/dynamo/.venv/bin/activate
uv pip install -e .
```

> **Note:** SGLang install may downgrade some packages (torch, numpy, etc.). This is expected.

## Step 7: Install infrastructure dependencies

Dynamo requires NATS and etcd for service discovery:

### NATS
```bash
curl -L https://github.com/nats-io/nats-server/releases/download/v2.10.20/nats-server-v2.10.20-linux-amd64.tar.gz -o /tmp/nats.tar.gz
tar xzf /tmp/nats.tar.gz -C /tmp
sudo mv /tmp/nats-server-v2.10.20-linux-amd64/nats-server /usr/local/bin/
nats-server -js -D --addr 127.0.0.1 --port 4222 &
```

### etcd
```bash
ETCD_VER=v3.5.17
curl -L https://storage.googleapis.com/etcd/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz -o /tmp/etcd.tar.gz
tar xzf /tmp/etcd.tar.gz -C /tmp
sudo mv /tmp/etcd-${ETCD_VER}-linux-amd64/etcd /usr/local/bin/
sudo mv /tmp/etcd-${ETCD_VER}-linux-amd64/etcdctl /usr/local/bin/
etcd --listen-client-urls http://0.0.0.0:2379 --advertise-client-urls http://0.0.0.0:2379 &
```

Verify both are running:
```bash
etcdctl endpoint health
printf "CONNECT {}\r\nPING\r\n" | timeout 2 nc 127.0.0.1 4222
```

## Step 8: Install CUDA toolkit (for flashinfer JIT)

The SGLang flashinfer backend needs `nvcc` to compile CUDA kernels at runtime. On an L4 (sm_89), CUDA 11.5 is too old — you need CUDA 11.8+.

```bash
# Add NVIDIA package repo
wget -q https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb -O /tmp/cuda-keyring.deb
sudo dpkg -i /tmp/cuda-keyring.deb
sudo apt-get update
sudo apt-get install -y cuda-toolkit-13-0

# Symlink so flashinfer finds nvcc at /usr/local/cuda
sudo ln -sf /usr/local/cuda-13.0 /usr/local/cuda
```

## Step 9: Run the SGLang backend agg.sh

```bash
cd /home/ubuntu/dynamo
source .venv/bin/activate
export CUDA_HOME=/usr/local/cuda
bash examples/backends/sglang/launch/agg.sh
```

The script will:
1. Start the Dynamo frontend on port 8000
2. Start the SGLang worker with the default model (`Qwen/Qwen3-0.6B`)
3. Download the model from HuggingFace on first run (~1.2GB)
4. Capture CUDA graphs (takes ~60s)

### To use a different model:

```bash
bash examples/backends/sglang/launch/agg.sh --model-path Qwen/Qwen3-8B
```

### Models that fit on L4 (24GB VRAM):

| Model | Size | VRAM | Fits? |
|-------|------|------|-------|
| Qwen/Qwen3-0.6B | 0.6B | ~1.2GB | ✅ |
| Qwen/Qwen3-1.7B | 1.7B | ~4GB | ✅ |
| Qwen/Qwen3-4B | 4B | ~9GB | ✅ |
| Qwen/Qwen3-8B | 8B | ~17GB | ✅ (tight) |
| Qwen/Qwen3-14B | 14B | ~30GB | ❌ |

## Step 10: Test inference

```bash
# Non-streaming chat
curl -s http://localhost:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "Qwen/Qwen3-0.6B",
    "messages": [{"role": "user", "content": "Hello!"}],
    "max_tokens": 32
  }'

# Streaming chat
curl -s http://localhost:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "Qwen/Qwen3-0.6B",
    "messages": [{"role": "user", "content": "Hello!"}],
    "max_tokens": 32,
    "stream": true
  }'

# Completions endpoint
curl -s http://localhost:8000/v1/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "Qwen/Qwen3-0.6B",
    "prompt": "The capital of France is",
    "max_tokens": 16
  }'
```

## Common errors and fixes

| Error | Cause | Fix |
|-------|-------|-----|
| `Host key verification failed` | No SSH key / known_hosts | Use HTTPS clone instead |
| `rustc not installed` | No Rust toolchain | Install via rustup |
| `Could not find protoc` | Missing protobuf-compiler | `sudo apt install protobuf-compiler` |
| `Unable to find libclang` | Missing libclang | `sudo apt install libclang-dev` + set `LIBCLANG_PATH` |
| `Failed to connect to NATS` | NATS server not running | Start nats-server |
| `Unable to create lease. Check etcd` | etcd not running | Start etcd |
| `Could not find nvcc` | CUDA toolkit missing or wrong path | Install CUDA toolkit, symlink `/usr/local/cuda` |
| `Capture cuda graph failed: nvcc` | CUDA toolkit too old for GPU arch | Install CUDA 11.8+ (13.0 recommended) |
| Exit code 137 (OOM) | GPU out of memory | Use smaller model or reduce `--mem-fraction-static` |
| `No module named cupy` | cupy not installed | Non-critical warning; SGLang falls back to numpy |

## Verification

```bash
source .venv/bin/activate
python -c "
import dynamo._core; print('_core: OK')
import dynamo.sglang; print('dynamo.sglang: OK')
import sglang; print('sglang:', sglang.__version__)
import torch; print('torch:', torch.__version__, '| CUDA:', torch.cuda.is_available())
"
```
