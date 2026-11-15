# Cargo commands

`dynamo_cargo.py` runs any shell command for a Dynamo worktree on Modal: `cargo check`, `clippy`, `test`, `tree`, `metadata`, or several chained with `&&`. One deployed app, `dynamo-cargo`, serves every caller, so no app is created per run.

## Run

```bash
DYNAMO_SRC=/path/to/worktree <skill-dir>/dynamo_cargo.py "cargo check --workspace --all-targets && cargo test -p dynamo-llm --no-fail-fast"
```

- The command runs with `bash -c` in `/src/dynamo`, so `cd lib/bindings/python && cargo check --locked` works.
- The complete output goes to a log file (default `/tmp/dynamo_cargo.<slot>.<random>.log`, unique per call, or `DYNAMO_CARGO_LOG`). The script prints the path. There is no live stream.
- The script's exit code is the remote command's exit code.
- What is sent: tracked plus untracked non-ignored files, minus top-level `recipes/`, `docs/`, `benchmarks/`, `container/`. Uncommitted edits are included, so the run reflects the working tree, not `HEAD`.

| Variable | Meaning | Default |
|---|---|---|
| `DYNAMO_SRC` | Worktree to build | `~/dynamo` |
| `DYNAMO_CARGO_SLOT` | Slot name | basename of `DYNAMO_SRC` |
| `DYNAMO_CARGO_LOG` | Where the complete output is written | `/tmp/dynamo_cargo.<slot>.<random>.log` |

## How it stays warm

```text
caller A (worktree x) ──┐                         ┌─ slot x: container with /src/dynamo + /build/target
caller B (worktree y) ──┼─> deployed app ─────────┼─ slot y: container with /src/dynamo + /build/target
caller C (worktree x) ──┘   dynamo-cargo          └─ ...
                                  │
                                  └─ volume dynamo-build-cache: sccache, cargo registry, base snapshot
```

- **Slot.** A name, by default the worktree directory name. Each slot is one container that keeps its source tree and target dir on local NVMe between calls. Calls to one slot run one at a time; calls to different slots run in parallel.
- **Sync.** Each call syncs the worktree by checksum. Only files whose content changed get a new mtime, so cargo rebuilds only what depends on them. Files that the build generates inside the tree are left alone; files you delete from the worktree are deleted remotely.
- **Incremental.** Workspace crates build incrementally. Registry dependencies come from the shared `sccache`.
- **Base snapshot.** A new slot, or one whose container stopped, restores the shared snapshot of a built tree and then syncs to the caller's worktree, so it rebuilds only the difference.
- **Idle.** A slot's container stops after 20 idle minutes. Containers are billed while idle.

## Measured

On the `dynamo-llm` test cycle (`cargo test -p dynamo-llm`), 32 vCPU:

| Situation | Build | Tests |
|---|---|---|
| Cold container, no base snapshot | 406 s | 101 s |
| Nothing changed | 1 s | 97 s |
| One-line edit in `dynamo-llm` | 38 s | 96 s |
| One-line edit in `dynamo-http-server` | 41 s | 96 s |

New slot, starting from the base snapshot (12.3 GB compressed; the target dir is 40 GB with test, check and clippy artifacts):

| Step | Time |
|---|---|
| Restore the base snapshot | 88 to 102 s |
| Build an unchanged tree after the restore (test build plus workspace check) | 7 to 14 s |
| Save a base snapshot | 82 to 114 s |
| Build the base from nothing: test build, workspace check, clippy | 307 s + 199 s + 204 s |

A fresh container per run, the previous approach, took 390 to 460 s every time: `dynamo-llm` is about 360k lines in one crate, and neither its library after an edit nor its test executable can come from `sccache`.

## Maintenance

```bash
modal deploy <skill-dir>/dynamo_cargo.py                              # once, and after editing the script
DYNAMO_SRC=<worktree on main> <skill-dir>/dynamo_cargo.py --save-base  # refresh the shared base snapshot from this slot
DYNAMO_SRC=<worktree> <skill-dir>/dynamo_cargo.py --reset              # delete this slot's tree and target dir
```

- Refresh the base snapshot from a slot that has just built and tested current `main`. Do it after large upstream changes; a stale base still works, it only rebuilds more.
- Redeploying restarts every slot's container. The next call in each slot restores the base snapshot.

## Gotchas

- Never set `CARGO_INCREMENTAL` in the image environment: `sccache` refuses to run when the variable exists. The dev and test profiles already make workspace crates incremental.
- Env `RUSTFLAGS` replaces the repo's `.cargo/config.toml` flags. The image re-adds `target-cpu=x86-64-v3`, `force-frame-pointers` and `--cfg tokio_unstable`; keep them in sync with the repo.
- The image has clippy, rustfmt, mold and protoc. It has no GPU, NIXL or CUDA toolkit, and no `cargo machete` (run machete on the host; it only reads sources).
- Two worktrees with the same directory name share a slot. Set `DYNAMO_CARGO_SLOT` to keep them apart.
- Take a baseline and its comparison run in the same slot when you compare timings; test results do not depend on the slot.
