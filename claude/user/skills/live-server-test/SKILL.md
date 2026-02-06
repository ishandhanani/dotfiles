---
name: live-server-test
description: Launch Dynamo+SGLang servers from example scripts, send test traffic, and validate
user-invocable: true
disable-model-invocation: true
---

# Live Server Test

Launch a Dynamo+SGLang serving stack using the example launch scripts, send test traffic, and validate the results.

## Current State

!`nvidia-smi --query-gpu=index,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null || echo "no GPUs detected"`

!`ps aux | grep -E 'dynamo\.|sglang' | grep -v grep | head -10 || echo "no running servers"`

## Available Launch Scripts

All scripts are in `~/dynamo/examples/backends/sglang/launch/`. Read the script before running to check model path and GPU requirements.

### Aggregated (single worker)

| Script | GPUs | What it does |
|---|---|---|
| `agg.sh` | 1 | Basic aggregated inference. Default model: `Qwen/Qwen3-0.6B`. Supports `--model-path`, `--enable-otel`. |
| `agg_embed.sh` | 1 | Embedding model. Fixed model: `Qwen/Qwen3-Embedding-4B`. |
| `agg_router.sh` | 2 | Aggregated with KV-aware routing. Two workers on separate GPUs. Supports `--enable-otel`, `--approx`. |

### Disaggregated (prefill/decode separation)

| Script | GPUs | What it does |
|---|---|---|
| `disagg.sh` | 2 | Basic disagg. Prefill on GPU 0, decode on GPU 1. Transfer backend: nixl. |
| `disagg_router.sh` | 4 | Disagg with KV routing. 2 prefill + 2 decode workers. ZMQ event publishing. |
| `disagg_same_gpu.sh` | 1 | Disagg on single GPU with memory fraction splitting. Needs >= 16GB VRAM. |

### Multimodal

| Script | GPUs | What it does |
|---|---|---|
| `multimodal_epd.sh` | 2 | Multimodal single-worker. Default model: `Qwen/Qwen2.5-VL-7B-Instruct`. |
| `multimodal_disagg.sh` | 3 | Multimodal disaggregated. Processor + encode + prefill + decode workers. |

### Specialized

| Script | GPUs | What it does |
|---|---|---|
| `diffusion_llada.sh` | 1 | Diffusion LM (LLaDA2.0). Custom endpoint format. |

## Workflow

### 1. Pick a script

Ask the user which mode they want to test. If they don't specify, default to `agg.sh` (simplest, 1 GPU).

Before launching, read the script to confirm the model path and GPU assignment:
```bash
cat ~/dynamo/examples/backends/sglang/launch/<script>.sh
```

### 2. Check prerequisites

- Enough free GPU memory for the model (check nvidia-smi output above)
- No stale server processes (check ps output above)
- If stale processes exist, ask user before killing them

### 3. Launch

```bash
cd /home/ubuntu/dynamo && bash examples/backends/sglang/launch/<script>.sh &
```

### 4. Wait for readiness

Poll until the server responds:
```bash
for i in $(seq 1 120); do
    if curl -sf http://localhost:8000/v1/models > /dev/null 2>&1; then
        echo "Server ready after ${i}s"
        break
    fi
    sleep 1
done
```

### 5. Send test traffic

**Simple validation** (single request):
```bash
curl -s http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "default", "messages": [{"role": "user", "content": "Say hello in one sentence."}], "max_tokens": 32}'
```

**Load test** (aiperf):
```bash
aiperf benchmark \
  --endpoint http://localhost:8000/v1/chat/completions \
  --model default \
  --num-requests 50 \
  --concurrency 8
```

For embedding models, use the embeddings endpoint:
```bash
curl -s http://localhost:8000/v1/embeddings \
  -H "Content-Type: application/json" \
  -d '{"model": "default", "input": "test sentence"}'
```

For multimodal models, include image_url in the message content.

### 6. Validate

- Response is valid JSON with `choices` array
- No CUDA OOM or stack traces in server logs
- GPU memory looks reasonable (`nvidia-smi`)
- For KV router modes: check that KV events are flowing (look for `BlockStored` in logs)
- For disagg modes: check both prefill and decode workers are handling traffic

### 7. Teardown

```bash
pkill -f "dynamo\." && pkill -f "sglang" && sleep 2
# Verify cleanup
ps aux | grep -E 'dynamo\.|sglang' | grep -v grep
nvidia-smi
```

## Common Issues

- **Port in use**: `ss -tlnp | grep 8000` -- kill the stale process
- **CUDA OOM**: Model too large for available VRAM. Try `agg.sh` with `Qwen/Qwen3-0.6B` (smallest)
- **nixl errors in disagg**: Check that both GPUs are on the same node and NVLink/PCIe is available
- **Build stale**: If behavior doesn't match code changes, rebuild first: `cd ~/dynamo/lib/bindings/python && maturin develop --uv && cd /home/ubuntu/dynamo && uv pip install -e .`
