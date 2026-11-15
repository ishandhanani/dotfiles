---
name: dynamo-modal-build
description: Build and test Dynamo on Modal instead of on the host, with one cache shared by every agent and machine. Two pieces: wheel builds (ai_dynamo_runtime via maturin) and cargo commands (check, clippy, test, tree, metadata) for any worktree. Use for rebuilding wheels, running Rust checks or tests without a local target dir, and whenever several agents build Dynamo at once.
---

# Dynamo builds on Modal

Run Dynamo's Rust builds on Modal. The host keeps no `target/` dir and needs no Rust toolchain. Every caller shares one cache, so a crate compiled for one agent is not compiled again for the next.

| You want | Use | Reference |
|---|---|---|
| An `ai_dynamo_runtime` wheel to install into a venv | `dynamo_build.py` | [references/wheel.md](references/wheel.md) |
| `cargo check`, `clippy`, `test`, `tree`, `metadata` for a worktree | `dynamo_cargo.py` | [references/cargo.md](references/cargo.md) |

Read the reference for the piece you need before running it.

## Shared cache

Both pieces use the Modal volume `dynamo-build-cache` in the `nvidia` workspace, environment `dynamo`:

- `sccache`: compiled registry dependencies, shared across branches, agents and machines.
- Wheel builds: the baseline source tree and warm layer that are baked into the wheel image.
- Cargo commands: the cargo registry and a base snapshot (sources plus target dir) that new slots start from.

## Prerequisites

- `modal` CLI (`uv tool install modal`) and `zstd` (`apt-get install -y zstd`), authenticated to the `nvidia` workspace (`modal token new --profile nvidia`; the browser session must be signed in to nvidia, not a personal account), environment `dynamo` (`modal config set-environment dynamo`).
- `uv` on PATH: `dynamo_cargo.py` is a `uv run --script` file and installs its own `modal` client.

## Rules

- Do not run `cargo build`, `cargo test` or `maturin` on the host when Modal is available. A full Dynamo target dir is 25 to 70 GB.
- Do not create a Modal app per run for cargo work. `dynamo_cargo.py` calls one deployed app; if it reports the app is missing, deploy it once with `modal deploy <skill-dir>/dynamo_cargo.py`.
- One slot per worktree (the default). Agents that share a worktree share its slot and take turns.
- Read results from the log file the script names, not from a live stream.
